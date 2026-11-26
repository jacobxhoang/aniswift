import AuthenticationServices
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
}

/// The redirect MyAnimeList sends back after sign-in. Every part is checked
/// before the code is exchanged: a foreign scheme or host, a repeated parameter
/// or a state that does not match the one this attempt generated must never be
/// treated as a completed sign-in.
enum MALCallback {
    static let scheme = "org.aniledger.ios"
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
        kSecAttrService as String: "org.aniledger.ios",
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
    func titleNames(_ ids: [Int], kind: Kind) async -> [Int: String]
    func resolveTitle(_ title: Title) async -> Title?
    func cachedTitle(_ title: Title) -> Title?
    func cachedDetail(_ title: Title) -> Fields?
    func savedDetail(_ title: Title) -> (fields: Fields, savedAt: Date)?
    func clearCatalogCache()

    func interestStacks(for title: Title, page: Int) async throws -> Page<InterestStack>
    func stackDetail(_ id: Int) async throws -> StackDetail
    func titleReviews(_ title: Title, page: Int) async throws -> Page<TitleReview>
}

@MainActor
final class API: APIClient {
    static let callbackScheme = MALCallback.scheme
    static let redirectURI = MALCallback.url
    private static let mal = URL(string: "https://api.myanimelist.net/v2")!
    private static let oauth = URL(string: "https://myanimelist.net/v1/oauth2")!
    private static let clientIDKey = "aniledger.mal.nativeClientID"
    private let tenrai = URL(string: "https://api.tenrai.org/v1")!
    private let jikan = URL(string: "https://jikan.lucashdo.com/v1")!
    private var malSession = SessionKeychain.read()
    private var sessionGeneration = UUID()
    private var signingIn = false
    private let transport = URLSession(configuration: .ephemeral, delegate: MALTransport(), delegateQueue: nil)
    private var privateQueue: Task<Void, Never>?
    private var cached: [URL: (Date, Fields)] = [:]
    private var catalogRequests: [URL: Task<(Fields, Data), Error>] = [:]
    private let catalogCacheLimit = 160
    private static let catalogLifetime: TimeInterval = 300
    /// User lists and friend activity change while the app is open, so they keep the short lifetime.
    private static let userLifetime: TimeInterval = 60
    private var titleLookups: [String: Task<Title?, Never>] = [:]
    private var activeTitleLookups = 0
    private var titleLookupWaiters: [CheckedContinuation<Void, Never>] = []
    private let titleLookupLimit = 6

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
        let directory = base.appending(path: "AniLedgerDetailCache", directoryHint: .isDirectory)
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

    func cachedTitle(_ title: Title) -> Title? {
        cachedDetail(title).flatMap { Title($0, kind: title.kind) }
    }

    /// Drops decoded catalog responses so Clear Cache also refreshes title pages.
    func clearCatalogCache() {
        cached.removeAll()
        if let directory = Self.detailDirectory() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Whether a decoded catalog response is still available to title pages.
    var hasCachedCatalog: Bool { !cached.isEmpty }

    /// English titles for a batch of ids in as few requests as possible.
    /// Tenrai's `ids` filter answers 50 titles at a time, which replaces a
    /// detail request per row when a list only carries the original title.
    func titleNames(_ ids: [Int], kind: Kind) async -> [Int: String] {
        var names: [Int: String] = [:]
        var remaining = Array(Set(ids.filter { $0 > 0 })).sorted()
        while !remaining.isEmpty {
            if Task.isCancelled { return names }
            let chunk = Array(remaining.prefix(50))
            remaining.removeFirst(chunk.count)
            let query = [URLQueryItem(name: "ids", value: chunk.map(String.init).joined(separator: ",")),
                         URLQueryItem(name: "limit", value: String(chunk.count))]
            guard let response = try? await catalog(kind.rawValue, query, refresh: false) else { continue }
            let rows: [Fields] = response.read("data") ?? []
            for row in rows {
                guard let id: Int = row.read("mal_id", "malId", "id"),
                      let name = row.englishTitle else { continue }
                names[id] = name
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
            return Title(fields, kind: title.kind)
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

    var configuredClientID: String? {
        if let saved = UserDefaults.standard.string(forKey: Self.clientIDKey), !saved.isEmpty { return saved }
        guard let bundled = Bundle.main.object(forInfoDictionaryKey: "AniLedgerMALClientID") as? String,
              !bundled.isEmpty else { return nil }
        return bundled
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
            throw APIError(status: 0, message: "Enter the 32-character Client ID for your MyAnimeList iOS app.")
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
        UserDefaults.standard.set(clientID, forKey: Self.clientIDKey)
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
        return "id,title,main_picture,alternative_titles,mean,media_type,\(total)"
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
    /// Stacks that contain this title. Tenrai answers 25 per page.
    func interestStacks(for title: Title, page: Int) async throws -> Page<InterestStack> {
        let response = try await catalog(
            "\(title.kind.rawValue)/\(title.malID)/stacks", [URLQueryItem(name: "page", value: String(page))],
            refresh: false)
        let rows: [Fields] = response.read("data") ?? []
        let pagination: Fields? = response.read("pagination")
        let more: Bool = pagination?.read("has_next_page", "hasNextPage") ?? false
        return Page(items: unique(rows.compactMap(InterestStack.init)), more: more)
    }

    func stackDetail(_ id: Int) async throws -> StackDetail {
        let response = try await catalog("stacks/\(id)", [], refresh: false)
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
        guard window != nil else { throw APIError(status: 0, message: "Bring AniLedger to the foreground and try again.") }
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
