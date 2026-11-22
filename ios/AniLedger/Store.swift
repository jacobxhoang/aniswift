import SwiftUI

@MainActor
final class Store: ObservableObject {
    let api = API()
    @Published var account: Account?
    @Published var checking = true
    @Published var message: String?
    @Published var lists: [Kind: [ListEntry]] = [:]
    @Published var nextList: [Kind: Int] = [:]
    @Published var friends: [Friend] = []
    @Published var activity: [FriendUpdate] = []
    @Published var friendMessage: String?
    @Published var loadingFriends = false
    @Published var checkedFriends = 0
    private var loadedAccount: Int?

    var recent: [ListEntry] {
        (lists[.anime, default: []] + lists[.manga, default: []]).sorted { $0.updated > $1.updated }
    }

    func restore() async {
        do {
            account = try await api.session()
            checking = false
            await loadLists()
        } catch {
            checking = false
            message = error.localizedDescription
        }
    }

    func connected(_ user: Account) async {
        account = user
        await loadLists()
    }

    func disconnect() {
        do {
            try api.signOut()
            account = nil
            loadedAccount = nil
            lists = [:]
            nextList = [:]
            activity = []
            friends = []
            checkedFriends = 0
            friendMessage = nil
        } catch { message = error.localizedDescription }
    }

    func handle(_ error: Error) {
        if (error as? APIError)?.status == 401 { disconnect() }
        message = error.localizedDescription
    }

    func loadLists(force: Bool = false) async {
        guard let user = account, force || loadedAccount != user.id else { return }
        loadedAccount = user.id
        for kind in Kind.allCases {
            do { try await loadList(kind, page: 1) }
            catch {
                loadedAccount = nil
                handle(error)
                if account == nil { return }
            }
        }
    }

    func loadList(_ kind: Kind, page: Int) async throws {
        guard let user = account else { return }
        let result = try await api.list(kind, page: page)
        guard account == user else { return }
        let previous = page == 1 ? [] : lists[kind, default: []]
        lists[kind] = unique(previous + result.items)
        nextList[kind] = result.more ? page + 1 : nil
    }

    func change(_ title: Title, _ change: ListChange?) async throws {
        guard let user = account else { return }
        try await api.save(title, change: change)
        guard account == user else { return }
        try await loadList(title.kind, page: 1)
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
