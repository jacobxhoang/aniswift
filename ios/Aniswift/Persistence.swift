import Darwin
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
    /// Whether the provider offered another page after this one. It is read as a
    /// flag, not a fact: a run of pages that stops moving the list clears it, so
    /// the list stops offering a page that would add nothing.
    var more: Bool
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

/// The schedules AniList has published, kept across launches so the airing rows of
/// a list draw “Episode 9 airs in 2 hours” on their first paint instead of a
/// blank line until the request answers. `askedAt` travels with them, so an entry
/// older than the cache's lifetime is asked for again while it is still shown.
struct AiringScheduleSnapshot: Codable {
    let schedules: [Int: AiringSchedule]
    let askedAt: [Int: Date]

    private static let file = URL.cachesDirectory.appending(path: "Aniswift-airing-schedules-v1.json")

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

struct CachedProfileValue<Value: Codable>: Codable {
    let value: Value
    let savedAt: Date

    var isFresh: Bool { Date.now.timeIntervalSince(savedAt) < 15 * 60 }
}

struct ProfileSnapshot: Codable {
    var stats: CachedProfileValue<ProfileStats>?
    var favorites: CachedProfileValue<[Kind: [Title]]>?
    var favoriteCharacters: CachedProfileValue<[CharacterReference]>?
    var favoritePeople: CachedProfileValue<[PersonReference]>?
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


/// One row a Home Screen widget draws: what the reader sees and the progress its
/// button adds to. No token and no account name travels in it.
struct WidgetRow: Codable, Identifiable {
    let id: String
    let malID: Int
    let kind: String
    let name: String
    let image: URL?
    let progress: Int
    let total: Int?
}

/// The account's totals as the statistics widget draws them: the counts the
/// public profile publishes, with a figure left out where the provider has none.
struct WidgetStats: Codable {
    let animeCount: Int?
    let mangaCount: Int?
    let daysWatched: Double?
    let chaptersRead: Int?
}

/// The App Group both bundles read the snapshot from. A group is an entitlement,
/// fixed when the bundle is signed rather than chosen by the app, so it is read
/// back from the signature: a build signed with a certificate that carries a
/// group of its own uses that one, and none of that certificate is written into
/// the project. The list below is only the fallback for a signature that cannot
/// be read.
enum AppGroup {
    /// The app's own group, and any a certificate that signs a build carries,
    /// added here for a signature that cannot be read back.
    static let known = ["group.org.aniswift.ios.shared"]

    /// The group in use: the first of the signature's groups that opens, and the
    /// known list only when the signature gave none.
    static let identifier: String? = {
        let granted = signatureGroups()
        let candidates = granted.isEmpty ? known : granted + known
        return candidates.first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()

    /// The groups the signature carries, whether or not any of them opens: what
    /// About reads back when a widget still draws nothing.
    static var signature: [String] { signatureGroups() }

    /// The App Groups the code signature carries, read through Security's own
    /// task API. The symbols are looked up at runtime rather than linked, so a
    /// system without them falls back to `known` instead of failing to launch.
    private static func signatureGroups() -> [String] {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)
        else { return [] }
        defer { dlclose(handle) }
        guard let create = dlsym(handle, "SecTaskCreateFromSelf"),
            let copy = dlsym(handle, "SecTaskCopyValueForEntitlement")
        else { return [] }

        // The two CF values are handed to Swift, which releases them: CFRelease
        // is unavailable here because Core Foundation is memory managed.
        typealias CreateTask = @convention(c) (UnsafeRawPointer?) -> AnyObject?
        typealias CopyEntitlement =
            @convention(c) (AnyObject?, CFString, UnsafeMutableRawPointer?) -> AnyObject?

        guard let task = unsafeBitCast(create, to: CreateTask.self)(nil) else { return [] }
        let lookUp = unsafeBitCast(copy, to: CopyEntitlement.self)
        guard let value = lookUp(task, "com.apple.security.application-groups" as CFString, nil)
        else { return [] }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

/// The rows the widgets draw, written after every list read or edit into the App
/// Group container the app and its extension share. Each kind keeps its three
/// most recently updated entries, which is all a widget draws.
struct WidgetSnapshot: Codable {
    var anime: [WidgetRow] = []
    var manga: [WidgetRow] = []
    /// The account's totals, once its public profile has been read.
    var stats: WidgetStats?

    private static let name = "Aniswift-widget-v1.json"

    /// The container both bundles write to, when the signature grants a group.
    static var container: URL? {
        guard let group = AppGroup.identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static var file: URL? {
        container?.appending(path: name)
    }

    static func read() -> Self? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() {
        guard let file = Self.file, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// The access token a widget's button needs to reach MyAnimeList. The Keychain
/// stays the app's one copy: an extension cannot read that item without a
/// keychain access group whose name is only resolved at signing, so this one
/// lives in the App Group container, protected until the device is first
/// unlocked, and is removed when the account signs out.
struct WidgetCredentials: Codable {
    let accessToken: String
    let expiresAt: Date

    private static let name = "Aniswift-widget-token.json"

    private static var file: URL? {
        WidgetSnapshot.container?.appending(path: name)
    }

    static func write(token: String, expiresAt: Date) {
        guard let file = Self.file,
            let data = try? JSONEncoder().encode(Self(accessToken: token, expiresAt: expiresAt))
        else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove() {
        guard let file = Self.file else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
