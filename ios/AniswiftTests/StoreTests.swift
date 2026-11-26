import Foundation
import Testing

@testable import Aniswift

/// A stand-in for the catalog and MyAnimeList client, so the store's sync,
/// paging and failure paths run without a network or a signed-in session.
@MainActor
private final class StubAPI: APIClient {
    var hasSession = true
    var configuredClientID: String?
    var hasCachedCatalog = false
    var account = Account(id: 1, name: "tester", image: nil)

    /// Thrown by every request while it is set.
    var failure: Error?
    /// The English names a batch answers, by MAL id. A missing key answers
    /// nothing, like a title whose batch did not name it.
    var titleNameAnswer: [Int: String] = [:]
    /// Every batch a screen asked for, so the batching itself can be checked.
    private(set) var titleNameRequests: [(kind: Kind, ids: [Int])] = []

    /// The changes the store sent, in order.
    private(set) var savedChanges: [ListChange?] = []

    static func fields(_ json: String) throws -> Fields {
        try JSONDecoder().decode(Fields.self, from: Data(json.utf8))
    }

    func session() async throws -> Account? { account }

    func signIn(clientID: String) async throws -> Account { account }

    func signOut() throws { hasSession = false }

    func list(_ kind: Kind, page: Int) async throws -> Page<ListEntry> {
        if let failure { throw failure }
        return Page(items: [], more: false)
    }

    func listEntry(_ title: Title) async throws -> ListEntry? {
        if let failure { throw failure }
        return nil
    }

    func save(_ title: Title, change: ListChange?) async throws -> Fields? {
        if let failure { throw failure }
        savedChanges.append(change)
        guard change != nil else { return nil }
        return try Self.fields("{}")
    }

    func catalog(_ path: String, _ query: [URLQueryItem], refresh: Bool) async throws -> Fields {
        if let failure { throw failure }
        return try Self.fields(#"{"data": []}"#)
    }

    func friendUpdates(
        _ friend: Friend, refresh: Bool
    ) async throws -> (updates: [FriendUpdate], freshness: CatalogFreshness) {
        if let failure { throw failure }
        return ([], CatalogFreshness())
    }

    /// The pages a stub list request answers, by page, instead of an empty list.
    var listPageAnswer: ((Int) throws -> Page<FriendUpdate>)?

    func friendListPage(
        _ friend: Friend, kind: Kind, page: Int, limit: Int, refresh: Bool
    ) async throws -> Page<FriendUpdate> {
        if let failure { throw failure }
        if let listPageAnswer { return try listPageAnswer(page) }
        return Page(items: [], more: false)
    }

    func titleNames(_ ids: [Int], kind: Kind) async -> [Int: String] {
        titleNameRequests.append((kind, ids))
        return titleNameAnswer.filter { ids.contains($0.key) }
    }

    func resolveTitle(_ title: Title) async -> Title? { nil }

    func cachedTitle(_ title: Title) -> Title? {
        titleNameAnswer[title.malID].map { title.fillingEnglishName(from: $0) }
    }

    func isNameResolved(_ title: Title) -> Bool { titleNameAnswer[title.malID] != nil }

    func cachedDetail(_ title: Title) -> Fields? { nil }

    func savedDetail(_ title: Title) -> (fields: Fields, savedAt: Date)? { nil }

    func clearCatalogCache() { hasCachedCatalog = false }

    func interestStacks(for title: Title, page: Int) async throws -> Page<InterestStack> {
        Page(items: [], more: false)
    }

    func stackDetail(_ id: Int) async throws -> StackDetail {
        throw APIError(status: 404, message: "No stack.")
    }

    func titleReviews(_ title: Title, page: Int) async throws -> Page<TitleReview> {
        Page(items: [], more: false)
    }
}

@Suite("Store sync")
@MainActor
struct StoreTests {
    private func account() -> Account { Account(id: 7, name: "reader", image: nil) }

    private func title(_ id: Int) throws -> Title {
        let fields = try StubAPI.fields("{\"mal_id\": \(id), \"title\": \"Show \(id)\", \"episodes\": 12}")
        return try #require(Title(fields, kind: .anime))
    }

    @Test("A saved progress change lands in the list")
    func changeAppliesOptimistically() async throws {
        ListCache.remove()
        let api = StubAPI()
        let store = Store(api: api)
        store.account = account()

        try await store.change(try title(1), ListChange(status: "watching", progress: 3, rating: 0))

        let entry = try #require(store.lists[.anime]?.first)
        #expect(entry.progress == 3)
        #expect(entry.status == "watching")
        #expect(api.savedChanges.count == 1)
        ListCache.remove()
    }

    @Test("Removing an entry takes it out of the list")
    func removalDropsEntry() async throws {
        ListCache.remove()
        let api = StubAPI()
        let store = Store(api: api)
        store.account = account()
        let item = try title(2)

        try await store.change(item, ListChange(status: "watching", progress: 1, rating: 0))
        #expect(store.lists[.anime]?.count == 1)

        try await store.change(item, nil)
        #expect(store.lists[.anime]?.isEmpty == true)
        ListCache.remove()
    }

    @Test("A failed list sync is reported and cleared by a successful retry")
    func listFailureSurfaces() async {
        ListCache.remove()
        let api = StubAPI()
        let store = Store(api: api)
        store.account = account()

        api.failure = APIError(status: 500, message: "Catalog unavailable.")
        await store.loadLists()
        #expect(store.listFailures[.anime] != nil)
        #expect(store.lists[.anime] == nil)

        api.failure = nil
        await store.loadLists(force: true)
        #expect(store.listFailures[.anime] == nil)
        #expect(store.lists[.anime]?.isEmpty == true)
        ListCache.remove()
    }
}

@Suite("Friend feed cursors")
struct FriendHistoryTests {
    private func friend(_ name: String) throws -> Friend {
        let fields = try JSONDecoder().decode(Fields.self, from: Data("{\"username\": \"\(name)\"}".utf8))
        return try #require(Friend(fields))
    }

    @Test("A cursor whose page failed stays queued for a retry")
    func failedCursorIsKept() throws {
        let ana = try friend("ana")
        let ben = try friend("ben")
        let answered = FriendHistoryCursor(friend: ana, kind: .anime, page: 1)
        let unanswered = FriendHistoryCursor(friend: ben, kind: .anime, page: 1)

        let advanced = advancedHistoryCursors(
            [answered, unanswered],
            answered: [
                (cursor: answered, page: Page<FriendUpdate>(items: [], more: true)),
                (cursor: unanswered, page: nil),
            ])

        #expect(advanced.contains(FriendHistoryCursor(friend: ana, kind: .anime, page: 2)))
        #expect(advanced.contains(unanswered))
        #expect(!advanced.contains(answered))
    }

    @Test("A finished list retires its cursor")
    func finishedListIsDropped() throws {
        let ana = try friend("ana")
        let cursor = FriendHistoryCursor(friend: ana, kind: .manga, page: 4)

        let advanced = advancedHistoryCursors(
            [cursor], answered: [(cursor: cursor, page: Page<FriendUpdate>(items: [], more: false))])

        #expect(advanced.isEmpty)
    }
}

@Suite("Friend list batches")
@MainActor
struct FriendListBatchTests {
    private func friend() throws -> Friend {
        let fields = try StubAPI.fields(#"{"username": "ana"}"#)
        return try #require(Friend(fields))
    }

    private func row(_ id: Int, friend: Friend) throws -> FriendUpdate {
        let fields = try StubAPI.fields("{\"mal_id\": \(id), \"title\": \"Show \(id)\"}")
        let title = try #require(Title(fields, kind: .anime))
        return FriendUpdate(friend: friend, title: title, fields: fields)
    }

    @Test("A batch reads every page up to the one that reports no more")
    func batchReadsToTheEnd() async throws {
        let api = StubAPI()
        let store = Store(api: api)
        let friend = try friend()
        let rows = try (1...3).map { try row($0, friend: friend) }
        api.listPageAnswer = { page in
            switch page {
            case 1: Page(items: [rows[0]], more: true, total: 3)
            case 2: Page(items: [rows[1]], more: true, total: 3)
            default: Page(items: [rows[2]], more: false, total: 3)
            }
        }

        let batch = await store.publicListBatch(friend, kind: .anime, from: 1)

        #expect(batch.items.map(\.title.malID) == [1, 2, 3])
        #expect(batch.nextPage == nil)
        #expect(batch.total == 3)
        #expect(batch.failure == nil)
    }

    @Test("A batch stops at the number of pages it was given")
    func batchStopsAtItsPageCount() async throws {
        let api = StubAPI()
        let store = Store(api: api)
        let friend = try friend()
        let rows = try (1...3).map { try row($0, friend: friend) }
        api.listPageAnswer = { page in Page(items: [rows[page - 1]], more: true, total: 9) }

        let batch = await store.publicListBatch(friend, kind: .anime, from: 1, pages: 2)

        #expect(batch.items.count == 2)
        #expect(batch.nextPage == 3)
    }

    @Test("A page that fails keeps the rows before it and the page to retry")
    func failedPageKeepsEarlierRows() async throws {
        let api = StubAPI()
        let store = Store(api: api)
        let friend = try friend()
        let first = try row(1, friend: friend)
        api.listPageAnswer = { page in
            guard page == 1 else { throw APIError(status: 500, message: "Catalog unavailable.") }
            return Page(items: [first], more: true, total: 3)
        }

        let batch = await store.publicListBatch(friend, kind: .anime, from: 1)

        #expect(batch.items.count == 1)
        #expect(batch.nextPage == 2)
        #expect((batch.failure as? APIError)?.status == 500)
    }

    @Test("A page that repeats rows already read ends the batch")
    func repeatingPageEndsBatch() async throws {
        let api = StubAPI()
        let store = Store(api: api)
        let friend = try friend()
        let first = try row(1, friend: friend)
        api.listPageAnswer = { _ in Page(items: [first], more: true, total: 9) }

        let batch = await store.publicListBatch(friend, kind: .anime, from: 1)

        #expect(batch.items.count == 1)
        #expect(batch.nextPage == nil)
        #expect(batch.failure == nil)
    }
}


@Suite("English titles")
@MainActor
struct TitleNameTests {
    private func row(_ id: Int, kind: Kind) throws -> Title {
        let fields = try StubAPI.fields("{\"mal_id\": \(id), \"title\": \"Show \(id)\"}")
        return try #require(Title(fields, kind: kind))
    }

    @Test("A page of rows is named in one request per kind")
    func pageNamesInOneRequestPerKind() async throws {
        let api = StubAPI()
        let store = Store(api: api)
        api.titleNameAnswer = [1: "Show One", 2: "Show Two", 3: "Book Three"]
        let anime = try [1, 2].map { try row($0, kind: .anime) }
        let manga = try [3].map { try row($0, kind: .manga) }

        await store.resolveNames(in: anime + manga)

        #expect(api.titleNameRequests.count == 2)
        #expect(store.named(anime[0]).englishName == "Show One")
        #expect(store.named(manga[0]).englishName == "Book Three")
    }

    @Test("Rows already named cost no request the next time")
    func namedRowsSkipTheLookup() async throws {
        let api = StubAPI()
        let store = Store(api: api)
        api.titleNameAnswer = [4: "Show Four"]
        let rows = [try row(4, kind: .anime)]

        await store.resolveNames(in: rows)
        await store.resolveNames(in: rows)

        #expect(api.titleNameRequests.count == 1)
    }

    @Test("A row that already carries its English title asks for nothing")
    func namedRowAsksForNothing() async throws {
        let api = StubAPI()
        let store = Store(api: api)
        let fields = try StubAPI.fields(
            #"{"mal_id": 5, "title": "Shingeki no Kyojin", "alternative_titles": {"en": "Attack on Titan"}}"#)
        let title = try #require(Title(fields, kind: .anime))

        await store.resolveNames(in: [title])

        #expect(api.titleNameRequests.isEmpty)
        #expect(store.named(title).englishName == "Attack on Titan")
    }
}
