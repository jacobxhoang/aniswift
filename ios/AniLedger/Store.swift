import SwiftUI

@MainActor
final class Store: ObservableObject {
    let api = API()
    @Published var account: Account?
    @Published var checking = true
    @Published var message: String?
    @Published private var savedLists: [Kind: SavedList] = [:]
    @Published private(set) var refreshingLists: Set<Kind> = []
    @Published var friends: [Friend] = []
    @Published var activity: [FriendUpdate] = []
    @Published var friendMessage: String?
    @Published var loadingFriends = false
    @Published var checkedFriends = 0
    private var accountGeneration = UUID()
    private var listRevisions: [Kind: Int] = [:]
    private var pagingLists: Set<Kind> = []

    var lists: [Kind: [ListEntry]] { savedLists.mapValues(\.items) }
    var nextList: [Kind: Int] { savedLists.compactMapValues { $0.more ? $0.page + 1 : nil } }

    var recent: [ListEntry] {
        (lists[.anime, default: []] + lists[.manga, default: []]).sorted { $0.updated > $1.updated }
    }

    func restore() async {
        if api.hasSession, let cache = ListCache.read() {
            account = cache.account
            savedLists = cache.lists
            checking = false
        }
        let generation = accountGeneration
        do {
            let user = try await api.session()
            guard accountGeneration == generation else { return }
            setAccount(user)
            checking = false
            await loadLists(force: true)
        } catch {
            guard accountGeneration == generation else { return }
            checking = false
            if !api.hasSession { setAccount(nil) }
            if account == nil { message = error.localizedDescription }
        }
    }

    func connected(_ user: Account) async {
        setAccount(user)
        await loadLists(force: true)
    }

    func disconnect() {
        do {
            try api.signOut()
            setAccount(nil)
        } catch { message = error.localizedDescription }
    }

    private func setAccount(_ user: Account?) {
        if account?.id != user?.id || user == nil {
            accountGeneration = UUID()
            listRevisions = [:]
            pagingLists = []
            refreshingLists = []
            savedLists = [:]
            activity = []
            friends = []
            checkedFriends = 0
            friendMessage = nil
            ListCache.remove()
        }
        account = user
    }

    func handle(_ error: Error) {
        if (error as? APIError)?.status == 401 { disconnect() }
        message = error.localizedDescription
    }

    func loadLists(force: Bool = false) async {
        let generation = accountGeneration
        for kind in Kind.allCases {
            guard accountGeneration == generation else { return }
            guard force || savedLists[kind] == nil else { continue }
            do { try await refreshList(kind) }
            catch {
                if accountGeneration == generation,
                   ((error as? APIError)?.status == 401 || savedLists[kind] == nil) {
                    handle(error)
                }
            }
        }
    }

    private func refreshList(_ kind: Kind) async throws {
        guard account != nil, !refreshingLists.contains(kind), !pagingLists.contains(kind) else { return }
        let generation = accountGeneration
        refreshingLists.insert(kind)
        defer {
            if accountGeneration == generation { refreshingLists.remove(kind) }
        }

        // Fetch the loaded range as a unit so entries that move between pages stay consistent.
        repeat {
            let revision = listRevisions[kind, default: 0]
            let lastPage = max(1, savedLists[kind]?.page ?? 0)
            var items: [ListEntry] = []
            var page = 1
            while true {
                let result = try await api.list(kind, page: page)
                guard accountGeneration == generation else { return }
                if listRevisions[kind, default: 0] != revision { break }
                items.append(contentsOf: result.items)
                if page == lastPage || !result.more {
                    updateList(kind, SavedList(items: unique(items), page: page, more: result.more))
                    return
                }
                page += 1
            }
            // A saved edit arrived mid-sync. Start again with fresh pages.
        } while !Task.isCancelled
    }

    func loadList(_ kind: Kind, page: Int) async throws {
        guard account != nil, !refreshingLists.contains(kind), !pagingLists.contains(kind),
              page == nextList[kind] else { return }
        let generation = accountGeneration
        if savedLists[kind]?.needsReconciliation == true {
            try await refreshList(kind)
            guard accountGeneration == generation, page == nextList[kind],
                  savedLists[kind]?.needsReconciliation == false, !pagingLists.contains(kind) else { return }
        }
        let revision = listRevisions[kind, default: 0]
        pagingLists.insert(kind)
        defer {
            if accountGeneration == generation { pagingLists.remove(kind) }
        }
        let result = try await api.list(kind, page: page)
        guard accountGeneration == generation, listRevisions[kind, default: 0] == revision else { return }
        let previous = savedLists[kind]?.items ?? []
        updateList(kind, SavedList(items: unique(previous + result.items), page: page, more: result.more))
    }

    func change(_ title: Title, _ change: ListChange?) async throws {
        guard account != nil else { return }
        let generation = accountGeneration
        try await api.save(title, change: change)
        guard accountGeneration == generation else { return }

        let kind = title.kind
        listRevisions[kind, default: 0] += 1
        var snapshot = savedLists[kind] ?? SavedList(items: [], page: 0, more: true)
        snapshot.needsReconciliation = snapshot.more
        let previous = snapshot.items.first { $0.id == title.id }
        snapshot.items.removeAll { $0.id == title.id }
        if let change {
            let savedTitle = previous?.title.fillingTitleAndImage(from: title) ?? title
            snapshot.items.insert(ListEntry(title: savedTitle, change: change), at: 0)
        }
        updateList(kind, snapshot)
    }

    private func updateList(_ kind: Kind, _ snapshot: SavedList) {
        guard let account, savedLists[kind] != snapshot else { return }
        savedLists[kind] = snapshot
        ListCache(account: account, lists: savedLists).write()
    }

    func loadFriends(reset: Bool = false) async {
        guard let user = account, !loadingFriends else { return }
        loadingFriends = true
        defer { loadingFriends = false }
        if reset {
            checkedFriends = 0
            activity = []
        }
        friendMessage = nil
        do {
            if reset || friends.isEmpty { try await fetchFriends(user, refresh: reset) }
            let batch = Array(friends.dropFirst(checkedFriends).prefix(6))
            var updates: [FriendUpdate] = []
            for friend in batch {
                guard account == user else { return }
                do { updates += try await publicUpdates(friend, refresh: reset) }
                catch { friendMessage = "Some friends’ public activity is unavailable." }
            }
            guard account == user else { return }
            checkedFriends += batch.count
            activity = unique(activity + updates).sorted { activityDate($0.date) > activityDate($1.date) }
        } catch { friendMessage = error.localizedDescription }
    }

    func fetchFriends(_ user: Account, refresh: Bool = false) async throws {
        let response = try await api.catalog("users/\(user.name)/friends", refresh: refresh)
        let entries: [Fields] = response.read("data") ?? []
        guard account == user else { return }
        friends = unique(entries.compactMap(Friend.init).filter { $0.id != user.name.lowercased() })
    }

    func publicUpdates(_ friend: Friend, refresh: Bool = false) async throws -> [FriendUpdate] {
        let result = try await api.catalog("users/\(friend.name)/userupdates", refresh: refresh)
        let body: Fields? = result.read("data")
        return Kind.allCases.flatMap { kind -> [FriendUpdate] in
            let entries: [Fields] = body?.read(kind.rawValue) ?? []
            return entries.compactMap { entry -> FriendUpdate? in
                guard let info: Fields = entry.read("entry"), let title = Title(info, kind: kind) else { return nil }
                return FriendUpdate(friend: friend, title: title, fields: entry)
            }
        }
    }

    func friendEntry(_ friend: Friend, _ title: Title) async throws -> FriendUpdate? {
        if let updates = try? await publicUpdates(friend), let match = updates.first(where: { $0.title.id == title.id }) {
            return match
        }
        for page in 1...10 {
            try Task.checkCancellation()
            let response = try await api.catalog("users/\(friend.name)/\(title.kind.rawValue)list", [
                URLQueryItem(name: "limit", value: "300"), URLQueryItem(name: "page", value: String(page))
            ])
            let body: Fields? = response.read("data")
            let entries: [Fields] = response.read("data") ?? body?.read("entries") ?? []
            if let match = entries.first(where: { ($0.read("malId", "mal_id", "mediaId", "id") as Int?) == title.malID }) {
                return FriendUpdate(friend: friend, title: title, fields: match)
            }
            let meta: Fields? = response.read("meta")
            let pagination: Fields? = meta?.read("pagination")
            if !(pagination?.read("hasNextPage") ?? (entries.count == 300)) { break }
        }
        return nil
    }
}

private struct SavedList: Codable, Equatable {
    var items: [ListEntry]
    let page: Int
    let more: Bool
    var needsReconciliation = false
}

private struct ListCache: Codable {
    let account: Account
    let lists: [Kind: SavedList]

    private static var file: URL {
        URL.cachesDirectory.appending(path: "AniLedger-lists-v1.json")
    }

    static func read() -> Self? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove() {
        try? FileManager.default.removeItem(at: file)
    }
}

func unique<T: Identifiable>(_ values: [T]) -> [T] {
    var seen = Set<T.ID>()
    return values.filter { seen.insert($0.id).inserted }
}

func activityDate(_ value: String?) -> Date {
    guard let value else { return .distantPast }
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: value) { return date }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.defaultDate = Date()
    for format in ["yyyy-MM-dd", "MMM d, yyyy", "MMM d, h:mm a", "MMM d"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: value) {
            if !format.contains("y"), date > Date() {
                return Calendar.current.date(byAdding: .year, value: -1, to: date) ?? date
            }
            return date
        }
    }
    if value.lowercased().hasPrefix("today") { return Date() }
    if value.lowercased().hasPrefix("yesterday") {
        return Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? .distantPast
    }
    return .distantPast
}

func displayDate(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "" }
    let date = activityDate(value)
    return date == .distantPast ? value : date.formatted(.dateTime.month(.abbreviated).day().year())
}
