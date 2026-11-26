import SwiftUI

@MainActor
final class Store: ObservableObject {
    /// The catalog and MyAnimeList client. It is injected so list sync, feed
    /// paging and the cache paths can run against a stub in tests.
    let api: any APIClient
    @Published var account: Account?
    @Published var checking = true
    @Published var message: String?
    @Published private(set) var organization = ListOrganization()
    @Published private var savedLists: [Kind: SavedList] = [:]
    /// Every list row by title id, so a poster tile reads its saved row in one
    /// step: Discover draws ten shelves of fourteen tiles, and each tile used to
    /// walk up to a thousand rows on every pass.
    private(set) var entries: [Kind: [String: ListEntry]] = [:]
    @Published private(set) var refreshingLists: Set<Kind> = []
    /// Why a kind's list could not be synced, so the list screen can offer a
    /// retry instead of drawing an empty list.
    @Published private(set) var listFailures: [Kind: String] = [:]
    /// Kinds whose first page has been requested but has not finished loading.
    @Published private(set) var pendingListLoads: Set<Kind> = []
    @Published var friends: [Friend] = []
    @Published var activity: [FriendUpdate] = []
    @Published var friendMessage: String?
    @Published var loadingFriends = false
    @Published private(set) var friendFeedPage = 0
    @Published private var checkedFriends = 0
    @Published private var historyCursors: [FriendHistoryCursor] = []
    @Published private var feedEnglishNames: [String: String] = [:]
    @Published private(set) var profileStatuses: [String: PublicDataStatus] = [:]
    @Published private(set) var feedStatus = PublicDataStatus()

    /// Set when a page of the feed could not be read, so the feed stops asking
    /// for a page that will not arrive until the reader refreshes it.
    @Published private(set) var feedPageStalled = false
    var hasMoreFriendActivity: Bool {
        (checkedFriends < friends.count || !historyCursors.isEmpty) && !feedPageStalled
    }

    @Published private var profiles = ProfileCache.read()
    private var profileRequests: [String: Task<ProfileFetchOutcome, Never>] = [:]
    private var publicBackoff: [String: PublicBackoff] = [:]
    private var publicRetryTasks: [String: Task<Void, Never>] = [:]
    private var pendingFeedSave: Task<Void, Never>?
    private static let feedBackoffKey = "feed"
    private static let publicRetryDelays: [TimeInterval] = [15, 30, 60]
    /// One friend answers with a handful of updates, so a page is built from
    /// several friends: twelve per request group, up to four groups, until the
    /// page holds enough rows to scroll instead of looking empty.
    private static let feedFriendBatch = 12
    private static let feedBatchLimit = 4
    private static let feedOlderPageLimit = 2
    private static let feedPageTarget = 30
    /// A saved feed older than this is refreshed when the tab is opened, so a
    /// snapshot from an earlier run cannot keep the feed short for good.
    private static let feedWindow: TimeInterval = 10 * 60

    init() {
        api = API()
    }

    init(api: any APIClient) {
        self.api = api
    }

    var malFavorites: [Kind: [Title]] {
        account.flatMap { profile(for: $0.name).favorites?.value } ?? [:]
    }

    func profile(for name: String) -> ProfileSnapshot {
        profiles[name.lowercased()] ?? ProfileSnapshot()
    }

    func profileStatus(for name: String) -> PublicDataStatus? {
        profileStatuses[name.lowercased()]
    }

    func loadProfile(_ name: String, refresh: Bool = false) async -> Bool {
        await loadProfile(name, refresh: refresh, userInitiated: refresh)
    }

    private func loadProfile(_ name: String, refresh: Bool, userInitiated: Bool) async -> Bool {
        let key = name.lowercased()
        let backoffKey = "profile:\(key)"
        if let pending = profileRequests[key] { return await pending.value.loaded }

        let cached = profile(for: name)
        let needsStats = refresh || cached.stats?.isFresh != true || cached.stats?.value.hasDetailedStatistics != true
        let needsFavorites = refresh || cached.favorites?.isFresh != true
        guard needsStats || needsFavorites else { return true }

        if userInitiated {
            clearPublicBackoff(backoffKey)
        } else if !canAttemptPublicRefresh(backoffKey) {
            // A backoff can only exist after a failure, so the note is already up.
            return false
        }

        let task = Task {
            await profileOutcome(for: name, refresh: refresh,
                                 needsStats: needsStats, needsFavorites: needsFavorites)
        }
        profileRequests[key] = task
        let outcome = await task.value
        profileRequests[key] = nil

        if outcome.loaded, !outcome.stale {
            clearPublicBackoff(backoffKey)
            profileStatuses[key] = nil
        } else {
            var status = profileStatuses[key] ?? PublicDataStatus()
            status.isShowingSavedData = true
            status.failure = outcome.failure
            status.savedAt = outcome.savedAt ?? status.savedAt
            profileStatuses[key] = status
            schedulePublicRetry(backoffKey) { [weak self] in
                _ = await self?.loadProfile(name, refresh: true, userInitiated: false)
            }
        }
        return outcome.loaded
    }

    private func profileOutcome(for name: String, refresh: Bool,
                                needsStats: Bool, needsFavorites: Bool) async -> ProfileFetchOutcome {
        async let statsResult = loadProfileStatsIfNeeded(name, refresh: refresh, needed: needsStats)
        async let favoritesResult = loadProfileFavoritesIfNeeded(name, refresh: refresh, needed: needsFavorites)
        let (stats, favorites) = await (statsResult, favoritesResult)

        var updated = profile(for: name)
        var loaded = true
        var stale = false
        var failure: String?
        var providerFetchedAt: Date?
        var wrote = false

        switch stats {
        case .success(.some(let fetch)):
            updated.stats = CachedProfileValue(value: fetch.stats, savedAt: .now)
            stale = stale || fetch.freshness.isStale
            providerFetchedAt = fetch.freshness.fetchedAt ?? providerFetchedAt
            wrote = true
        case .success(.none):
            break
        case .failure(let error):
            loaded = false
            failure = failureMessage(error)
        }

        switch favorites {
        case .success(.some(let fetch)):
            updated.favorites = CachedProfileValue(value: fetch.favorites, savedAt: .now)
            stale = stale || fetch.freshness.isStale
            providerFetchedAt = fetch.freshness.fetchedAt ?? providerFetchedAt
            wrote = true
        case .success(.none):
            break
        case .failure(let error):
            loaded = false
            failure = failureMessage(error)
        }

        if wrote {
            profiles[name.lowercased()] = updated
            ProfileCache.write(profiles)
        }
        let savedAt = [updated.stats?.savedAt, updated.favorites?.savedAt].compactMap { $0 }.min()
        return ProfileFetchOutcome(loaded: loaded, stale: stale,
                                   savedAt: providerFetchedAt ?? savedAt, failure: failure)
    }

    private struct ProfileStatsFetch {
        let stats: ProfileStats
        let freshness: CatalogFreshness
    }

    private struct ProfileFavoritesFetch {
        let favorites: [Kind: [Title]]
        let freshness: CatalogFreshness
    }

    private struct ProfileFetchOutcome {
        let loaded: Bool
        let stale: Bool
        let savedAt: Date?
        let failure: String?
    }

    private struct PublicBackoff {
        var attempts = 0
        var nextAttempt: Date?
    }

    private func loadProfileStatsIfNeeded(_ name: String, refresh: Bool, needed: Bool) async -> Result<ProfileStatsFetch?, Error> {
        guard needed else { return .success(nil) }
        return await loadProfileStats(name, refresh: refresh)
    }

    private func loadProfileFavoritesIfNeeded(_ name: String, refresh: Bool, needed: Bool) async -> Result<ProfileFavoritesFetch?, Error> {
        guard needed else { return .success(nil) }
        return await loadProfileFavorites(name, refresh: refresh)
    }

    private func loadProfileStats(_ name: String, refresh: Bool) async -> Result<ProfileStatsFetch?, Error> {
        do {
            let response = try await api.catalog("users/\(name)/statistics", [], refresh: refresh)
            guard let data: Fields = response.read("data"), let stats = ProfileStats(data) else {
                return .failure(APIError(status: 0, message: "The profile statistics could not be read."))
            }
            return .success(ProfileStatsFetch(stats: stats, freshness: CatalogFreshness(response.read("meta"))))
        } catch {
            return .failure(error)
        }
    }

    private func loadProfileFavorites(_ name: String, refresh: Bool) async -> Result<ProfileFavoritesFetch?, Error> {
        do {
            let response = try await api.catalog("users/\(name)/favorites", [], refresh: refresh)
            guard let data: Fields = response.read("data") else {
                return .failure(APIError(status: 0, message: "The profile favorites could not be read."))
            }
            let favorites = Dictionary(uniqueKeysWithValues: Kind.allCases.map { kind in
                let entries: [Fields] = data.read(kind.rawValue) ?? []
                return (kind, entries.compactMap { Title($0, kind: kind) })
            })
            return .success(ProfileFavoritesFetch(favorites: favorites, freshness: CatalogFreshness(response.read("meta"))))
        } catch {
            return .failure(error)
        }
    }

    private func failureMessage(_ error: Error) -> String {
        plainMessage(error, fallback: "Some public profile details are unavailable.")
    }

    private func canAttemptPublicRefresh(_ key: String) -> Bool {
        guard let next = publicBackoff[key]?.nextAttempt else { return true }
        // Let a scheduled retry run even if its sleep wakes a moment early.
        return Date() >= next.addingTimeInterval(-1)
    }

    private func clearPublicBackoff(_ key: String) {
        publicBackoff[key] = nil
        publicRetryTasks[key]?.cancel()
        publicRetryTasks[key] = nil
    }

    private func schedulePublicRetry(_ key: String, retry: @escaping @MainActor () async -> Void) {
        var backoff = publicBackoff[key] ?? PublicBackoff()
        backoff.attempts += 1
        guard backoff.attempts <= Self.publicRetryDelays.count else {
            backoff.nextAttempt = .distantFuture
            publicBackoff[key] = backoff
            return
        }
        let delay = Self.publicRetryDelays[backoff.attempts - 1]
        backoff.nextAttempt = Date().addingTimeInterval(delay)
        publicBackoff[key] = backoff
        publicRetryTasks[key]?.cancel()
        publicRetryTasks[key] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await retry()
        }
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
            if account == nil { message = plainMessage(error, fallback: "Could not check your session.") }
        }
    }

    func connected(_ user: Account) async {
        let cache = ListCache.read()
        setAccount(user)
        if let cache, cache.account.id == user.id, savedLists.isEmpty {
            savedLists = cache.lists
            entries = cache.lists.mapValues { Self.index($0.items) }
            ListCache(account: user, lists: savedLists).write()
        }
        await loadLists(force: true)
    }

    func disconnect() {
        do {
            try api.signOut()
            setAccount(nil)
        } catch { message = plainMessage(error, fallback: "Could not sign out.") }
    }

    private func setAccount(_ user: Account?) {
        if account?.id != user?.id || user == nil {
            accountGeneration = UUID()
            organization = user.map { readOrganization(for: $0) } ?? ListOrganization()
            listRevisions = [:]
            pagingLists = []
            refreshingLists = []
            listFailures = [:]
            pendingListLoads = []
            savedLists = [:]
            entries = [:]
            activity = []
            friends = []
            checkedFriends = 0
            friendFeedPage = 0
            historyCursors = []
            feedEnglishNames = [:]
            loadingFriends = false
            friendMessage = nil
            profileStatuses = [:]
            feedStatus = PublicDataStatus()
            feedPageStalled = false
            publicBackoff = [:]
            for task in publicRetryTasks.values { task.cancel() }
            publicRetryTasks = [:]
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
        feedStatus = PublicDataStatus(savedAt: cache.savedAt)
    }

    func friendFeedTitle(_ title: Title) -> Title {
        title.fillingEnglishName(from: feedEnglishNames[title.id])
    }

    func rememberFriendFeedEnglishName(_ name: String, for title: Title) {
        rememberFriendFeedEnglishNames([title.id: name])
    }

    private func rememberFriendFeedEnglishNames(_ names: [String: String]) {
        guard account != nil else { return }
        let additions = names.filter { feedEnglishNames[$0.key] != $0.value }
        guard !additions.isEmpty else { return }
        feedEnglishNames.merge(additions) { _, new in new }
        // A page that names a dozen titles used to encode and write the whole
        // snapshot a dozen times, once per name; the write is coalesced instead.
        saveFriendFeedSoon()
    }

    /// Writes the feed snapshot once after a burst of changes.
    private func saveFriendFeedSoon() {
        guard pendingFeedSave == nil else { return }
        pendingFeedSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.pendingFeedSave = nil
            self.saveFriendFeed()
        }
    }

    /// Jikan Edge list rows carry only the original title, so the whole page is
    /// resolved in grouped Tenrai requests instead of one detail request per row.
    private func resolveEnglishNames(in updates: [FriendUpdate]) async {
        var pending: [Kind: [Int]] = [:]
        for title in unique(updates.map(\.title)) where title.needsTitleLookup {
            pending[title.kind, default: []].append(title.malID)
        }
        guard !pending.isEmpty else { return }
        // One request per kind, both in flight at once.
        await withTaskGroup(of: [String: String].self) { group in
            for (kind, ids) in pending {
                group.addTask {
                    let names = await self.api.titleNames(ids, kind: kind)
                    return names.reduce(into: [String: String]()) { result, entry in
                        result["\(kind.rawValue)-\(entry.key)"] = entry.value
                    }
                }
            }
            for await names in group { rememberFriendFeedEnglishNames(names) }
        }
    }

    private func saveFriendFeed() {
        guard let account else { return }
        FriendFeedCache(accountID: account.id, friends: friends, activity: activity,
                        checkedFriends: checkedFriends, historyCursors: historyCursors,
                        page: friendFeedPage, englishNames: feedEnglishNames, savedAt: .now).write()
        feedStatus.savedAt = .now
    }

    func handle(_ error: Error) {
        Haptics.error()
        if (error as? APIError)?.status == 401 { disconnect() }
        message = plainMessage(error, fallback: "Could not finish that request.")
    }

    func loadLists(force: Bool = false) async {
        let generation = accountGeneration
        let pending = Kind.allCases.filter { force || savedLists[$0] == nil }
        guard !pending.isEmpty else { return }
        pendingListLoads.formUnion(pending)
        defer { if accountGeneration == generation { pendingListLoads.subtract(pending) } }
        for kind in pending {
            guard accountGeneration == generation else { return }
            defer { if accountGeneration == generation { pendingListLoads.remove(kind) } }
            do { try await refreshList(kind) }
            catch {
                // A list refresh cancelled by navigation is not a failure worth alerting.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                if accountGeneration == generation {
                    listFailures[kind] = failureMessage(error)
                    if (error as? APIError)?.status == 401 || savedLists[kind] == nil {
                        handle(error)
                    }
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

    private func organizationKey(_ accountID: Int) -> String { "aniswift.organization.v1.\(accountID)" }

    private func readOrganization(for user: Account) -> ListOrganization {
        guard let data = UserDefaults.standard.data(forKey: organizationKey(user.id)) else { return ListOrganization() }
        return (try? JSONDecoder().decode(ListOrganization.self, from: data)) ?? ListOrganization()
    }

    private func updateList(_ kind: Kind, _ snapshot: SavedList) {
        guard let account else { return }
        // Reaching here means the provider answered, so an earlier failure is stale.
        listFailures[kind] = nil
        guard savedLists[kind] != snapshot else { return }
        savedLists[kind] = snapshot
        entries[kind] = Self.index(snapshot.items)
        ListCache(account: account, lists: savedLists).write()
    }

    /// Every row of a list by title id, for a poster tile's lookup.
    private static func index(_ items: [ListEntry]) -> [String: ListEntry] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func loadFriends(reset: Bool = false) async {
        await loadFriends(reset: reset, userInitiated: reset)
    }

    /// What the Feed tab does when it opens: a saved page is drawn at once, and
    /// it is refreshed when it is older than the feed's window, or when the last
    /// load left nothing to page from — so a thin snapshot from an earlier run
    /// cannot keep the feed short for good.
    func openFeed() async {
        guard account != nil, !loadingFriends else { return }
        if friendFeedPage == 0 {
            await loadFriends()
            return
        }
        if let savedAt = feedStatus.savedAt, Date().timeIntervalSince(savedAt) < Self.feedWindow,
            hasMoreFriendActivity || !activity.isEmpty
        {
            return
        }
        await loadFriends(reset: true, userInitiated: false)
    }

    private func loadFriends(reset: Bool, userInitiated: Bool) async {
        guard let user = account, !loadingFriends else { return }
        let generation = accountGeneration
        loadingFriends = true
        defer { if accountGeneration == generation { loadingFriends = false } }

        if userInitiated {
            clearPublicBackoff(Self.feedBackoffKey)
        } else if !canAttemptPublicRefresh(Self.feedBackoffKey) {
            friendMessage = feedStatus.failure
            return
        }
        friendMessage = nil
        if reset { feedPageStalled = false }

        if !reset, friendFeedPage > 0, checkedFriends >= friends.count {
            await loadOlderFriendActivity(generation: generation)
            return
        }

        do {
            let refreshedFriends: [Friend]
            var stale = false
            var providerFetchedAt: Date?
            if reset || friends.isEmpty {
                let loaded = try await friendList(user, refresh: reset)
                refreshedFriends = loaded.friends
                stale = loaded.freshness.isStale
                providerFetchedAt = loaded.freshness.fetchedAt
            } else {
                refreshedFriends = friends
            }
            guard !Task.isCancelled, accountGeneration == generation else { return }

            // Every friend's lists are seeded at page one, so a page that recent
            // activity cannot fill can be filled from them instead.
            var cursors =
                reset || friendFeedPage == 0
                ? refreshedFriends.flatMap { friend in
                    Kind.allCases.map { FriendHistoryCursor(friend: friend, kind: $0, page: 1) }
                }
                : historyCursors
            // One friend answers with a handful of updates, so a page built from
            // one group of friends reads as a feed with nothing in it. Keep asking
            // while the page is thin, up to four groups, and stop as soon as it
            // holds enough rows to scroll.
            var start = reset ? 0 : checkedFriends
            var updates: [FriendUpdate] = []
            var failures = 0
            var batches = 0
            while batches < Self.feedBatchLimit, start < refreshedFriends.count {
                let batch = Array(refreshedFriends.dropFirst(start).prefix(Self.feedFriendBatch))
                guard !batch.isEmpty else { break }
                let result = await loadRecentFriendActivity(batch, refresh: reset)
                guard !Task.isCancelled, accountGeneration == generation else { return }
                start += batch.count
                batches += 1
                updates += result.updates
                failures += result.failures
                stale = stale || result.stale
                providerFetchedAt = result.fetchedAt ?? providerFetchedAt
                if unique(updates).count >= Self.feedPageTarget { break }
            }

            // Recent activity is only a friend's last few entries, so a page that
            // is still thin fills from their list pages before it is drawn — the
            // pages "Load older activity" walks — instead of showing a handful of
            // rows and leaving the reader to tap for the rest.
            var olderPages = 0
            while unique(updates).count < Self.feedPageTarget, olderPages < Self.feedOlderPageLimit,
                let older = await loadOlderActivity(cursors)
            {
                guard !Task.isCancelled, accountGeneration == generation else { return }
                cursors = older.cursors
                updates += older.updates
                olderPages += 1
            }

            // Keep the snapshot the user is already reading instead of replacing
            // it with an empty page when nothing at all could be read.
            if reset, unique(updates).isEmpty, failures > 0, !activity.isEmpty {
                // The page did not land, so the feed must not keep asking for one.
                feedPageStalled = true
                markFeedSavedData(message: "Could not refresh the feed.",
                                  savedAt: providerFetchedAt ?? feedStatus.savedAt)
                return
            }

            if reset { friendFeedPage = 0 }
            historyCursors = cursors
            friends = refreshedFriends
            checkedFriends = start
            let sorted = sortedFriendActivity(updates)
            await resolveEnglishNames(in: sorted)
            guard !Task.isCancelled, accountGeneration == generation else { return }
            activity = reset ? sorted : unique(activity + sorted)
            friendFeedPage += 1
            feedPageStalled = false
            saveFriendFeed()

            // A stray friend whose list is private should not put the whole feed
            // behind a note, so only an empty page says so.
            if stale || (failures > 0 && unique(updates).isEmpty) {
                markFeedSavedData(message: failures > 0 ? "Could not refresh the feed." : nil,
                                  savedAt: providerFetchedAt ?? feedStatus.savedAt)
            } else {
                clearFeedSavedData()
            }
        } catch {
            guard !Task.isCancelled, accountGeneration == generation else { return }
            feedPageStalled = true
            markFeedSavedData(message: failureMessage(error), savedAt: feedStatus.savedAt)
        }
    }

    private func markFeedSavedData(message: String?, savedAt: Date?) {
        var status = feedStatus
        status.isShowingSavedData = true
        status.failure = message
        status.savedAt = savedAt ?? status.savedAt
        feedStatus = status
        friendMessage = activity.isEmpty ? message : nil
        // Heal the feed on its own only while there is nothing on screen: a
        // scheduled retry reloads the first page, which would replace the page
        // the reader is in. With rows showing, the note's Retry is their call.
        guard activity.isEmpty else { return }
        schedulePublicRetry(Self.feedBackoffKey) { [weak self] in
            _ = await self?.loadFriends(reset: true, userInitiated: false)
        }
    }

    private func clearFeedSavedData() {
        feedStatus = PublicDataStatus(savedAt: Date())
        clearPublicBackoff(Self.feedBackoffKey)
    }

    private struct FriendActivityBatch {
        var updates: [FriendUpdate] = []
        var failures = 0
        var stale = false
        var fetchedAt: Date?
    }

    private func loadRecentFriendActivity(_ batch: [Friend], refresh: Bool) async -> FriendActivityBatch {
        var result = FriendActivityBatch()
        let concurrency = 6
        for start in stride(from: 0, to: batch.count, by: concurrency) {
            guard !Task.isCancelled else { return result }
            let friends = batch[start..<min(start + concurrency, batch.count)]
            await withTaskGroup(of: (updates: [FriendUpdate]?, freshness: CatalogFreshness).self) { group in
                for friend in friends {
                    // The fetch and its decode both leave the main actor, so six
                    // friends are six requests in flight rather than six tasks
                    // queueing up to parse their payloads on the main thread.
                    group.addTask {
                        do {
                            let rows = try await self.api.friendUpdates(friend, refresh: refresh)
                            return (rows.updates, rows.freshness)
                        } catch {
                            return (nil, CatalogFreshness())
                        }
                    }
                }
                for await item in group {
                    if let updates = item.updates { result.updates += updates } else { result.failures += 1 }
                    result.stale = result.stale || item.freshness.isStale
                    result.fetchedAt = item.freshness.fetchedAt ?? result.fetchedAt
                }
            }
        }
        return result
    }

    private struct OlderActivityBatch {
        var updates: [FriendUpdate] = []
        var cursors: [FriendHistoryCursor] = []
    }

    /// The next four list pages, newest first across friends. A batch nothing
    /// answered returns nil rather than consuming the cursors it did not fill, so
    /// a failure never drops a friend's older pages.
    private func loadOlderActivity(_ cursors: [FriendHistoryCursor]) async -> OlderActivityBatch? {
        let batch = Array(cursors.prefix(4))
        guard !batch.isEmpty else { return nil }
        let answered = await withTaskGroup(of: (FriendHistoryCursor, Page<FriendUpdate>?).self) { group in
            for cursor in batch {
                group.addTask { (cursor, try? await self.historyPage(cursor)) }
            }
            // Every cursor answers, with nil for a page that could not be read, so
            // the bookkeeping can tell a finished list from a failed request.
            var pages: [(cursor: FriendHistoryCursor, page: Page<FriendUpdate>?)] = []
            for await answer in group {
                pages.append((cursor: answer.0, page: answer.1))
            }
            return pages
        }
        let updatedCursors = advancedHistoryCursors(cursors, answered: answered)
        guard updatedCursors != cursors else { return nil }
        return OlderActivityBatch(updates: answered.flatMap { $0.page?.items ?? [] }, cursors: updatedCursors)
    }

    private func loadOlderFriendActivity(generation: UUID) async {
        guard let batch = await loadOlderActivity(historyCursors) else {
            guard !Task.isCancelled, accountGeneration == generation else { return }
            // Nothing answered. Keep the cursors queued for the next refresh and
            // stop the feed from asking for a page that is not coming.
            feedPageStalled = true
            friendMessage = "Could not load older activity."
            return
        }
        guard !Task.isCancelled, accountGeneration == generation else { return }
        feedPageStalled = false
        historyCursors = batch.cursors
        // The batch was consumed even when it held nothing this feed can show, so
        // the page advances and the next batch is asked for.
        friendFeedPage += 1
        let older = sortedFriendActivity(batch.updates)
        if !older.isEmpty {
            await resolveEnglishNames(in: older)
            guard !Task.isCancelled, accountGeneration == generation else { return }
            activity = unique(activity + older)
        }
        saveFriendFeed()
    }

    private func historyPage(_ cursor: FriendHistoryCursor) async throws -> Page<FriendUpdate> {
        try await api.friendListPage(cursor.friend, kind: cursor.kind, page: cursor.page, limit: 50)
    }

    func publicListPage(_ friend: Friend, kind: Kind, page: Int, limit: Int = 50) async throws -> Page<FriendUpdate> {
        try await api.friendListPage(friend, kind: kind, page: page, limit: limit)
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
        friends = loaded.friends
    }

    private func friendList(_ user: Account, refresh: Bool) async throws -> (friends: [Friend], freshness: CatalogFreshness) {
        let response = try await api.catalog("users/\(user.name)/friends", [], refresh: refresh)
        guard let entries: [Fields] = response.read("data") else {
            throw APIError(status: 0, message: "Could not load friends.")
        }
        return (unique(entries.compactMap(Friend.init).filter { $0.id != user.name.lowercased() }),
                CatalogFreshness(response.read("meta")))
    }

    func publicUpdates(_ friend: Friend, refresh: Bool = false) async throws -> [FriendUpdate] {
        try await api.friendUpdates(friend, refresh: refresh).updates
    }

    /// Activity already cached by the friends feed, used when a friend profile
    /// cannot reach Jikan Edge.
    func savedUpdates(for friend: Friend) -> [FriendUpdate] {
        activity.filter { $0.friend.id == friend.id }
    }

    /// A title page's friend row shows a friend's recent public activity, so one
    /// `userupdates` request answers it. Walking the friend's list pages used to
    /// cost up to ten 300-row requests per friend, for rows the page never shows.
    func friendEntry(_ friend: Friend, _ title: Title) async throws -> FriendUpdate? {
        try await publicUpdates(friend).first { $0.title.id == title.id }
    }
}

func unique<T: Identifiable>(_ values: [T]) -> [T] {
    var seen = Set<T.ID>()
    return values.filter { seen.insert($0.id).inserted }
}

/// What a failure is told as: a provider's own sentence when it wrote one, and a
/// plain fallback for a transport or decoding failure instead of the system's
/// jargon. Every screen that shows an error goes through here.
func plainMessage(_ error: Error, fallback: String) -> String {
    if let api = error as? APIError { return api.message }
    guard let failure = error as? URLError else { return fallback }
    switch failure.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
        return "Aniswift could not reach the internet."
    case .timedOut:
        return "The request took too long. Try again."
    default:
        return fallback
    }
}

/// The formats a provider writes a date in, each with its own formatter: a
/// formatter cannot be reformatted while another row is reading it, and a row
/// used to allocate a pair of them on every call.
private enum ActivityDates {
    static let iso = ISO8601DateFormatter()
    static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()
    static let dates: [(format: String, formatter: DateFormatter)] =
        ["yyyy-MM-dd", "MMM d, yyyy", "MMM d, h:mm a", "MMM d"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.defaultDate = Date()
            formatter.dateFormat = format
            return (format, formatter)
        }
}

func activityDate(_ value: String?) -> Date {
    guard let value else { return .distantPast }
    if let date = ActivityDates.iso.date(from: value) { return date }
    if let date = ActivityDates.isoFractional.date(from: value) { return date }
    for entry in ActivityDates.dates {
        if let date = entry.formatter.date(from: value) {
            if !entry.format.contains("y"), date > Date() {
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
