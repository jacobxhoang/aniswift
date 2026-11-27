import AuthenticationServices
import Combine
import Foundation
import Security
import UIKit

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

struct Page<Value> {
    let items: [Value]
    let more: Bool
    /// The provider's own count of every row behind a page, when it sent one:
    /// a friend's list screen reads it to say how much of the list it has.
    var total: Int? = nil
}

/// The redirect MyAnimeList sends back after sign-in. Every part is checked
/// before the code is exchanged: a foreign scheme or host, a repeated parameter
/// or a state that does not match the one this attempt generated must never be
/// treated as a completed sign-in.
enum MALCallback {
    static let scheme = "org.aniswift.ios"
    static let url = "\(scheme)://oauth"

    static func code(from url: URL, state: String) -> String? {
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let states = values.filter { $0.name == "state" }
        let codes = values.filter { $0.name == "code" }
        guard url.scheme == scheme, url.host == "oauth", url.path.isEmpty,
            url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
            states.count == 1, states.first?.value == state,
            codes.count == 1, let code = codes.first?.value, !code.isEmpty
        else { return nil }
        return code
    }
}

private struct MALSession: Codable {
    let clientID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

private final class MALTransport: NSObject, URLSessionTaskDelegate {
    // API and token endpoints are fixed. Never forward credentials through redirects.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum SessionKeychain {
    static let key: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.aniswift.ios",
        kSecAttrAccount as String: "mal-native-session"
    ]

    static func read() -> MALSession? {
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(MALSession.self, from: data)
    }

    static func write(_ session: MALSession?) throws {
        guard let session else {
            let status = SecItemDelete(key as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure() }
            return
        }
        let value = [kSecValueData as String: try JSONEncoder().encode(session)]
        let status = SecItemUpdate(key as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var query = key.merging(value) { _, new in new }
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw failure() }
        } else if status != errSecSuccess { throw failure() }
    }

    static func failure() -> APIError {
        APIError(status: 0, message: "Could not save the MyAnimeList session.")
    }
}

/// The catalog and MyAnimeList surface the app runs on. `Store` holds one of
/// these, so the sync, paging and cache paths can be exercised against a stub
/// instead of the network.
@MainActor
protocol APIClient: AnyObject {
    var hasSession: Bool { get }
    var configuredClientID: String? { get }
    var hasCachedCatalog: Bool { get }

    func session() async throws -> Account?
    func signIn(clientID: String) async throws -> Account
    func signOut() throws

    func list(_ kind: Kind, page: Int) async throws -> Page<ListEntry>
    func listEntry(_ title: Title) async throws -> ListEntry?
    func save(_ title: Title, change: ListChange?) async throws -> Fields?

    func catalog(_ path: String, _ query: [URLQueryItem], refresh: Bool) async throws -> Fields
    /// A friend's public activity, decoded on the thread that fetched it.
    func friendUpdates(
        _ friend: Friend, refresh: Bool
    ) async throws -> (updates: [FriendUpdate], freshness: CatalogFreshness)
    /// One page of a friend's public list, decoded on the thread that fetched it.
    func friendListPage(
        _ friend: Friend, kind: Kind, page: Int, limit: Int, refresh: Bool
    ) async throws -> Page<FriendUpdate>
    func titleNames(_ ids: [Int], kind: Kind) async -> [Int: String]
    func resolveTitle(_ title: Title) async -> Title?
    func cachedTitle(_ title: Title) -> Title?
    /// Whether a title's English name is already known, a batch that answered
    /// there is none included.
    func isNameResolved(_ title: Title) -> Bool
    func cachedDetail(_ title: Title) -> Fields?
    func savedDetail(_ title: Title) -> (fields: Fields, savedAt: Date)?
    func clearCatalogCache()

    func interestStacks(for title: Title, page: Int, refresh: Bool) async throws -> Page<InterestStack>
    func stackDetail(_ id: Int) async throws -> StackDetail
    func titleReviews(_ title: Title, page: Int) async throws -> Page<TitleReview>
}

@MainActor
final class API: APIClient {
    static let callbackScheme = MALCallback.scheme
    static let redirectURI = MALCallback.url
    private static let mal = URL(string: "https://api.myanimelist.net/v2")!
    private static let oauth = URL(string: "https://myanimelist.net/v1/oauth2")!
    private let tenrai = URL(string: "https://api.tenrai.org/v1")!
    private let jikan = URL(string: "https://jikan.lucashdo.com/v1")!
    private var malSession = SessionKeychain.read()
    private var sessionGeneration = UUID()
    private var signingIn = false
    private let transport = URLSession(configuration: .ephemeral, delegate: MALTransport(), delegateQueue: nil)
    private var privateQueue: Task<Void, Never>?
    private var cached: [URL: (Date, Fields)] = [:]
    private var cachedUpdates: [URL: (date: Date, updates: [FriendUpdate], freshness: CatalogFreshness)] = [:]
    private var cachedListPages: [URL: (date: Date, page: Page<FriendUpdate>)] = [:]
    private var catalogRequests: [URL: Task<(Fields, Data), Error>] = [:]
    private let catalogCacheLimit = 160
    private static let catalogLifetime: TimeInterval = 300
    /// User lists and friend activity change while the app is open, so they keep the short lifetime.
    private static let userLifetime: TimeInterval = 60
    private var titleLookups: [String: Task<Title?, Never>] = [:]
    private var activeTitleLookups = 0
    private var titleLookupWaiters: [CheckedContinuation<Void, Never>] = []
    private let titleLookupLimit = 6
    /// English titles for rows that carry only the original one, by `kind-id`,
    /// with the titles a batch answered as having none. Both outlive a launch,
    /// so a list opens named instead of a detail request per row.
    private var nameCache = TitleNameCache.read() ?? TitleNameCache()
    private var pendingNameSave: Task<Void, Never>?
    private static let nameCacheLimit = 4000
    /// Chunks of fifty ids asked for together, so a long list is named in one
    /// round of requests rather than one behind another.
    private static let nameChunks = 3

    static func url(_ base: URL, _ path: String, _ query: [URLQueryItem] = []) -> URL {
        let url = base.appending(path: path)
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        return parts.url!
    }

    private func request(_ request: URLRequest) async throws -> (Fields, Data) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server did not respond.")
        }
        let fields = try? JSONDecoder().decode(Fields.self, from: data)
        guard (200..<300).contains(http.statusCode), let fields else {
            throw APIError(status: http.statusCode, message: fields?.string("error") ?? "The request could not be completed.")
        }
        return (fields, data)
    }

    func catalog(_ path: String, _ query: [URLQueryItem] = [], refresh: Bool = false) async throws -> Fields {
        try Task.checkCancellation()
        let publicUserData = path.hasPrefix("users/")
        let cacheKey = Self.url(publicUserData ? jikan : tenrai, path, query)
        let lifetime = publicUserData ? Self.userLifetime : Self.catalogLifetime
        if !refresh, let (date, result) = cached[cacheKey], Date().timeIntervalSince(date) < lifetime { return result }
        if let pending = catalogRequests[cacheKey] {
            let (result, _) = try await pending.value
            try Task.checkCancellation()
            return result
        }

        let request = Task {
            try await fetchCatalog(path, query, publicUserData: publicUserData)
        }
        catalogRequests[cacheKey] = request
        defer { catalogRequests[cacheKey] = nil }
        let (result, data) = try await request.value
        if Self.isDetailPath(path) { Self.writeDetail(data, path: path) }
        cached[cacheKey] = (.now, result)
        if cached.count > catalogCacheLimit {
            let oldest = cached.sorted { $0.value.0 < $1.value.0 }
            for entry in oldest.prefix(cached.count - catalogCacheLimit) {
                cached.removeValue(forKey: entry.key)
            }
        }
        try Task.checkCancellation()
        return result
    }

    private func fetchCatalog(_ path: String, _ query: [URLQueryItem],
                              publicUserData: Bool) async throws -> (Fields, Data) {
        for base in publicUserData ? [jikan] : [tenrai, jikan] {
            do {
                let url = Self.url(base, path, query)
                return try await request(URLRequest(url: url, timeoutInterval: base == tenrai ? 5 : 10))
            } catch {
                try Task.checkCancellation()
                if base == jikan { throw error }
            }
        }
        throw APIError(status: 0, message: "Catalog unavailable.")
    }

    /// Only the bundled `/full` payload is kept: it is the one a title page
    /// draws, and it also carries the relations, links and theme songs, so a
    /// page opened without a connection is not left half empty.
    private static func isDetailPath(_ path: String) -> Bool {
        path.hasSuffix("/full") && (path.hasPrefix("anime/") || path.hasPrefix("manga/"))
    }

    private static func detailDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appending(path: "AniswiftDetailCache", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func detailFile(_ path: String) -> URL? {
        detailDirectory()?.appending(path: path.replacingOccurrences(of: "/", with: "-") + ".json")
    }

    private static func writeDetail(_ data: Data, path: String) {
        guard data.count < 2_000_000, let file = detailFile(path) else { return }
        SnapshotWriter.write(data, to: file)
    }

    /// The saved `/full` payload for a title page and the time it was written,
    /// for when the live request fails.
    func savedDetail(_ title: Title) -> (fields: Fields, savedAt: Date)? {
        guard let file = Self.detailFile("\(title.kind.rawValue)/\(title.malID)/full"),
              let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(Fields.self, from: data),
              let fields: Fields = decoded.read("data") else { return nil }
        let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        return (fields, written)
    }

    /// The most recent detail payload for a title, used to paint its page
    /// before the network answers. `/full` carries the same `data` node.
    func cachedDetail(_ title: Title) -> Fields? {
        let path = "\(title.kind.rawValue)/\(title.malID)"
        for key in [Self.url(tenrai, path), Self.url(tenrai, path + "/full")] {
            guard let (date, response) = cached[key],
                  Date().timeIntervalSince(date) < Self.catalogLifetime,
                  let fields: Fields = response.read("data") else { continue }
            return fields
        }
        return nil
    }

    /// The title as the name cache knows it: an English name already resolved
    /// fills the row, and the catalog's own cached detail fills the rest.
    func cachedTitle(_ title: Title) -> Title? {
        if let name = nameCache.names[title.id] { return title.fillingEnglishName(from: name) }
        return cachedDetail(title).flatMap { Title($0, kind: title.kind) }
    }

    /// Whether an English name for a title is already known, including a batch
    /// that answered there is none, so the row is not asked for again.
    func isNameResolved(_ title: Title) -> Bool {
        nameCache.names[title.id] != nil || nameCache.nameless.contains(title.id)
    }

    private func rememberName(_ name: String, key: String) {
        guard nameCache.names[key] != name else { return }
        nameCache.names[key] = name
        nameCache.nameless.remove(key)
        // A name is cheap to resolve again, so the oldest entries go first
        // rather than letting the file grow with every list ever opened.
        let overflow = nameCache.names.count - Self.nameCacheLimit
        if overflow > 0 {
            for entry in Array(nameCache.names.keys.prefix(overflow)) {
                nameCache.names.removeValue(forKey: entry)
            }
        }
        saveNamesSoon()
    }

    private func rememberNameless(_ key: String) {
        guard nameCache.names[key] == nil, nameCache.nameless.insert(key).inserted else { return }
        saveNamesSoon()
    }

    /// Writes once after a burst, so a page of fifty rows is one encode and one
    /// write instead of fifty of each.
    private func saveNamesSoon() {
        guard pendingNameSave == nil else { return }
        pendingNameSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.pendingNameSave = nil
            self.nameCache.write()
        }
    }

    /// Drops decoded catalog responses and the remembered English names, so
    /// Clear Cache also refreshes title pages and names rows from scratch.
    func clearCatalogCache() {
        cached.removeAll()
        cachedUpdates.removeAll()
        cachedListPages.removeAll()
        nameCache = TitleNameCache()
        pendingNameSave?.cancel()
        pendingNameSave = nil
        TitleNameCache.remove()
        if let directory = Self.detailDirectory() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Whether a decoded catalog response is still available to title pages.
    var hasCachedCatalog: Bool { !cached.isEmpty || !cachedUpdates.isEmpty || !cachedListPages.isEmpty }

    /// A friend's public activity, decoded off the main actor: `Fields` wraps a
    /// decoder container and cannot leave the thread that decoded it, so the rows
    /// are built where the bytes arrive and only values come back.
    func friendUpdates(
        _ friend: Friend, refresh: Bool
    ) async throws -> (updates: [FriendUpdate], freshness: CatalogFreshness) {
        let url = Self.url(jikan, "users/\(friend.name)/userupdates")
        if !refresh, let entry = cachedUpdates[url],
            Date().timeIntervalSince(entry.date) < Self.userLifetime
        {
            return (entry.updates, entry.freshness)
        }
        let data = try await Self.data(URLRequest(url: url, timeoutInterval: 10))
        let decoded = try await Self.decodeUpdates(data, friend: friend)
        cachedUpdates[url] = (.now, decoded.updates, decoded.freshness)
        if cachedUpdates.count > catalogCacheLimit {
            let oldest = cachedUpdates.sorted { $0.value.date < $1.value.date }
            for entry in oldest.prefix(cachedUpdates.count - catalogCacheLimit) {
                cachedUpdates.removeValue(forKey: entry.key)
            }
        }
        return decoded
    }

    /// One page of a friend's public list, decoded the same way. A pull to
    /// refresh passes `refresh` so the minute of cached pages is not handed back.
    func friendListPage(
        _ friend: Friend, kind: Kind, page: Int, limit: Int, refresh: Bool
    ) async throws -> Page<FriendUpdate> {
        let url = Self.url(jikan, "users/\(friend.name)/\(kind.rawValue)list", [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        if !refresh, let entry = cachedListPages[url], Date().timeIntervalSince(entry.date) < Self.userLifetime {
            return entry.page
        }
        let data = try await Self.data(URLRequest(url: url, timeoutInterval: 10))
        let result = try await Self.decodeListPage(data, friend: friend, kind: kind, page: page, limit: limit)
        cachedListPages[url] = (.now, result)
        if cachedListPages.count > catalogCacheLimit {
            let oldest = cachedListPages.sorted { $0.value.date < $1.value.date }
            for entry in oldest.prefix(cachedListPages.count - catalogCacheLimit) {
                cachedListPages.removeValue(forKey: entry.key)
            }
        }
        return result
    }

    /// The bytes of a request, fetched and checked off the main actor.
    nonisolated static func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server did not respond.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let fields = try? JSONDecoder().decode(Fields.self, from: data)
            throw APIError(status: http.statusCode,
                           message: fields?.string("error") ?? "The request could not be completed.")
        }
        return data
    }

    /// The rows a friend's activity payload describes. `nonisolated async` runs it
    /// on the cooperative pool rather than the caller's actor, so the parse never
    /// lands on the main thread.
    nonisolated static func decodeUpdates(
        _ data: Data, friend: Friend
    ) async throws -> (updates: [FriendUpdate], freshness: CatalogFreshness) {
        let response = try JSONDecoder().decode(Fields.self, from: data)
        let body: Fields? = response.read("data")
        let updates = Kind.allCases.flatMap { kind -> [FriendUpdate] in
            let entries: [Fields] = body?.read(kind.rawValue) ?? []
            return entries.compactMap { entry -> FriendUpdate? in
                guard let info: Fields = entry.read("entry"), let title = Title(info, kind: kind) else {
                    return nil
                }
                return FriendUpdate(friend: friend, title: title, fields: entry)
            }
        }
        return (updates, CatalogFreshness(response.read("meta")))
    }

    /// One page of a friend's list, built off the main actor. Every row is kept:
    /// Jikan Edge's list rows carry no `date` — only `updatedAt`, which is often
    /// null — and a friend's list screen draws them without one. The feed, which
    /// sorts and dates its rows, filters them where it reads them.
    nonisolated static func decodeListPage(
        _ data: Data, friend: Friend, kind: Kind, page: Int, limit: Int
    ) async throws -> Page<FriendUpdate> {
        let response = try JSONDecoder().decode(Fields.self, from: data)
        let body: Fields? = response.read("data")
        guard let rows: [Fields] = response.read("data") ?? body?.read("entries") else {
            throw APIError(status: 0, message: "Could not load this list.")
        }
        let meta: Fields? = response.read("meta")
        let pagination: Fields? = meta?.read("pagination") ?? response.read("pagination")
        let hasNext: Bool? = pagination?.read("hasNextPage", "has_next_page")
        let total: Int? = pagination?.read("total") ?? body?.read("total")
        let more = hasNext ?? (total.map { $0 > page * limit } ?? (rows.count == limit))
        let entries = rows.compactMap { row -> FriendUpdate? in
            guard let title = Title(row, kind: kind) else { return nil }
            return FriendUpdate(friend: friend, title: title, fields: row)
        }
        return Page(items: entries, more: more, total: total)
    }

    /// English titles for a batch of ids in as few requests as possible, and
    /// remembered. Tenrai's `ids` filter answers full rows fifty at a time,
    /// which replaces a detail request per row when a list only carries the
    /// original title; the chunks go out three at a time. A row the filter
    /// answered without an English name is remembered as having none, and a row
    /// it did not answer stays open, because the filter also leaves out titles
    /// it will not show.
    func titleNames(_ ids: [Int], kind: Kind) async -> [Int: String] {
        var names: [Int: String] = [:]
        var remaining: [Int] = []
        for id in Set(ids.filter { $0 > 0 }).sorted() {
            let key = "\(kind.rawValue)-\(id)"
            if let name = nameCache.names[key] {
                names[id] = name
            } else if !nameCache.nameless.contains(key) {
                remaining.append(id)
            }
        }
        while !remaining.isEmpty {
            if Task.isCancelled { return names }
            let batch = Array(remaining.prefix(Self.nameChunks * 50))
            remaining.removeFirst(batch.count)
            var chunks: [[Int]] = []
            var start = 0
            while start < batch.count {
                let end = min(start + 50, batch.count)
                chunks.append(Array(batch[start..<end]))
                start = end
            }
            await withTaskGroup(of: [Fields]?.self) { group in
                for chunk in chunks {
                    group.addTask {
                        let query = [
                            URLQueryItem(name: "ids", value: chunk.map(String.init).joined(separator: ",")),
                            URLQueryItem(name: "limit", value: String(chunk.count)),
                        ]
                        let response = try? await self.catalog(kind.rawValue, query, refresh: false)
                        return response?.read("data")
                    }
                }
                for await rows in group {
                    guard let rows else { continue }
                    for row in rows {
                        guard let id: Int = row.read("mal_id", "malId", "id") else { continue }
                        let key = "\(kind.rawValue)-\(id)"
                        if let name = row.englishTitle {
                            rememberName(name, key: key)
                            names[id] = name
                        } else {
                            rememberNameless(key)
                        }
                    }
                }
            }
        }
        return names
    }

    func resolveTitle(_ title: Title) async -> Title? {
        guard !Task.isCancelled else { return nil }
        if let cached = cachedTitle(title) { return cached }
        if let pending = titleLookups[title.id] { return await pending.value }

        let lookup = Task<Title?, Never> {
            await acquireTitleLookupSlot()
            defer { releaseTitleLookupSlot() }

            if let cached = cachedTitle(title) { return cached }
            let path = "\(title.kind.rawValue)/\(title.malID)"
            guard let response = try? await catalog(path, [], refresh: false),
                  let fields: Fields = response.read("data") else { return nil }
            let resolved = Title(fields, kind: title.kind)
            // One row's lookup names every other row that shows the same title.
            if let name = resolved?.englishName {
                rememberName(name, key: title.id)
            } else if resolved != nil {
                rememberNameless(title.id)
            }
            return resolved
        }
        titleLookups[title.id] = lookup
        defer { titleLookups[title.id] = nil }
        return await lookup.value
    }

    private func acquireTitleLookupSlot() async {
        if activeTitleLookups < titleLookupLimit {
            activeTitleLookups += 1
        } else {
            await withCheckedContinuation { continuation in
                titleLookupWaiters.append(continuation)
            }
        }
    }

    private func releaseTitleLookupSlot() {
        if titleLookupWaiters.isEmpty {
            activeTitleLookups -= 1
        } else {
            titleLookupWaiters.removeFirst().resume()
        }
    }

    // Serialize authenticated requests so refresh-token rotation and list edits stay ordered.
    private func privateRequest(_ path: String, _ query: [URLQueryItem] = [],
                                method: String = "GET", form: [String: String]? = nil) async throws -> Fields? {
        let previous = privateQueue
        let generation = sessionGeneration
        let job = Task { @MainActor in
            await previous?.value
            return try await self.sendPrivate(path, query, method: method, form: form, generation: generation)
        }
        privateQueue = Task { _ = try? await job.value }
        return try await job.value
    }

    private func sendPrivate(_ path: String, _ query: [URLQueryItem], method: String,
                             form: [String: String]?, generation: UUID) async throws -> Fields? {
        guard generation == sessionGeneration else { throw CancellationError() }
        guard let current = malSession else {
            throw APIError(status: 401, message: "Sign in with MyAnimeList to use your lists.")
        }
        let session = current.expiresAt.timeIntervalSinceNow < 60 ? try await renew(current, generation: generation) : current
        let url = Self.url(Self.mal, path, query)
        do {
            let fields = try await sendMAL(url, method: method, form: form, accessToken: session.accessToken)
            guard generation == sessionGeneration else { throw CancellationError() }
            return fields
        } catch let error as APIError where error.status == 401 {
            let refreshed = try await renew(session, generation: generation)
            let fields = try await sendMAL(url, method: method, form: form, accessToken: refreshed.accessToken)
            guard generation == sessionGeneration else { throw CancellationError() }
            return fields
        }
    }

    private func sendMAL(_ url: URL, method: String = "GET", form: [String: String]? = nil,
                         accessToken: String? = nil) async throws -> Fields? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let form {
            request.httpBody = Self.formBody(form)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "MyAnimeList did not respond.")
        }
        let fields = try? JSONDecoder().decode(Fields.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode,
                           message: fields?.string("error_description", "message", "error") ?? "MyAnimeList rejected the request.")
        }
        return fields
    }

    private static func formBody(_ parameters: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed)!.replacingOccurrences(of: "%20", with: "+")
        }
        return Data(parameters.sorted { $0.key < $1.key }.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&").utf8)
    }

    private func exchange(_ form: [String: String], clientID: String, previous: MALSession? = nil) async throws -> MALSession {
        var parameters = form
        parameters["client_id"] = clientID
        guard let result = try await sendMAL(Self.url(Self.oauth, "token"), method: "POST", form: parameters),
              let access = result.string("access_token"),
              let refresh = result.string("refresh_token") ?? previous?.refreshToken,
              let lifetime: Int = result.read("expires_in"), lifetime > 0 else {
            throw APIError(status: 0, message: "MyAnimeList returned an invalid session.")
        }
        return MALSession(clientID: clientID, accessToken: access, refreshToken: refresh,
                          expiresAt: Date().addingTimeInterval(TimeInterval(lifetime)))
    }

    private func renew(_ current: MALSession, generation: UUID) async throws -> MALSession {
        guard generation == sessionGeneration else { throw CancellationError() }
        let renewed: MALSession
        do {
            renewed = try await exchange(["grant_type": "refresh_token", "refresh_token": current.refreshToken],
                                         clientID: current.clientID, previous: current)
        } catch let error as APIError where error.status == 400 || error.status == 401 {
            guard generation == sessionGeneration else { throw CancellationError() }
            try signOut()
            throw APIError(status: 401, message: "Your MyAnimeList session expired. Sign in again.")
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        try SessionKeychain.write(renewed)
        malSession = renewed
        return renewed
    }

    /// The MyAnimeList client ID the build ships, read from Info.plist (CI
    /// injects it from a secret). The app has no field for it: a build signs
    /// in with the ID it was built with, so nothing has to be typed on a phone.
    var configuredClientID: String? {
        guard let bundled = Bundle.main.object(forInfoDictionaryKey: "AniswiftMALClientID") as? String else {
            return nil
        }
        let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var hasSession: Bool { malSession != nil }

    func session() async throws -> Account? {
        guard hasSession else { return nil }
        let fields = try await privateRequest("users/@me", [.init(name: "fields", value: "id,name,picture")])
        return try account(from: fields)
    }

    func signOut() throws {
        try SessionKeychain.write(nil)
        malSession = nil
        sessionGeneration = UUID()
    }

    func signIn(clientID rawID: String) async throws -> Account {
        guard !signingIn else { throw APIError(status: 0, message: "MyAnimeList sign-in is already open.") }
        signingIn = true
        defer { signingIn = false }
        let clientID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clientID.range(of: "^[A-Za-z0-9]{32}$", options: .regularExpression) != nil else {
            throw APIError(status: 0, message: "This build's MyAnimeList client ID is not a 32-character ID.")
        }
        let generation = sessionGeneration
        let verifier = try Self.randomProof()
        let state = try Self.randomProof()
        let start = Self.url(Self.oauth, "authorize", [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: Self.redirectURI), .init(name: "state", value: state),
            .init(name: "code_challenge", value: verifier), .init(name: "code_challenge_method", value: "plain"),
        ])
        let callback = try await LoginBrowser().authenticate(start, scheme: Self.callbackScheme)
        guard let code = MALCallback.code(from: callback, state: state) else {
            throw APIError(
                status: 0,
                message: "MyAnimeList sign-in did not complete. Check the registered redirect URL and try again.")
        }
        let next = try await exchange([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "code_verifier": verifier,
        ], clientID: clientID)
        let profileURL = Self.url(Self.mal, "users/@me", [.init(name: "fields", value: "id,name,picture")])
        let profile = try await sendMAL(profileURL, accessToken: next.accessToken)
        let user = try account(from: profile)
        guard generation == sessionGeneration else { throw CancellationError() }
        try SessionKeychain.write(next)
        sessionGeneration = UUID()
        malSession = next
        return user
    }

    private static func randomProof() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw APIError(status: 0, message: "Could not start MyAnimeList sign-in.")
        }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func account(from fields: Fields?) throws -> Account {
        guard let fields, let id: Int = fields.read("id"), id > 0, let name = fields.string("name") else {
            throw APIError(status: 0, message: "MyAnimeList returned an invalid account.")
        }
        return Account(id: id, name: name, image: fields.image)
    }

    private func titleFields(_ kind: Kind) -> String {
        let total = kind == .anime ? "num_episodes" : "num_chapters"
        // A list row draws its release year and, for a title still on the
        // air, when its next episode is due, so the payload carries the
        // status, the date it started and — for anime — the weekly slot.
        let airing = kind == .anime ? ",status,start_date,broadcast" : ",status,start_date"
        return "id,title,main_picture,alternative_titles,mean,media_type,\(total)\(airing)"
    }

    private func statusFields(_ kind: Kind) -> String {
        let fields = kind == .anime ? "num_episodes_watched,num_times_rewatched" : "num_chapters_read,num_times_reread"
        return "status,score,updated_at,start_date,finish_date,comments,\(fields)"
    }

    func list(_ kind: Kind, page: Int) async throws -> Page<ListEntry> {
        let result = try await privateRequest("users/@me/\(kind.rawValue)list", [
            .init(name: "fields", value: "list_status{\(statusFields(kind))},\(titleFields(kind))"),
            .init(name: "limit", value: "100"), .init(name: "offset", value: String((page - 1) * 100)),
            .init(name: "sort", value: "list_updated_at"), .init(name: "nsfw", value: "true"),
        ])
        guard let rows: [Fields] = result?.read("data") else {
            throw APIError(status: 0, message: "MyAnimeList returned an invalid list.")
        }
        let paging: Fields? = result?.read("paging")
        let items = rows.compactMap { row -> ListEntry? in
            guard let node: Fields = row.read("node"), let status: Fields = row.read("list_status"),
                  let title = Title(node, kind: kind), status.string("status") != nil else { return nil }
            return ListEntry(status, title: title)
        }
        return Page(items: items, more: paging?.string("next") != nil)
    }

    func listEntry(_ title: Title) async throws -> ListEntry? {
        guard let result = try await privateRequest("\(title.kind.rawValue)/\(title.malID)", [
            .init(name: "fields", value: "my_list_status{\(statusFields(title.kind))}"),
        ]) else { throw APIError(status: 0, message: "MyAnimeList returned an invalid entry.") }
        guard let entry: Fields = result.read("my_list_status"), entry.string("status") != nil else { return nil }
        return ListEntry(entry, title: title)
    }

    func save(_ title: Title, change: ListChange?) async throws -> Fields? {
        let path = "\(title.kind.rawValue)/\(title.malID)/my_list_status"
        guard let change else {
            _ = try await privateRequest(path, method: "DELETE")
            return nil
        }
        let progressField = title.kind == .anime ? "num_watched_episodes" : "num_chapters_read"
        var form = ["status": change.status, "score": String(change.rating), progressField: String(change.progress)]
        if let details = change.details {
            if let count = details.repeatCount {
                form[title.kind == .anime ? "num_times_rewatched" : "num_times_reread"] = String(count)
            }
            form["start_date"] = details.startDate
            form["finish_date"] = details.finishDate
            form["comments"] = details.notes
        }
        guard let response = try await privateRequest(path, method: "PUT", form: form),
              response.string("status") != nil else {
            throw APIError(status: 0, message: "MyAnimeList did not confirm the update.")
        }
        return response
    }
}

extension API {
    /// Stacks that contain this title. Tenrai answers 25 per page, and it is the
    /// only source that serves this path, so a first answer that failed is
    /// asked again rather than reported as a failure the reader has to clear.
    /// Adult stacks are asked for by name: the catalog hides them by default,
    /// and a title that is itself adult has no other stacks at all.
    func interestStacks(
        for title: Title, page: Int, refresh: Bool = false
    ) async throws -> Page<InterestStack> {
        let path = "\(title.kind.rawValue)/\(title.malID)/stacks"
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sfw", value: "false"),
            URLQueryItem(name: "sfw-strict", value: "false"),
        ]
        let response: Fields
        do {
            response = try await catalog(path, query, refresh: refresh)
        } catch {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(350))
            response = try await catalog(path, query, refresh: true)
        }
        let rows: [Fields] = response.read("data") ?? []
        let pagination: Fields? = response.read("pagination")
        let more: Bool = pagination?.read("has_next_page", "hasNextPage") ?? false
        return Page(items: unique(rows.compactMap(InterestStack.init)), more: more)
    }

    /// One stack with every entry it lists, adult entries included: the catalog
    /// hides them by default, and a stack whose titles are adult would read as
    /// an empty one.
    func stackDetail(_ id: Int) async throws -> StackDetail {
        let response = try await catalog(
            "stacks/\(id)",
            [URLQueryItem(name: "sfw", value: "false"), URLQueryItem(name: "sfw-strict", value: "false")],
            refresh: false)
        guard let detail = StackDetail(response) else {
            throw APIError(status: 0, message: "This stack could not be read.")
        }
        return detail
    }

    func titleReviews(_ title: Title, page: Int) async throws -> Page<TitleReview> {
        let path = "\(title.kind.rawValue)/\(title.malID)/reviews"
        let response = try await catalog(
            path,
            [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "spoilers", value: "true"),
                URLQueryItem(name: "preliminary", value: "true"),
            ], refresh: false)
        let data: Fields? = response.read("data")
        guard let rows: [Fields] = response.read("data") ?? data?.read("reviews", "items") else {
            throw APIError(status: 0, message: "Could not load reviews.")
        }
        let pagination: Fields? = response.read("pagination")
        let meta: Fields? = response.read("meta")
        let metaPagination: Fields? = meta?.read("pagination")
        let hasMore: Bool =
            pagination?.read("has_next_page", "hasNextPage")
            ?? metaPagination?.read("hasNextPage", "has_next_page") ?? false
        return Page(items: unique(rows.compactMap(TitleReview.init)), more: hasMore)
    }
}

func catalogPage(_ result: Fields, kind: Kind) -> Page<Title> {
    let body: Fields? = result.read("data")
    let entries: [Fields] = result.read("data") ?? body?.read("entries", "items", "anime") ?? []
    let pagination: Fields? = result.read("pagination")
    let meta: Fields? = result.read("meta")
    let metaPagination: Fields? = meta?.read("pagination")
    return Page(items: entries.compactMap { Title($0, kind: kind) },
                more: pagination?.read("has_next_page") ?? metaPagination?.read("hasNextPage") ?? false)
}

func recommendations(_ result: Fields, kind: Kind) -> [Title] {
    let entries: [Fields] = result.read("data") ?? []
    return entries.flatMap { item in
        if let children: [Fields] = item.read("entry", "entries") { return children }
        if let child: Fields = item.read("entry") { return [child] }
        return [item]
    }.compactMap { Title($0, kind: kind) }
}

@MainActor
private final class LoginBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private let window: UIWindow? = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
        .compactMap { $0.windows.first(where: \.isKeyWindow) }.first

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window!
    }

    func authenticate(_ start: URL, scheme: String) async throws -> URL {
        guard window != nil else { throw APIError(status: 0, message: "Bring Aniswift to the foreground and try again.") }
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let browser = ASWebAuthenticationSession(url: start, callbackURLScheme: scheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? APIError(status: 0, message: "Sign-in did not complete.")) }
            }
            browser.presentationContextProvider = self
            session = browser
            if !browser.start() {
                continuation.resume(throwing: APIError(status: 0, message: "Unable to start MyAnimeList sign-in."))
            }
        }
    }
}

/// A signed-in AniList account: the token its implicit grant returns, when it
/// ends, and the account the lists belong to.
struct AniListSession: Codable {
    var token: String
    var expiresAt: Date
    var id: Int = 0
    var name: String = ""
}

/// AniList hands its token back to a redirect URL the app does not register, so
/// the token is read from wherever it appears rather than from one callback: the
/// redirect's fragment or query, where MyAnimeList puts its code, or the text of
/// the auth-pin page.
enum AniListCallback {
    /// The token wherever AniList wrote it: the fragment of the redirect the app
    /// can name, the address of the page the client's redirect URL points at,
    /// or the auth-pin page's own text.
    static func token(in url: URL) -> String? {
        token(in: url.absoluteString) ?? jwt(in: url.absoluteString)
    }

    static func token(in text: String) -> String? {
        guard let marker = text.range(of: "access_token=") else { return nil }
        let value = text[marker.upperBound...].prefix { character in
            character != "&" && character != "#" && character != "\n" && character != "\""
                && character != " "
        }
        return value.isEmpty ? nil : String(value).removingPercentEncoding
    }

    /// The token on its own, as the auth-pin page writes it: an AniList token is
    /// a JWT, which starts `eyJ` and runs long, so the page's text is searched
    /// for one rather than for a name it does not print.
    static func jwt(in text: String) -> String? {
        let separators = CharacterSet(charactersIn: " \n\t\"'`<>,()[]")
        for chunk in text.components(separatedBy: separators) {
            let value = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("eyJ"), value.count > 40 { return value }
        }
        return nil
    }
}

/// One row of a signed-in account's AniList list, read-only: the media it
/// names, the status and progress AniList holds, and its score out of 100.
struct AniListEntry: Identifiable {
    /// The AniList media id, which the row is identified by.
    let id: Int
    /// The list entry's own id, which a delete asks for.
    let entryID: Int
    let malID: Int?
    let kind: Kind
    let name: String
    let original: String
    let image: URL?
    let status: String
    let progress: Int
    let total: Int?
    let score: Double

    init?(_ fields: Fields, kind: Kind) {
        guard let media: Fields = fields.read("media"), let id: Int = media.read("id") else { return nil }
        let title: Fields? = media.read("title")
        guard let original = title?.string("romaji") ?? title?.string("english") else { return nil }
        self.id = id
        entryID = fields.read("id") ?? 0
        malID = media.read("idMal")
        self.kind = kind
        self.original = original
        name = title?.string("english") ?? original
        let cover: Fields? = media.read("coverImage")
        image = cover.flatMap { publicURL($0.string("large")) }
        status = Self.statusLabel(fields.string("status"), kind: kind)
        progress = fields.read("progress") ?? 0
        let count: Int? = media.read(kind == .anime ? "episodes" : "chapters")
        total = count.flatMap { $0 > 0 ? $0 : nil }
        score = fields.read("score") ?? 0
    }

    /// The name a reader should see for the stored preferred-language setting.
    func displayName(for language: String) -> String {
        if language == TitleLanguage.romaji.rawValue { return original.isEmpty ? name : original }
        return name.isEmpty ? original : name
    }

    /// AniList's status values as the app names them.
    static func statusLabel(_ value: String?, kind: Kind) -> String {
        switch value?.uppercased() {
        case "CURRENT": kind == .anime ? "Watching" : "Reading"
        case "REPEATING": kind == .anime ? "Rewatching" : "Rereading"
        case "PLANNING": kind == .anime ? "Plan to watch" : "Plan to read"
        case "COMPLETED": "Completed"
        case "PAUSED": "On hold"
        case "DROPPED": "Dropped"
        default: value?.capitalized ?? "Other"
        }
    }

    var progressLabel: String? {
        if let total { return "\(progress)/\(total)" }
        return progress > 0 ? "\(progress)" : nil
    }

    /// A 100-point AniList score read on the app's 10-point scale, decimals
    /// kept: 85 is the 8.5 a reader scored, not an 8.
    var scoreLabel: String? {
        guard score > 0 else { return nil }
        let value = (score / 10).ledgerDecimal(0...1)
        return "★ \(value)/10"
    }
}

/// The AniList session, in the Keychain under the app's service: it is read
/// once when the client is built and written whenever the account changes.
private enum AniListKeychain {
    static let key: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.aniswift.ios",
        kSecAttrAccount as String: "anilist-session",
    ]

    static func read() -> AniListSession? {
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AniListSession.self, from: data)
    }

    static func write(_ session: AniListSession) throws {
        let value = [kSecValueData as String: try JSONEncoder().encode(session)]
        let status = SecItemUpdate(key as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var query = key.merging(value) { _, new in new }
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw failure() }
        } else if status != errSecSuccess {
            throw failure()
        }
    }

    static func remove() {
        SecItemDelete(key as CFDictionary)
    }

    static func failure() -> APIError {
        APIError(status: 0, message: "Could not save the AniList session.")
    }
}

/// The AniList section of Settings: one client that signs in through AniList's
/// implicit grant, reads the account's lists through its GraphQL API, and
/// carries MyAnimeList changes over. It runs one way — an AniList change is
/// never written back to MyAnimeList.
@MainActor
final class AniListClient: ObservableObject {
    static let shared = AniListClient()
    static let graphql = URL(string: "https://graphql.anilist.co")!
    static let authorize = URL(string: "https://anilist.co/api/v2/oauth/authorize")!

    @Published private(set) var session: AniListSession?
    @Published private(set) var entries: [AniListEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var connecting = false
    @Published private(set) var message: String?
    /// The AniList media and list entry ids by `Title.id`, learned from a sync
    /// or a lookup, so a change does not need a second request for them.
    private var mediaIDs: [String: Int] = [:]
    private var entryIDs: [String: Int] = [:]
    /// The changes queued for AniList, so two quick swipes reach it in the
    /// order they were made instead of racing each other.
    private var pushQueue: Task<Void, Never>?

    /// The AniList app's client ID the build ships, read from Info.plist. The
    /// app has no field for it: Connect signs in with the ID it was built with.
    static var bundledClientID: String? {
        guard let bundled = Bundle.main.object(forInfoDictionaryKey: "AniswiftAniListClientID") as? String else {
            return nil
        }
        let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumber) ? trimmed : nil
    }

    init() {
        let cached = AniListKeychain.read()
        session = (cached?.expiresAt ?? .distantPast) > .now ? cached : nil
    }

    var isSignedIn: Bool { (session?.expiresAt ?? .distantPast) > .now }

    /// Takes the token the sign-in sheet read, and asks AniList which account it
    /// belongs to. The sheet presents AniList's own page, so the redirect URL of
    /// the client ID the build ships does not have to be one this app can name:
    /// the token is read from wherever AniList hands it back.
    func adopt(_ token: String) async {
        guard !connecting else { return }
        connecting = true
        message = nil
        defer { connecting = false }
        do {
            // AniList tokens last a year unless the answer says otherwise, and
            // a token read off a page carries no lifetime at all.
            var session = AniListSession(token: token, expiresAt: Date().addingTimeInterval(31_536_000))
            let viewer = try await viewer(token: session.token)
            guard let account: Int = viewer.read("id"), let name = viewer.string("name") else {
                message = "AniList did not answer with the account."
                return
            }
            session.id = account
            session.name = name
            self.session = session
            try AniListKeychain.write(session)
            await sync(refresh: true)
        } catch {
            guard !Task.isCancelled else { return }
            message = plainMessage(error, fallback: "Could not sign in to AniList.")
        }
    }

    func signOut() {
        session = nil
        entries = []
        message = nil
        mediaIDs = [:]
        entryIDs = [:]
        AniListKeychain.remove()
    }

    /// Carries a MyAnimeList change to AniList, one change at a time so two
    /// quick swipes arrive in the order they were made. This is the whole
    /// sync: AniList is written to, never read back into MyAnimeList.
    func push(_ title: Title, change: ListChange?) async {
        let previous = pushQueue
        let job = Task { [weak self] in
            _ = await previous?.value
            await self?.send(title, change: change)
        }
        pushQueue = job
        _ = await job.value
    }

    private func send(_ title: Title, change: ListChange?) async {
        guard let session, session.expiresAt > .now else { return }
        do {
            if let change {
                guard let mediaID = try await mediaID(for: title, session: session) else { return }
                let body: [String: Any] = [
                    // scoreRaw is the 100-point score every account reads the
                    // same way: the plain `score` argument is taken in the
                    // user's own scoring format, so a MAL 8 sent as 80 became
                    // a 10/10 on every account not already on 100 points.
                    "query": """
                    mutation ($mediaId: Int, $status: MediaListStatus, $progress: Int, $scoreRaw: Int) {
                      SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress, scoreRaw: $scoreRaw) {
                        id
                      }
                    }
                    """,
                    "variables": [
                        "mediaId": mediaID,
                        "status": Self.status(change.status, kind: title.kind),
                        "progress": change.progress,
                        "scoreRaw": change.rating * 10,
                    ],
                ]
                _ = try await query(body, token: session.token)
            } else if let entryID = entryIDs[title.id] {
                let body: [String: Any] = [
                    "query": "mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }",
                    "variables": ["id": entryID],
                ]
                _ = try await query(body, token: session.token)
                entryIDs[title.id] = nil
                mediaIDs[title.id] = nil
            }
            message = nil
        } catch {
            guard !Task.isCancelled else { return }
            // The MyAnimeList change already landed; this only says the copy on
            // AniList did not.
            message = plainMessage(error, fallback: "Could not copy that change to AniList.")
        }
    }

    /// The AniList media id for a title: the one a sync learned, or the answer
    /// to a lookup by its MyAnimeList id.
    private func mediaID(for title: Title, session: AniListSession) async throws -> Int? {
        if let cached = mediaIDs[title.id] { return cached }
        let body: [String: Any] = [
            "query": "query ($malId: Int, $type: MediaType) { Media(idMal: $malId, type: $type) { id } }",
            "variables": ["malId": title.malID, "type": title.kind == .anime ? "ANIME" : "MANGA"],
        ]
        let result = try await query(body, token: session.token)
        guard let data: Fields = result.read("data"),
            let media: Fields = data.read("Media"),
            let id: Int = media.read("id")
        else { return nil }
        mediaIDs[title.id] = id
        return id
    }

    /// The AniList status a MyAnimeList status maps to.
    private static func status(_ value: String, kind: Kind) -> String {
        switch value.lowercased().replacingOccurrences(of: "_", with: " ") {
        case "watching", "reading": "CURRENT"
        case "completed": "COMPLETED"
        case "on hold": "PAUSED"
        case "dropped": "DROPPED"
        case "plan to watch", "plan to read": "PLANNING"
        default: "CURRENT"
        }
    }

    /// Brings the account's lists over, grouped by kind and status. The lists
    /// are read again on each refresh, since they change on AniList.
    func sync(refresh: Bool = false) async {
        guard let saved = session else { return }
        guard saved.expiresAt > .now else {
            session = nil
            AniListKeychain.remove()
            message = "Your AniList session has expired. Connect again."
            return
        }
        guard !loading else { return }
        loading = true
        message = nil
        defer { loading = false }
        do {
            var loaded: [AniListEntry] = []
            for kind in Kind.allCases {
                loaded += try await list(kind, session: saved)
            }
            guard !Task.isCancelled else { return }
            entries = loaded
            mediaIDs = [:]
            entryIDs = [:]
            for entry in loaded {
                guard let malID = entry.malID else { continue }
                let key = "\(entry.kind.rawValue)-\(malID)"
                mediaIDs[key] = entry.id
                if entry.entryID > 0 { entryIDs[key] = entry.entryID }
            }
        } catch {
            guard !Task.isCancelled else { return }
            message = plainMessage(error, fallback: "Could not read your AniList lists.")
        }
    }

    private func viewer(token: String) async throws -> Fields {
        let result = try await query(["query": "query { Viewer { id name } }"], token: token)
        guard let data: Fields = result.read("data"), let viewer: Fields = data.read("Viewer") else {
            throw APIError(status: 0, message: "AniList did not answer with the account.")
        }
        return viewer
    }

    private func list(_ kind: Kind, session: AniListSession) async throws -> [AniListEntry] {
        // The score is asked for on the 100-point scale, whatever format the
        // account itself scores in, so every row reads the same way.
        let body: [String: Any] = [
            "query": """
            query ($id: Int, $type: MediaType) {
              MediaListCollection(userId: $id, type: $type) {
                lists {
                  entries {
                    status
                    progress
                    score(format: POINT_100)
                    media {
                      id
                      idMal
                      title { romaji english }
                      coverImage { large }
                      episodes
                      chapters
                    }
                  }
                }
              }
            }
            """,
            "variables": ["id": session.id, "type": kind == .anime ? "ANIME" : "MANGA"],
        ]
        let result = try await query(body, token: session.token)
        guard let data: Fields = result.read("data"),
            let collection: Fields = data.read("MediaListCollection"),
            let lists: [Fields] = collection.read("lists")
        else {
            throw APIError(status: 0, message: "AniList did not answer with your lists.")
        }
        let rows: [Fields] = lists.flatMap { list -> [Fields] in list.read("entries") ?? [] }
        return rows.compactMap { AniListEntry($0, kind: kind) }
    }

    /// The next episode of a batch of anime, by MyAnimeList id. AniList answers
    /// this without a session, so a title page and a list of rows get an exact
    /// schedule whether or not AniList is connected in Settings. A title that is
    /// not on the air has no next episode and is left out of the answer.
    func schedules(forMALIDs ids: [Int]) async -> [Int: AiringSchedule] {
        guard !ids.isEmpty else { return [:] }
        let body: [String: Any] = [
            "query": """
            query ($ids: [Int]) {
              Page(perPage: 50) {
                media(idMal_in: $ids, type: ANIME) {
                  idMal
                  nextAiringEpisode { episode airingAt }
                }
              }
            }
            """,
            "variables": ["ids": ids],
        ]
        guard let result = try? await query(body, token: nil),
            let data: Fields = result.read("data"),
            let page: Fields = data.read("Page"),
            let rows: [Fields] = page.read("media")
        else { return [:] }
        var learned: [Int: AiringSchedule] = [:]
        for row in rows {
            guard let malID: Int = row.read("idMal"),
                let next: Fields = row.read("nextAiringEpisode"),
                let episode: Int = next.read("episode"), episode > 0,
                let airingAt: Int = next.read("airingAt")
            else { continue }
            learned[malID] = AiringSchedule(
                episode: episode, date: Date(timeIntervalSince1970: TimeInterval(airingAt)))
        }
        return learned
    }

    private func query(_ body: [String: Any], token: String?) async throws -> Fields {
        var request = URLRequest(url: Self.graphql, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "AniList did not respond.")
        }
        let fields = try? JSONDecoder().decode(Fields.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            let errors: [Fields] = fields?.read("errors") ?? []
            throw APIError(
                status: http.statusCode,
                message: errors.first?.string("message") ?? "AniList could not answer.")
        }
        guard let fields else {
            throw APIError(status: 0, message: "AniList answered with something unreadable.")
        }
        return fields
    }
}


/// The next episode of an anime that is still on the air, as AniList publishes
/// it: which episode it is and when it is due, in one exact value. MyAnimeList
/// names only a weekly slot, which counts seven days between episodes and so
/// drifts by an episode for every break a run takes; AniList tracks the run
/// itself, so the countdown and the caught-up colour no longer drift with it.
struct AiringSchedule: Equatable, Codable {
    /// The episode that airs at `date`.
    let episode: Int
    let date: Date
}

/// The schedules AniList has published, by MyAnimeList id, so a list of airing
/// anime costs one request rather than one per row, and a page opened again
/// inside `lifetime` answers from what it already has. AniList answers a
/// schedule query without a session, so this works whether or not the reader
/// has connected AniList in Settings.
@MainActor
final class AiringScheduleCache: ObservableObject {
    static let shared = AiringScheduleCache()

    @Published private(set) var schedules: [Int: AiringSchedule] = [:]
    /// When each id was asked for. An id that answered nothing — a run that has
    /// finished, or a title AniList does not list — is stamped too, so it is not
    /// asked for again on every pass.
    private var askedAt: [Int: Date] = [:]
    /// The ids a request is already on its way for, so a list and a title page
    /// opening together cost one request instead of two.
    private var inFlight: Set<Int> = []

    private static let lifetime: TimeInterval = 10 * 60
    private static let batchSize = 50

    /// The schedules the last launch learned are drawn at once, so an airing row
    /// shows “Episode 9 airs in 2 hours” on its first paint. An entry older
    /// than `lifetime` is asked for again while the saved one stays on screen.
    init() {
        guard let saved = AiringScheduleSnapshot.read() else { return }
        schedules = saved.schedules
        askedAt = saved.askedAt
    }

    func schedule(for malID: Int) -> AiringSchedule? { schedules[malID] }

    /// Asks AniList for the schedules it does not know yet, in batches of fifty,
    /// and leaves every id it already has alone. A pull to refresh passes
    /// `refresh` to read them again.
    func learn(_ ids: [Int], refresh: Bool = false) async {
        let now = Date()
        let wanted = Set(ids.filter { $0 > 0 }).subtracting(inFlight).filter { id in
            guard !refresh, let asked = askedAt[id] else { return true }
            return now.timeIntervalSince(asked) > Self.lifetime
        }.sorted()
        guard !wanted.isEmpty else { return }
        inFlight.formUnion(wanted)
        defer { inFlight.subtract(wanted) }
        var start = 0
        while start < wanted.count, !Task.isCancelled {
            let batch = Array(wanted[start..<min(start + Self.batchSize, wanted.count)])
            start += batch.count
            let learned = await AniListClient.shared.schedules(forMALIDs: batch)
            let stamp = Date()
            for id in batch { askedAt[id] = stamp }
            for (id, schedule) in learned { schedules[id] = schedule }
        }
        persist()
    }

    /// Writes what a list can still draw, and drops a run whose episode passed
    /// more than a day ago, so the file does not grow with every title opened
    /// and a finished run's row loses nothing it was still showing.
    private func persist() {
        let horizon = Date().addingTimeInterval(-24 * 60 * 60)
        let live = schedules.filter { $0.value.date > horizon }
        AiringScheduleSnapshot(
            schedules: live, askedAt: askedAt.filter { live[$0.key] != nil }
        ).write()
    }
}
