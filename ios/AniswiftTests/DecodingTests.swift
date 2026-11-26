import Foundation
import Testing

@testable import Aniswift

@Suite("Fields decoding")
struct DecodingTests {
    private func fields(_ json: String) throws -> Fields {
        try JSONDecoder().decode(Fields.self, from: Data(json.utf8))
    }

    @Test("Both key spellings decode from the same payload")
    func keyAliases() throws {
        let payload = try fields(#"{"mal_id": 5114, "malId": 99}"#)
        let snake: Int? = payload.read("mal_id")
        let camel: Int? = payload.read("malId")
        #expect(snake == 5114)
        #expect(camel == 99)
    }

    @Test("A value of the wrong type falls through to the next name")
    func wrongTypeFallsThrough() throws {
        let payload = try fields(#"{"mal_id": "5114", "id": 5114}"#)
        let id: Int? = payload.read("mal_id", "id")
        #expect(id == 5114)
    }

    @Test("Blank strings are skipped")
    func blankStrings() throws {
        let payload = try fields(#"{"title": "   ", "name": "Cowboy Bebop"}"#)
        #expect(payload.string("title", "name") == "Cowboy Bebop")
    }

    @Test("Images prefer the large URL and reject insecure hosts")
    func images() throws {
        let jikan = try fields(
            #"{"images": {"jpg": {"image_url": "https://cdn.myanimelist.net/images/anime/4/19644.jpg", "large_image_url": "https://cdn.myanimelist.net/images/anime/4/19644l.jpg"}}}"#
        )
        #expect(jikan.image?.lastPathComponent == "19644l.jpg")

        let camel = try fields(#"{"imageUrl": "https://cdn.myanimelist.net/images/anime/4/19644.jpg"}"#)
        #expect(camel.image != nil)

        let insecure = try fields(#"{"imageUrl": "http://example.com/a.jpg"}"#)
        #expect(insecure.image == nil)
    }
}
