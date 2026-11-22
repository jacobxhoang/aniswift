import SwiftUI

@MainActor
final class Store: ObservableObject {
    let api = API()
    @Published var account: Account?
    @Published var checking = true
    @Published var message: String?
    @Published private(set) var organization = ListOrganization()
    @Published private var savedLists: [Kind: SavedList] = [:]
    @Published private(set) var refreshingLists: Set<Kind> = []
    @Published var friends: [Friend] = []
    @Published var activity: [FriendUpdate] = []
    @Published var friendMessage: String?
    @Published var loadingFriends = false
    @Published private(set) var friendFeedPage = 0
    @Published private var checkedFriends = 0
    @Published private var historyCursors: [FriendHistoryCursor] = []
    @Published private var feedEnglishNames: [String: String] = [:]

    var hasMoreFriendActivity: Bool { checkedFriends < friends.count || !historyCursors.isEmpty }
    @Published private var profiles = ProfileCache.read()
    private var profileRequests: [String: Task<Bool, Never>] = [:]
    let previousLocalFavorites: [Title] = {
        guard let data = UserDefaults.standard.data(forKey: "aniledger.localFavorites.v1") else { return [] }
        return (try? JSONDecoder().decode([Title].self, from: data)) ?? []
    }()

    var malFavorites: [Kind: [Title]] {
        account.flatMap { profile(for: $0.name).favorites?.value } ?? [:]
    }

    func isMALFavorite(_ title: Title) -> Bool {
        malFavorites[title.kind]?.contains { $0.id == title.id } ?? false
    }

    func profile(for name: String) -> ProfileSnapshot {
        profiles[name.lowercased()] ?? ProfileSnapshot()
    }

    func loadProfile(_ name: String, refresh: Bool = false) async -> Bool {
        let key = name.lowercased()
        if let pending = profileRequests[key] { return await pending.value }

        let cached = profile(for: name)
        let needsStats = refresh || cached.stats?.isFresh != true || cached.stats?.value.hasDetailedStatistics != true
        let needsFavorites = refresh || cached.favorites?.isFresh != true
        guard needsStats || needsFavorites else { return true }

        let task = Task {
            async let stats = needsStats ? fetchProfileStats(name, refresh: refresh) : nil
            async let favorites = needsFavorites ? fetchProfileFavorites(name, refresh: refresh) : nil
            let (newStats, newFavorites) = await (stats, favorites)
            if newStats != nil || newFavorites != nil {
                var updated = cached
                if let newStats { updated.stats = CachedProfileValue(value: newStats, savedAt: .now) }
                if let newFavorites { updated.favorites = CachedProfileValue(value: newFavorites, savedAt: .now) }
                profiles[key] = updated
                ProfileCache.write(profiles)
            }
            return (!needsStats || newStats != nil) && (!needsFavorites || newFavorites != nil)
        }
        profileRequests[key] = task
        let loaded = await task.value
        profileRequests[key] = nil
        return loaded
    }

    private func fetchProfileStats(_ name: String, refresh: Bool) async -> ProfileStats? {
        let response = try? await api.catalog("users/\(name)/statistics", refresh: refresh)
        guard let data: Fields = response?.read("data") else { return nil }
        return ProfileStats(data)
    }

    private func fetchProfileFavorites(_ name: String, refresh: Bool) async -> [Kind: [Title]]? {
        let response = try? await api.catalog("users/\(name)/favorites", refresh: refresh)
        guard let data: Fields = response?.read("data") else { return nil }
        return Dictionary(uniqueKeysWithValues: Kind.allCases.map { kind in
            let entries: [Fields] = data.read(kind.rawValue) ?? []
            return (kind, entries.compactMap { Title($0, kind: kind) })
        })
    }

    private var accountGeneration = UUID()
    private var listRevisions: [Kind: Int] = [:]
    private var pagingLists: Set<Kind> = []

    var lists: [Kind: [ListEntry]] { savedLists.mapValues(\.items) }
    var nextList: [Kind: Int] { savedLists.compactMapValues { $0.more ? $0.page + 1 : nil } }

    var recent: [ListEntry] {
        (lists[.anime, default: []] + lists[.manga, default: []]).sorted { $0.updated > $1.updated }
    }

    func restore() async {
        guard api.hasSession else { checking = false; return }
        if let cache = ListCache.read() {
            account = cache.account
            organization = readOrganization(for: cache.account)
            savedLists = cache.lists
            restoreFriendFeed(for: cache.account)
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
        let cache = ListCache.read()
        setAccount(user)
        if let cache, cache.account.id == user.id, savedLists.isEmpty {
            savedLists = cache.lists
            ListCache(account: user, lists: savedLists).write()
        }
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
            organization = user.map { readOrganization(for: $0) } ?? ListOrganization()
            listRevisions = [:]
            pagingLists = []
            refreshingLists = []
            savedLists = [:]
            activity = []
            friends = []
            checkedFriends = 0
            friendFeedPage = 0
            historyCursors = []
            feedEnglishNames = [:]
            loadingFriends = false
            friendMessage = nil
            ListCache.remove()
            if let user {
                restoreFriendFeed(for: user)
            } else {
                FriendFeedCache.remove()
            }
        }
        account = user
    }

    private func restoreFriendFeed(for user: Account) {
        guard let cache = FriendFeedCache.read() else { return }
        guard cache.accountID == user.id else {
            FriendFeedCache.remove()
            return
        }
        friends = cache.friends
        activity = cache.activity
        checkedFriends = cache.checkedFriends
        historyCursors = cache.historyCursors
        friendFeedPage = cache.page
        feedEnglishNames = cache.englishNames ?? [:]
    }

    func friendFeedTitle(_ title: Title) -> Title {
        title.fillingEnglishName(from: feedEnglishNames[title.id])
    }

    func rememberFriendFeedEnglishName(_ name: String, for title: Title) {
        guard account != nil, feedEnglishNames[title.id] != name else { return }
        feedEnglishNames[title.id] = name
        saveFriendFeed()
    }

    private func saveFriendFeed() {
        guard let account else { return }
        FriendFeedCache(accountID: account.id, friends: friends, activity: activity,
                        checkedFriends: checkedFriends, historyCursors: historyCursors,
                        page: friendFeedPage, englishNames: feedEnglishNames).write()
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
        let response = try await api.save(title, change: change)
        guard accountGeneration == generation else { return }
        let kind = title.kind
        listRevisions[kind, default: 0] += 1
        var snapshot = savedLists[kind] ?? SavedList(items: [], page: 0, more: true)
        snapshot.needsReconciliation = snapshot.more
        let previous = snapshot.items.first { $0.id == title.id }
        snapshot.items.removeAll { $0.id == title.id }
        if let change, let response {
            let savedTitle = previous?.title.fillingTitleAndImage(from: title) ?? title
            snapshot.items.insert(ListEntry(response, title: savedTitle, fallback: change, previous: previous), at: 0)
        }
        updateList(kind, snapshot)
    }

    func organize(_ title: Title, lists selected: Set<UUID>, adding newLists: [CustomTitleList],
                  hidden: Bool, accountID: Int) {
        guard account?.id == accountID else { return }
        var updated = organization
        updated.lists += newLists
        for index in updated.lists.indices {
            let contains = updated.lists[index].titles.contains { $0.id == title.id }
            if selected.contains(updated.lists[index].id) {
                if !contains { updated.lists[index].titles.append(title) }
            } else if contains {
                updated.lists[index].titles.removeAll { $0.id == title.id }
            }
        }
        if hidden { updated.hidden.insert(title.id) }
        else { updated.hidden.remove(title.id) }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: organizationKey(accountID))
        organization = updated
    }

    private func organizationKey(_ accountID: Int) -> String { "aniledger.organization.v1.\(accountID)" }

    private func readOrganization(for user: Account) -> ListOrganization {
        guard let data = UserDefaults.standard.data(forKey: organizationKey(user.id)) else { return ListOrganization() }
        return (try? JSONDecoder().decode(ListOrganization.self, from: data)) ?? ListOrganization()
    }

    private func updateList(_ kind: Kind, _ snapshot: SavedList) {
        guard let account, savedLists[kind] != snapshot else { return }
        savedLists[kind] = snapshot
        ListCache(account: account, lists: savedLists).write()
    }

    func loadFriends(reset: Bool = false) async {
        guard let user = account, !loadingFriends else { return }
        let generation = accountGeneration
        loadingFriends = true
        defer { if accountGeneration == generation { loadingFriends = false } }
        friendMessage = nil

        if !reset, friendFeedPage > 0, checkedFriends >= friends.count {
            await loadOlderFriendActivity(generation: generation)
            return
        }

        do {
            let refreshedFriends = reset || friends.isEmpty
                ? try await friendList(user, refresh: reset)
                : friends
            guard !Task.isCancelled, accountGeneration == generation else { return }
            let start = reset ? 0 : checkedFriends
            let batch = Array(refreshedFriends.dropFirst(start).prefix(8))
            let results = await loadRecentFriendActivity(batch, refresh: reset)
            guard !Task.isCancelled, accountGeneration == generation else { return }
            if reset && !batch.isEmpty && results.isEmpty && !activity.isEmpty {
                friendMessage = "Could not refresh the feed."
                return
            }
            if reset || friendFeedPage == 0 {
                historyCursors = refreshedFriends.flatMap { friend in
                    Kind.allCases.map { FriendHistoryCursor(friend: friend, kind: $0, page: 1) }
                }
            }
            friends = refreshedFriends
            checkedFriends = start + batch.count
            let updates = results.flatMap { $0 }
            let sorted = sortedFriendActivity(updates)
            activity = reset ? sorted : unique(activity + sorted)
            friendFeedPage += 1
            saveFriendFeed()
        } catch {
            if !Task.isCancelled, accountGeneration == generation { friendMessage = error.localizedDescription }
        }
    }

    private func loadRecentFriendActivity(_ batch: [Friend], refresh: Bool) async -> [[FriendUpdate]] {
        var results: [[FriendUpdate]] = []
        let concurrency = 4
        for start in stride(from: 0, to: batch.count, by: concurrency) {
            guard !Task.isCancelled else { return results }
            let friends = batch[start..<min(start + concurrency, batch.count)]
            await withTaskGroup(of: [FriendUpdate]?.self) { group in
                for friend in friends {
                    group.addTask { try? await self.publicUpdates(friend, refresh: refresh) }
                }
                for await updates in group {
                    if let updates { results.append(updates) }
                }
            }
        }
        return results
    }

    private func loadOlderFriendActivity(generation: UUID) async {
        let batch = Array(historyCursors.prefix(4))
        guard !batch.isEmpty else { return }
        let results = await withTaskGroup(of: (FriendHistoryCursor, Page<FriendUpdate>?).self) { group in
            for cursor in batch {
                group.addTask { (cursor, try? await self.historyPage(cursor)) }
            }
            var results: [(FriendHistoryCursor, Page<FriendUpdate>)] = []
            for await (cursor, page) in group {
                if let page { results.append((cursor, page)) }
            }
            return results
        }

        guard !Task.isCancelled, accountGeneration == generation else { return }
        historyCursors.removeFirst(batch.count)
        for (cursor, page) in results where page.more {
            historyCursors.append(FriendHistoryCursor(friend: cursor.friend, kind: cursor.kind, page: cursor.page + 1))
        }
        let older = sortedFriendActivity(results.flatMap { $0.1.items })
        activity = unique(activity + older)
        friendFeedPage += 1
        saveFriendFeed()
    }

    private func historyPage(_ cursor: FriendHistoryCursor) async throws -> Page<FriendUpdate> {
        let result = try await publicListPage(cursor.friend, kind: cursor.kind, page: cursor.page)
        return Page(items: result.items.filter { $0.date != nil }, more: result.more)
    }

    func publicListPage(_ friend: Friend, kind: Kind, page: Int, limit: Int = 50) async throws -> Page<FriendUpdate> {
        let result = try await api.catalog("users/\(friend.name)/\(kind.rawValue)list", [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ])
        let data: Fields? = result.read("data")
        guard let rows: [Fields] = result.read("data") ?? data?.read("entries") else {
            throw APIError(status: 0, message: "Could not load this list.")
        }
        let meta: Fields? = result.read("meta")
        let pagination: Fields? = meta?.read("pagination") ?? result.read("pagination")
        let hasNext: Bool? = pagination?.read("hasNextPage", "has_next_page")
        let total: Int? = data?.read("total")
        let more = hasNext ?? (total.map { $0 > page * limit } ?? (rows.count == limit))
        let entries = rows.compactMap { row -> FriendUpdate? in
            guard let title = Title(row, kind: kind) else { return nil }
            return FriendUpdate(friend: friend, title: title, fields: row)
        }
        return Page(items: entries, more: more)
    }

    private func sortedFriendActivity(_ items: [FriendUpdate]) -> [FriendUpdate] {
        var dated: [(item: FriendUpdate, date: Date)] = unique(items).map { update in
            (item: update, date: activityDate(update.date))
        }
        dated.sort { lhs, rhs in
            if lhs.date == rhs.date { return lhs.item.id < rhs.item.id }
            return lhs.date > rhs.date
        }
        return dated.map { $0.item }
    }

    func fetchFriends(_ user: Account, refresh: Bool = false) async throws {
        let generation = accountGeneration
        let loaded = try await friendList(user, refresh: refresh)
        guard !Task.isCancelled, accountGeneration == generation, account == user else { return }
        friends = loaded
    }

    private func friendList(_ user: Account, refresh: Bool) async throws -> [Friend] {
        let response = try await api.catalog("users/\(user.name)/friends", refresh: refresh)
        guard let entries: [Fields] = response.read("data") else {
            throw APIError(status: 0, message: "Could not load friends.")
        }
        return unique(entries.compactMap(Friend.init).filter { $0.id != user.name.lowercased() })
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

private struct FriendHistoryCursor: Codable {
    let friend: Friend
    let kind: Kind
    let page: Int
}

private struct FriendFeedCache: Codable {
    let accountID: Int
    let friends: [Friend]
    let activity: [FriendUpdate]
    let checkedFriends: Int
    let historyCursors: [FriendHistoryCursor]
    let page: Int

    let englishNames: [String: String]?

    private static let file = URL.cachesDirectory.appending(path: "AniLedger-friends-feed-v1.json")

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

private struct SavedList: Codable, Equatable {
    var items: [ListEntry]
    let page: Int
    let more: Bool
    var needsReconciliation = false
}

struct ProfileStats: Codable {
    let animeCount: Int?
    let mangaCount: Int?
    let daysWatched: Double?
    let chaptersRead: Int?
    let animeDetails: ProfileMediaStats?
    let mangaDetails: ProfileMediaStats?

    var hasDetailedStatistics: Bool { animeDetails != nil || mangaDetails != nil }

    func details(for kind: Kind) -> ProfileMediaStats? {
        kind == .anime ? animeDetails : mangaDetails
    }

    func isListEmpty(for kind: Kind) -> Bool {
        if let count = kind == .anime ? animeCount : mangaCount {
            return count == 0
        }
        guard let details = details(for: kind) else { return false }
        return kind.statuses.allSatisfy { details.statusCounts[$0] == 0 }
    }

    init?(_ fields: Fields) {
        let anime: Fields? = fields.read("anime")
        let manga: Fields? = fields.read("manga")
        guard anime != nil || manga != nil else { return nil }
        animeCount = anime?.read("totalEntries", "total_entries")
        mangaCount = manga?.read("totalEntries", "total_entries")
        daysWatched = anime?.read("daysWatched", "days_watched")
        chaptersRead = manga?.read("chaptersRead", "chapters_read", "chapters")
        animeDetails = anime.map { ProfileMediaStats($0, kind: .anime) }
        mangaDetails = manga.map { ProfileMediaStats($0, kind: .manga) }
    }
}

struct ProfileMediaStats: Codable {
    let statusCounts: [String: Int]
    let meanScore: Double?
    let days: Double?
    let progress: Int?
    let volumes: Int?

    init(_ fields: Fields, kind: Kind) {
        let planKey = kind.statuses.last!
        let values: [String: Int?] = [
            kind.statuses[0]: fields.read(kind.statuses[0]),
            "completed": fields.read("completed"),
            "on_hold": fields.read("onHold", "on_hold"),
            "dropped": fields.read("dropped"),
            planKey: fields.read(kind == .anime ? "planToWatch" : "planToRead", planKey)
        ]
        statusCounts = values.compactMapValues { count in count.flatMap { $0 >= 0 ? $0 : nil } }
        meanScore = fields.read("meanScore", "mean_score")
        days = kind == .anime ? fields.read("daysWatched", "days_watched") : fields.read("daysRead", "days_read")
        progress = kind == .anime
            ? fields.read("episodesWatched", "episodes_watched", "episodes")
            : fields.read("chaptersRead", "chapters_read", "chapters")
        volumes = fields.read("volumesRead", "volumes_read", "volumes")
    }
}

struct CachedProfileValue<Value: Codable>: Codable {
    let value: Value
    let savedAt: Date

    var isFresh: Bool { Date.now.timeIntervalSince(savedAt) < 15 * 60 }
}

struct ProfileSnapshot: Codable {
    var stats: CachedProfileValue<ProfileStats>?
    var favorites: CachedProfileValue<[Kind: [Title]]>?
}

private enum ProfileCache {
    private static let file = URL.cachesDirectory.appending(path: "AniLedger-profiles-v1.json")

    static func read() -> [String: ProfileSnapshot] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: ProfileSnapshot].self, from: data)) ?? [:]
    }

    static func write(_ profiles: [String: ProfileSnapshot]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
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
    iso.formatOptions.insert(.withFractionalSeconds)
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
