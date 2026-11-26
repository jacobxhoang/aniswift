import Foundation

/// Why a screen is showing saved public data: the Jikan Edge proxy served a
/// stale copy, or a request failed while the previous snapshot stays visible.
struct PublicDataStatus: Equatable {
    var isShowingSavedData = false
    var failure: String? = nil
    var savedAt: Date? = nil
}

/// Snapshot files are written on paths that run while someone is reading: a list
/// edit, a feed page, a title page. Encoding stays where the value lives and the
/// write itself moves to one serial queue, so the main actor never waits on the
/// disk and two writes to the same file cannot land out of order.
enum SnapshotWriter {
    private static let queue = DispatchQueue(label: "org.aniswift.snapshot-writes", qos: .utility)

    static func write(_ data: Data, to file: URL) {
        queue.async {
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Removing waits for the writes already queued, so a snapshot cleared at
    /// sign-out cannot be written back by a request that finished just before.
    static func remove(_ file: URL) {
        queue.sync {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// One page of a kind's list as it was saved, with the flag that says a list
/// edit landed while that page range was being fetched.
struct SavedList: Codable, Equatable {
    var items: [ListEntry]
    let page: Int
    let more: Bool
    var needsReconciliation = false
}

/// The next page of one friend's activity to read for the feed. A feed page
/// covers every friend, so the queue holds a cursor per friend and kind.
struct FriendHistoryCursor: Codable, Equatable {
    let friend: Friend
    let kind: Kind
    let page: Int
}

/// Which history cursors survive a batch. A page that answered is consumed and
/// replaced by the next page when the list has one; a page that failed stays in
/// the queue, so a later refresh retries that friend instead of dropping it.
func advancedHistoryCursors(
    _ cursors: [FriendHistoryCursor],
    answered: [(cursor: FriendHistoryCursor, page: Page<FriendUpdate>?)]
) -> [FriendHistoryCursor] {
    var remaining = cursors
    for (cursor, page) in answered {
        guard let index = remaining.firstIndex(of: cursor), let page else { continue }
        remaining.remove(at: index)
        if page.more {
            remaining.append(FriendHistoryCursor(friend: cursor.friend, kind: cursor.kind, page: cursor.page + 1))
        }
    }
    return remaining
}

struct FriendFeedCache: Codable {
    let accountID: Int
    let friends: [Friend]
    let activity: [FriendUpdate]
    let checkedFriends: Int
    let historyCursors: [FriendHistoryCursor]
    let page: Int

    let savedAt: Date?

    private static let file = URL.cachesDirectory.appending(path: "Aniswift-friends-feed-v1.json")

    static func read() -> Self? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SnapshotWriter.write(data, to: Self.file)
    }

    static func remove() {
        SnapshotWriter.remove(file)
    }
}

/// The English titles resolved so far, by `kind-id`, kept across launches so a
/// list opens with its names in place instead of a catalog request per row every
/// time the app starts. `nameless` holds the titles a batch answered as having
/// no English name, so no row asks for one again.
struct TitleNameCache: Codable {
    var names: [String: String] = [:]
    var nameless: Set<String> = []

    private static let file = URL.cachesDirectory.appending(path: "Aniswift-title-names-v1.json")

    static func read() -> Self? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SnapshotWriter.write(data, to: Self.file)
    }

    static func remove() {
        SnapshotWriter.remove(file)
    }
}

struct ListCache: Codable {
    let account: Account
    let lists: [Kind: SavedList]

    private static var file: URL {
        URL.cachesDirectory.appending(path: "Aniswift-lists-v1.json")
    }

    static func read() -> Self? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SnapshotWriter.write(data, to: Self.file)
    }

    static func remove() {
        SnapshotWriter.remove(file)
    }
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

enum ProfileCache {
    private static let file = URL.cachesDirectory.appending(path: "Aniswift-profiles-v1.json")

    static func read() -> [String: ProfileSnapshot] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: ProfileSnapshot].self, from: data)) ?? [:]
    }

    static func write(_ profiles: [String: ProfileSnapshot]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        SnapshotWriter.write(data, to: file)
    }
}
