import Foundation

enum Kind: String, CaseIterable, Identifiable, Codable {
    case anime, manga
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var unit: String { self == .anime ? "Episodes" : "Chapters" }
    var statuses: [String] {
        [self == .anime ? "watching" : "reading", "completed", "on_hold", "dropped",
         self == .anime ? "plan_to_watch" : "plan_to_read"]
    }
    /// The media types MyAnimeList reports for this kind, as a list names them.
    /// The two kinds share none of them, so a manga list has its own set.
    var formats: [String] {
        switch self {
        case .anime: ["TV", "Movie", "OVA", "ONA", "Special", "Music", "TV Special"]
        case .manga: ["Manga", "Novel", "Light Novel", "One-shot", "Doujinshi", "Manhwa", "Manhua"]
        }
    }
}

func statusLabel(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}

// Tenrai and Jikan Edge use different keys for some of the same MAL fields.
struct Fields: Decodable {
    let values: KeyedDecodingContainer<Key>

    struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        values = try decoder.container(keyedBy: Key.self)
    }

    func read<T: Decodable>(_ names: String...) -> T? {
        for name in names {
            if let value = try? values.decode(T.self, forKey: Key(stringValue: name)) { return value }
        }
        return nil
    }

    func string(_ names: String...) -> String? {
        for name in names {
            if let value: String = read(name), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    var englishTitle: String? {
        let titles: [Fields]? = read("titles")
        let alternatives: Fields? = read("alternative_titles", "alternativeTitles")
        let localized: Fields? = read("title", "titles")
        return string("title_english", "titleEnglish", "englishTitle", "english_title")
            ?? alternatives?.string("en", "english")
            ?? localized?.string("en", "english")
            ?? titles?.first(where: { $0.string("type")?.lowercased() == "english" })?.string("title", "name")
    }

    var romajiTitle: String? {
        let titles: [Fields]? = read("titles")
        let localized: Fields? = read("title", "titles")
        return string("title_romaji", "titleRomaji", "romajiTitle", "romaji")
            ?? localized?.string("romaji")
            ?? titles?.first(where: { $0.string("type")?.lowercased() == "romaji" })?.string("title", "name")
            ?? string("title", "name")
            ?? titles?.first(where: { $0.string("type")?.lowercased() == "default" })?.string("title", "name")
    }

    /// The Japanese title: MyAnimeList's `title_japanese`, AniList's `native`,
    /// or the Jikan titles row of that type. A row that carries none has no
    /// Japanese name, and its page shows the name it does have.
    var japaneseTitle: String? {
        let titles: [Fields]? = read("titles")
        let localized: Fields? = read("title", "titles")
        return string("title_japanese", "titleJapanese", "japaneseTitle", "japanese_title")
            ?? localized?.string("native", "japanese")
            ?? titles?.first(where: {
                ["japanese", "native"].contains($0.string("type")?.lowercased() ?? "")
            })?.string("title", "name")
    }

    var includesEnglishTitleField: Bool {
        ["title_english", "titleEnglish", "englishTitle", "english_title", "alternative_titles", "alternativeTitles"]
            .contains { values.contains(Key(stringValue: $0)) }
    }

    var image: URL? {
        let images: Fields? = read("images")
        let jpg: Fields? = images?.read("jpg")
        let webp: Fields? = images?.read("webp")
        let large = jpg?.string("large_image_url") ?? webp?.string("large_image_url") ?? images?.string("large")
        let standard = jpg?.string("image_url") ?? webp?.string("image_url")
        let direct = string("imageUrl", "image", "avatarUrl", "avatar", "picture")
        let mainPicture: Fields? = read("main_picture")
        return publicURL(large ?? standard ?? mainPicture?.string("large", "medium") ?? direct)
    }
}

/// Freshness reported by Jikan Edge for public user data. The proxy answers
/// with `meta = {cached, stale, refreshFailed, fetchedAt}`.
struct CatalogFreshness: Equatable {
    var isStale = false
    var fetchedAt: Date?

    init(_ meta: Fields? = nil) {
        let stale: Bool? = meta?.read("stale")
        let refreshFailed: Bool? = meta?.read("refreshFailed")
        isStale = (stale ?? false) || (refreshFailed ?? false)
        if let raw = meta?.string("fetchedAt") {
            let date = activityDate(raw)
            fetchedAt = date == .distantPast ? nil : date
        }
    }
}

enum TitleLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case romaji = "Romaji"
    /// The name the title is known by in Japan: MyAnimeList's `title_japanese`.
    case japanese = "Japanese"

    var id: String { rawValue }
}

func publicURL(_ raw: String?) -> URL? {
    guard let raw, let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
    return url
}

struct Title: Identifiable, Hashable, Codable {
    let malID: Int
    let kind: Kind
    private(set) var name: String
    let original: String
    private(set) var image: URL?
    private var english: String?
    private var japanese: String?
    private var sparseTitle: Bool?
    var englishName: String? { english ?? (name == original ? nil : name) }
    var japaneseName: String? { japanese }

    /// The name a reader should see for the stored preferred-language setting.
    func displayName(for language: String) -> String {
        if language == TitleLanguage.japanese.rawValue {
            return japanese ?? (name.isEmpty ? original : name)
        }
        if language == TitleLanguage.romaji.rawValue {
            return original.isEmpty ? name : original
        }
        return name.isEmpty ? original : name
    }
    var needsTitleLookup: Bool { sparseTitle == true && englishName == nil }
    let score: Double?
    let format: String?
    let total: Int?
    let members: Int?
    let synopsis: String?
    let genres: [String]?
    let releaseYear: Int?
    let catalogStatus: String?
    /// The weekly slot a title that is still on the air takes, the date its
    /// first episode aired and whether it is on the air: together they say
    /// which episode comes next and whether the reader is caught up.
    let slot: AiringSlot?
    let premiere: Date?
    let isAiring: Bool
    var id: String { "\(kind.rawValue)-\(malID)" }
    var malURL: URL { URL(string: "https://myanimelist.net/\(kind.rawValue)/\(malID)")! }

    init?(_ fields: Fields, kind: Kind) {
        let english = fields.englishTitle
        guard let id: Int = fields.read("mal_id", "malId", "id"), id > 0,
              let original = fields.romajiTitle ?? english else { return nil }
        malID = id
        self.kind = kind
        self.original = original
        self.english = english
        japanese = fields.japaneseTitle
        name = english ?? original
        sparseTitle = !fields.includesEnglishTitleField
        image = fields.image
        score = fields.read("score", "mean")
        format = fields.string("type", "mediaType") ?? fields.string("media_type")?.uppercased()
        let count: Int? = fields.read("episodes", "chapters", "total", "num_episodes", "num_chapters")
        total = count.flatMap { $0 > 0 ? $0 : nil }
        members = fields.read("members")
        synopsis = fields.string("synopsis")
        let genreRows: [Fields]? = fields.read("genres")
        genres = (fields.read("genres") as [String]?) ?? genreRows?.compactMap { $0.string("name") }
        let dates: Fields? = fields.read(kind == .anime ? "aired" : "published")
        let parts: Fields? = dates?.read("prop")
        let start: Fields? = parts?.read("from")
        let dateYear = (dates?.string("from") ?? fields.string("start_date")).flatMap { Int($0.prefix(4)) }
        let year = (fields.read("year") as Int?) ?? (start?.read("year") as Int?) ?? dateYear
        releaseYear = year.flatMap { $0 > 0 ? $0 : nil }
        catalogStatus = fields.string("status")
        slot = AiringSlot(fields.read("broadcast"))
        let airing: Bool? = fields.read("airing")
        let status = (catalogStatus ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
        isAiring = airing == true || status == "currently airing"
        premiere = (dates?.string("from") ?? fields.string("start_date")).flatMap { raw -> Date? in
            let date = activityDate(raw)
            return date == .distantPast ? nil : date
        }
    }

    /// The next airing of this title, while it is still on the air.
    func nextAiring(schedule: AiringSchedule? = nil, after now: Date = .now) -> AiringProgress? {
        AiringProgress.next(
            slot: slot, premiere: premiere, total: total, isAiring: isAiring, schedule: schedule,
            after: now)
    }

    func fillingEnglishName(from cachedName: String?) -> Title {
        guard englishName == nil, let cachedName else { return self }
        var result = self
        result.english = cachedName
        result.name = cachedName
        return result
    }

    func fillingTitleAndImage(from other: Title?) -> Title {
        guard let other, id == other.id else { return self }
        var result = self
        if let preferred = englishName ?? other.englishName {
            result.english = preferred
            result.name = preferred
        }
        result.image = image ?? other.image
        return result
    }
}

struct ListDetails: Codable, Equatable {
    var repeatCount = 0
    var startDate = ""
    var finishDate = ""
    var notes = ""

    func changes(from original: Self) -> ListDetailPatch? {
        guard self != original else { return nil }
        return ListDetailPatch(
            repeatCount: repeatCount == original.repeatCount ? nil : repeatCount,
            startDate: startDate == original.startDate ? nil : startDate,
            finishDate: finishDate == original.finishDate ? nil : finishDate,
            notes: notes == original.notes ? nil : notes
        )
    }
}

struct ListDetailPatch: Encodable {
    let repeatCount: Int?
    let startDate: String?
    let finishDate: String?
    let notes: String?
}

struct ListEntry: Identifiable, Codable, Equatable {
    let title: Title
    let status: String
    let progress: Int
    let rating: Int
    let updated: String
    let details: ListDetails?
    /// Whether MyAnimeList holds the entry in a rewatch or reread: it keeps that
    /// as a watching or reading entry with a flag, so the status alone cannot
    /// tell the two apart.
    var isRestarting: Bool? = nil
    var id: String { title.id }

    init(_ fields: Fields, title: Title, fallback: ListChange? = nil, previous: ListEntry? = nil) {
        self.title = title
        status = fields.string("status") ?? fallback?.status ?? title.kind.statuses.last!
        progress = fields.read("num_episodes_watched", "num_chapters_read") ?? fallback?.progress ?? 0
        rating = fields.read("score") ?? fallback?.rating ?? 0
        updated = fields.string("updated_at") ?? Date().ISO8601Format()
        isRestarting = fields.read("is_rewatching", "is_rereading") ?? fallback?.restarts

        let prior = previous?.details ?? ListDetails()
        let count: Int? = fields.read("num_times_rewatched", "num_times_reread")
        let start: String? = fields.read("start_date")
        let finish: String? = fields.read("finish_date")
        let notes: String? = fields.read("comments")
        details = ListDetails(
            repeatCount: count ?? fallback?.details?.repeatCount ?? prior.repeatCount,
            startDate: start ?? fallback?.details?.startDate ?? prior.startDate,
            finishDate: finish ?? fallback?.details?.finishDate ?? prior.finishDate,
            notes: notes ?? fallback?.details?.notes ?? prior.notes
        )
    }
}

struct ListChange: Encodable {
    var status: String
    var progress: Int
    var rating: Int
    var details: ListDetailPatch? = nil
    /// Whether the change starts or ends a rewatch: `nil` leaves the flag as
    /// MyAnimeList holds it, which is what every other edit does.
    var restarts: Bool? = nil
}

struct CustomTitleList: Identifiable, Codable, Hashable {
    var id = UUID()
    let name: String
    var titles: [Title] = []
}

struct ListOrganization: Codable {
    var lists: [CustomTitleList] = []
    var hidden: Set<String> = []
}

struct Account: Codable, Equatable {
    let id: Int
    let name: String
    let image: URL?
}

struct Friend: Identifiable, Hashable, Codable {
    let name: String
    let avatar: URL?
    var id: String { name.lowercased() }

    init?(_ fields: Fields) {
        guard let name = fields.string("username", "name"),
              name.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil else { return nil }
        self.name = name
        avatar = fields.image
    }
}

struct FriendUpdate: Identifiable, Codable {
    let friend: Friend
    let title: Title
    let status: String?
    let score: Int?
    let progress: Int?
    let total: Int?
    let date: String?
    var id: String { friend.id + title.id }

    init(friend: Friend, title: Title, fields: Fields) {
        self.friend = friend
        self.title = title
        status = fields.string("status")
        score = fields.read("score")
        progress = fields.read("progress", "episodesWatched", "chaptersRead", "watchedEpisodes", "readChapters")
        total = fields.read("total") ?? title.total
        let rawDate = fields.string("updatedAt", "updated_at", "date")
        let parsedDate = activityDate(rawDate)
        date = parsedDate == .distantPast ? rawDate : parsedDate.formatted(.iso8601)
    }

    var activityPhrase: String {
        let status = status?.lowercased().replacingOccurrences(of: "_", with: " ")
        if status == "completed" { return "completed" }
        if status?.hasPrefix("plan to") == true { return "plans to \(title.kind == .anime ? "watch" : "read")" }
        if status == "dropped" { return "dropped" }
        if status == "on hold" { return "put on hold" }
        if let progress = progress, progress > 0 {
            let unit = title.kind == .anime ? "episode" : "chapter"
            return "\(title.kind == .anime ? "watched" : "read") through \(unit) \(progress) of"
        }
        return "updated"
    }

    var activityDescription: String {
        if let status, ["completed", "dropped", "on hold", "plan to watch", "plan to read"]
            .contains(status.lowercased().replacingOccurrences(of: "_", with: " ")) {
            return statusLabel(status)
        }
        if let progress, progress > 0 {
            let count = total.flatMap { $0 > 0 ? "\(progress) / \($0)" : nil } ?? "\(progress)"
            return "\(count) \(title.kind.unit.lowercased())"
        }
        return status.map(statusLabel) ?? "Updated \(title.kind.rawValue) list"
    }

    var activityDetails: String {
        [score.flatMap { $0 > 0 ? "\($0)/10" : nil }, date.map { displayDate($0) }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct TitleReview: Identifiable, Hashable {
    let id: String
    let url: URL?
    let author: String
    let avatar: URL?
    let date: String?
    let text: String
    let tag: String?
    let rating: Int?
    let spoiler: Bool

    var ratingLabel: String? {
        rating.flatMap { (1...10).contains($0) ? "\($0)/10" : nil }
    }

    var displayedDate: String? {
        let value = displayDate(date)
        return value.isEmpty ? nil : value
    }

    init?(_ fields: Fields) {
        // Tenrai serves Jikan's shape (`review`, `mal_id`, `user`), and the Jikan
        // Edge fallback serves its own (`reviewText`, `reviewId`, `username`):
        // reading only one of them dropped every review the fallback answered,
        // so a title page showed a Reviews section with nothing in it.
        guard let text = fields.string("review", "text", "reviewText") else { return nil }
        let user: Fields? = fields.read("user")
        let tags: [String] = fields.read("tags") ?? [fields.string("tag")].compactMap { $0 }
        self.text = text
        author =
            user?.string("username", "name") ?? fields.string("username", "user")
            ?? "MyAnimeList member"
        avatar = user?.image ?? fields.image
        date = fields.string("date")
        url = publicURL(fields.string("url"))
        let malID: Int? = fields.read("mal_id", "malId", "reviewId", "id")
        id = malID.map(String.init) ?? url?.absoluteString ?? "\(author)|\(date ?? "")|\(text)"
        tag = tags.first { ["Recommended", "Mixed Feelings", "Not Recommended"].contains($0) }
        rating = fields.read("score")
        spoiler =
            (fields.read("is_spoiler", "isSpoiler") ?? false)
            || tags.contains { $0.localizedCaseInsensitiveContains("spoiler") }
    }
}

/// A MyAnimeList interest stack: a curated group of titles. Tenrai serves the
/// stacks that contain a title at `/anime/{id}/stacks` and `/manga/{id}/stacks`,
/// and one stack with all of its entries at `/stacks/{id}`.
struct InterestStack: Identifiable, Hashable {
    let id: Int
    let kind: Kind
    let name: String
    let summary: String?
    let author: String
    let authorURL: URL?
    let url: URL?
    let restacks: Int
    let entryCount: Int
    let isOfficial: Bool
    let isChallenge: Bool
    let isSpoiler: Bool
    let created: Date?

    init?(_ fields: Fields) {
        guard let id: Int = fields.read("mal_id", "malId", "id"), id > 0,
              let name = fields.string("title", "name")
        else { return nil }
        self.id = id
        self.name = name
        kind = fields.string("stack_type", "stackType")?.lowercased() == "manga" ? .manga : .anime
        summary = fields.string("description", "synopsis")
        author = fields.string("author_username", "authorUsername", "username") ?? "MyAnimeList member"
        authorURL = publicURL(fields.string("author_url", "authorUrl"))
        url = publicURL(fields.string("url"))
        restacks = fields.read("restack_count", "restackCount") ?? 0
        entryCount = fields.read("entry_count", "entryCount") ?? 0
        isOfficial = fields.read("is_official", "isOfficial") ?? false
        isChallenge = fields.read("is_challenge", "isChallenge") ?? false
        isSpoiler = fields.read("is_spoiler", "isSpoiler") ?? false
        let rawCreated = fields.string("created_at", "createdAt")
        let parsed = activityDate(rawCreated)
        created = parsed == .distantPast ? nil : parsed
    }

    /// A stack a link named only by its id. The page it opens replaces this with
    /// the stack its response describes.
    init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
        name = "Interest Stack"
        summary = nil
        author = "MyAnimeList member"
        authorURL = nil
        url = nil
        restacks = 0
        entryCount = 0
        isOfficial = false
        isChallenge = false
        isSpoiler = false
        created = nil
    }
}

/// One title inside a stack, with the stack author's score and note for it.
struct StackEntry: Identifiable {
    let title: Title
    let position: Int
    let note: String?
    let score: Int?
    /// A stack can list the same title more than once, so the position is part
    /// of the row identity rather than the title alone.
    var id: String { "\(position)-\(title.id)" }

    init?(_ fields: Fields, kind: Kind) {
        guard let title = Title(fields, kind: kind) else { return nil }
        self.title = title
        position = fields.read("position") ?? 0
        note = fields.string("note")
        let rating: Double? = fields.read("author_score", "authorScore")
        score = rating.flatMap { (1...10).contains(Int($0)) ? Int($0) : nil }
    }
}

/// The stack a page returns: its header and its entries. The header is parsed
/// because its `stack_type` tells the entries how to decode, and because a page
/// opened from a link is pushed with an id alone and draws its header from here.
struct StackDetail {
    let stack: InterestStack
    let entries: [StackEntry]

    init?(_ response: Fields) {
        let row: Fields = response.read("data") ?? response
        guard let stack = InterestStack(row) else { return nil }
        self.stack = stack
        let rows: [Fields] = row.read("entries") ?? row.read("items") ?? []
        entries = rows.compactMap { StackEntry($0, kind: stack.kind) }
    }
}

/// A stack link inside prose. Interest stacks chain themselves with lines like
/// "Part 2: https://myanimelist.net/stacks/6746", so a description draws those
/// links as controls that open the stack they name instead of a web page.
enum StackLink {
    enum Segment: Hashable {
        case text(String)
        case stack(text: String, id: Int)
    }

    private static let pattern = #"https?://(?:www\.)?myanimelist\.net/stacks/(\d+)"#

    /// The stack a MyAnimeList URL names, when it names one.
    static func stackID(from url: URL) -> Int? {
        guard let host = url.host?.lowercased(),
              host == "myanimelist.net" || host == "www.myanimelist.net"
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0].lowercased() == "stacks", let id = Int(parts[1]), id > 0 else {
            return nil
        }
        return id
    }

    /// The text split so each stack link can be drawn as its own control.
    static func segments(in text: String) -> [Segment] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [.text(text)]
        }
        var segments: [Segment] = []
        var start = text.startIndex
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text),
                  let digits = Range(match.range(at: 1), in: text),
                  let id = Int(text[digits]), id > 0
            else { continue }
            if start < whole.lowerBound {
                segments.append(.text(String(text[start..<whole.lowerBound])))
            }
            segments.append(.stack(text: String(text[whole]), id: id))
            start = whole.upperBound
        }
        guard !segments.isEmpty else { return [.text(text)] }
        if start < text.endIndex {
            segments.append(.text(String(text[start...])))
        }
        return segments
    }
}

// Screens that used to be pushed with a destination closure get a value route
// instead: mixing the two navigation styles makes the next value-based push
// appear beneath the destination-pushed screen.
struct StackRoute: Hashable {
    let stack: InterestStack
}

/// The weekly slot an airing anime takes, as MyAnimeList publishes it: a
/// weekday and a time in Japan's zone, which is the one every slot is given
/// in. The title page turns the slot into the countdown it shows.
struct AiringSlot: Hashable, Codable {
    /// The weekday, numbered the way `Calendar` numbers it: 1 is Sunday.
    let weekday: Int
    let hour: Int
    let minute: Int

    private static let weekdays = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]
    private static let names = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    init?(_ broadcast: Fields?) {
        guard let broadcast, let day = broadcast.string("day"), let time = broadcast.string("time") else {
            return nil
        }
        // The payload names a day in the plural ("Sundays") and sometimes in
        // the singular, so the trailing s is the only difference to read past.
        let lowered = day.lowercased()
        let name = lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
        guard let weekday = Self.weekdays[name] else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            return nil
        }
        self.weekday = weekday
        hour = parts[0]
        minute = parts[1]
    }

    /// The slot as a reader sees it, e.g. "Sunday at 23:15 JST".
    var label: String {
        "\(Self.names[weekday - 1]) at \(String(format: "%02d:%02d", hour, minute)) JST"
    }

    /// When this slot next comes round after `now`. Japan has no daylight
    /// saving, so one fixed zone is exact for every title MyAnimeList lists.
    func next(after now: Date = .now) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }
}

/// What a title's airing says right now: when its next episode is due, which
/// one that is, and how many have aired. MyAnimeList publishes neither the
/// next episode nor an aired count, so both come from the weekly slot and the
/// premiere date — exact for a run without breaks, and silent about the
/// episode once a run outlasts the length it was announced with.
struct AiringProgress: Equatable {
    let date: Date
    /// The episode that airs at `date`, when it is known.
    let episode: Int?
    /// How many episodes have aired by now, when that is known.
    let aired: Int?

    /// The line a list row and a title page draw: "Episode 9 airs in 14
    /// hours", or "Next episode in 14 hours" when the episode is not known.
    func line(relativeTo now: Date = .now) -> String {
        let away = Self.relative.localizedString(for: date, relativeTo: now)
        guard let episode else { return "Next episode \(away)" }
        return "Episode \(episode) airs \(away)"
    }

    /// One formatter for every countdown: building one per row pass is the
    /// cost a relative date would pay.
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// When a title that is still on the air next airs, from the pieces a
    /// payload carries: its weekly slot, the date it started and the length it
    /// was announced with, or from the schedule AniList publishes for the run.
    static func next(
        slot: AiringSlot?, premiere: Date?, total: Int?, isAiring: Bool,
        schedule: AiringSchedule? = nil, after now: Date = .now
    ) -> AiringProgress? {
        // A published schedule is the run's own: it names the episode that is
        // really next and when it is really due, so a break in the middle of a
        // run no longer shifts every count after it. How many have aired is the
        // one before it.
        if isAiring, let schedule {
            return AiringProgress(date: schedule.date, episode: schedule.episode, aired: max(schedule.episode - 1, 0))
        }
        guard isAiring, let slot, let date = slot.next(after: now) else { return nil }
        guard let premiere else {
            return AiringProgress(date: date, episode: nil, aired: nil)
        }
        // One episode a week, from the first: the slot's place in the run is
        // how many have aired, and the one after it is next. The episode is
        // named only while the run fits the length it was announced with, so a
        // long run with breaks counts slots and says nothing rather than a
        // wrong number; how many aired is still known, and colours the row.
        let aired = max(Int((date.timeIntervalSince(premiere) / (7 * 24 * 60 * 60)).rounded()), 0)
        let episode = total.flatMap { aired + 1 <= $0 ? aired + 1 : nil }
        return AiringProgress(date: date, episode: episode, aired: aired)
    }
}

extension Fields {
    /// The next airing this payload describes, when the title it names is
    /// still on the air.
    func airingProgress(schedule: AiringSchedule? = nil, after now: Date = .now) -> AiringProgress? {
        let airing: Bool? = read("airing")
        let status = (string("status") ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
        let dates: Fields? = read("aired") ?? read("published")
        let premiere = (dates?.string("from") ?? string("start_date")).flatMap { raw -> Date? in
            let date = activityDate(raw)
            return date == .distantPast ? nil : date
        }
        let count: Int? = read("episodes", "num_episodes", "chapters", "num_chapters")
        return AiringProgress.next(
            slot: AiringSlot(read("broadcast")), premiere: premiere,
            total: count.flatMap { $0 > 0 ? $0 : nil },
            isAiring: airing == true || status == "currently airing", schedule: schedule, after: now)
    }
}

struct TitleStacksRoute: Hashable {
    let title: Title
    let stacks: [InterestStack]
    let more: Bool
}

struct TitleCollectionRoute: Hashable {
    let label: String
    let titles: [Title]
    var notes: [String: String] = [:]
    var showsScore = false
}

struct CharactersRoute: Hashable {
    let members: [CastMember]
}

struct TitleReviewsRoute: Hashable {
    let title: Title
    let reviews: [TitleReview]?
    let more: Bool
}

struct TitleReviewRoute: Hashable {
    let title: Title
    let review: TitleReview
}

struct FriendMediaRoute: Hashable {
    let friend: Friend
    let kind: Kind
}

struct CustomListsRoute: Hashable {}

struct CustomListRoute: Hashable {
    let list: CustomTitleList
}
