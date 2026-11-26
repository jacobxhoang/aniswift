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

    func friendListPage(_ friend: Friend, kind: Kind, page: Int, limit: Int) async throws -> Page<FriendUpdate> {
        if let failure { throw failure }
        return Page(items: [], more: false)
    }

    func titleNames(_ ids: [Int], kind: Kind) async -> [Int: String] { [:] }

    func resolveTitle(_ title: Title) async -> Title? { nil }

    func cachedTitle(_ title: Title) -> Title? { nil }

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
