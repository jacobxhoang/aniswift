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
        return publicURL(large ?? standard ?? direct)
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
        format = fields.string("type", "mediaType", "media_type")
        total = fields.read("episodes", "chapters", "total")
        members = fields.read("members")
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

struct ListEntry: Identifiable, Codable, Equatable {
    let title: Title
    let status: String
    let progress: Int
    let rating: Int
    let updated: String
    var id: String { title.id }

    init(title: Title, change: ListChange) {
        self.title = title
        status = change.status
        progress = change.progress
        rating = change.rating
        updated = Date().ISO8601Format()
    }

    init?(_ fields: Fields, kind: Kind) {
        guard let title = Title(fields, kind: kind) else { return nil }
        self.title = title
        status = fields.string("status") ?? kind.statuses.last!
        progress = fields.read("progress") ?? 0
        rating = fields.read("rating") ?? 0
        updated = fields.string("updated") ?? ""
    }
}

struct ListChange: Encodable {
    var status: String
    var progress: Int
    var rating: Int
}

struct Account: Codable, Equatable {
    let id: Int
    let name: String
    let image: URL?
}

struct Friend: Identifiable {
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

struct FriendUpdate: Identifiable {
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
        date = fields.string("updatedAt", "date")
    }
}

struct TitleReview: Identifiable {
    let id = UUID()
    let author: String
    let avatar: URL?
    let date: String?
    let text: String
    let tag: String?
    let rating: Int?
    let spoiler: Bool

    init?(_ fields: Fields) {
        guard let text = fields.string("review", "text") else { return nil }
        let user: Fields? = fields.read("user")
        let tags: [String] = fields.read("tags") ?? [fields.string("tag")].compactMap { $0 }
        self.text = text
        author = user?.string("username", "name") ?? fields.string("user", "username") ?? "MyAnimeList member"
        avatar = user?.image ?? fields.image
        date = fields.string("date")
        tag = tags.first { ["Recommended", "Mixed Feelings", "Not Recommended"].contains($0) }
        rating = fields.read("score")
        spoiler = (fields.read("is_spoiler", "isSpoiler") ?? false) || tags.contains { $0.localizedCaseInsensitiveContains("spoiler") }
    }
}
