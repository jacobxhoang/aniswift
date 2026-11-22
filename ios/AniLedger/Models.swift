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
    private var sparseTitle: Bool?
    var englishName: String? { english ?? (name == original ? nil : name) }
    var needsTitleLookup: Bool { sparseTitle == true && englishName == nil }
    let score: Double?
    let format: String?
    let total: Int?
    let members: Int?
    let synopsis: String?
    let genres: [String]?
    let releaseYear: Int?
    let catalogStatus: String?
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
    var id: String { title.id }

    init(_ fields: Fields, title: Title, fallback: ListChange? = nil, previous: ListEntry? = nil) {
        self.title = title
        status = fields.string("status") ?? fallback?.status ?? title.kind.statuses.last!
        progress = fields.read("num_episodes_watched", "num_chapters_read") ?? fallback?.progress ?? 0
        rating = fields.read("score") ?? fallback?.rating ?? 0
        updated = fields.string("updated_at") ?? Date().ISO8601Format()

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
}

struct CustomTitleList: Identifiable, Codable {
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

struct TitleReview: Identifiable {
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
        guard let text = fields.string("review", "text") else { return nil }
        let user: Fields? = fields.read("user")
        let tags: [String] = fields.read("tags") ?? [fields.string("tag")].compactMap { $0 }
        self.text = text
        author = user?.string("username", "name") ?? fields.string("user", "username") ?? "MyAnimeList member"
        avatar = user?.image ?? fields.image
        date = fields.string("date")
        url = publicURL(fields.string("url"))
        let malID: Int? = fields.read("mal_id", "malId", "id")
        id = malID.map(String.init) ?? url?.absoluteString ?? "\(author)|\(date ?? "")|\(text)"
        tag = tags.first { ["Recommended", "Mixed Feelings", "Not Recommended"].contains($0) }
        rating = fields.read("score")
        spoiler = (fields.read("is_spoiler", "isSpoiler") ?? false) || tags.contains { $0.localizedCaseInsensitiveContains("spoiler") }
    }
}
