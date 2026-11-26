import Foundation
import Testing

@testable import AniLedger

@Suite("Title parsing")
struct TitleTests {
    private func title(_ json: String, kind: Kind = .anime) throws -> Title {
        let fields = try JSONDecoder().decode(Fields.self, from: Data(json.utf8))
        return try #require(Title(fields, kind: kind))
    }

    @Test("A detail payload keeps its English title and needs no lookup")
    func detailPayload() throws {
        let value = try title(
            #"{"mal_id": 1, "title": "Cowboy Bebop", "title_english": "Cowboy Bebop", "episodes": 26, "score": 8.75}"#
        )
        #expect(value.id == "anime-1")
        #expect(value.name == "Cowboy Bebop")
        #expect(value.englishName == "Cowboy Bebop")
        #expect(value.needsTitleLookup == false)
        #expect(value.total == 26)
        #expect(value.score == 8.75)
    }

    @Test("Alternative titles supply the English name")
    func alternativeTitles() throws {
        let value = try title(
            #"{"mal_id": 3, "title": "Shingeki no Kyojin", "alternative_titles": {"en": "Attack on Titan"}}"#
        )
        #expect(value.name == "Attack on Titan")
        #expect(value.englishName == "Attack on Titan")
        #expect(value.needsTitleLookup == false)
    }

    @Test("A Jikan list row is sparse until its English title is resolved")
    func sparseRow() throws {
        let value = try title(
            #"{"malId": 44347, "title": "One Punch-Man", "imageUrl": "https://cdn.myanimelist.net/images/manga/3/243930.jpg"}"#
        )
        #expect(value.id == "anime-44347")
        #expect(value.name == "One Punch-Man")
        #expect(value.englishName == nil)
        #expect(value.needsTitleLookup)
        #expect(value.image != nil)
    }

    @Test("Filling an English name clears the lookup and renames the row")
    func fillEnglishName() throws {
        let row = try title(#"{"malId": 44347, "title": "One Punch-Man"}"#)
        let filled = row.fillingEnglishName(from: "One-Punch Man")
        #expect(filled.name == "One-Punch Man")
        #expect(filled.englishName == "One-Punch Man")
        #expect(filled.needsTitleLookup == false)
    }

    @Test("Manga rows read chapters and the publishing year")
    func manga() throws {
        let value = try title(
            #"{"mal_id": 2, "title": "Berserk", "chapters": 374, "published": {"prop": {"from": {"year": 1989}}}}"#,
            kind: .manga
        )
        #expect(value.kind == .manga)
        #expect(value.total == 374)
        #expect(value.releaseYear == 1989)
    }

    @Test("A payload without an id is rejected")
    func missingID() throws {
        let missing = try JSONDecoder().decode(Fields.self, from: Data(#"{"title": "Cowboy Bebop"}"#.utf8))
        #expect(Title(missing, kind: .anime) == nil)

        let zero = try JSONDecoder().decode(Fields.self, from: Data(#"{"mal_id": 0, "title": "Cowboy Bebop"}"#.utf8))
        #expect(Title(zero, kind: .anime) == nil)
    }
}
