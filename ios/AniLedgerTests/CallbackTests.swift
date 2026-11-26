import Foundation
import Testing

@testable import AniLedger

@Suite("MyAnimeList callback")
struct CallbackTests {
    private let state = "state-value"

    private func callback(_ query: String) -> URL? {
        URL(string: "org.aniledger.ios://oauth?\(query)")
    }

    @Test("A matching state and code are accepted")
    func acceptsValidCallback() throws {
        let url = try #require(callback("state=\(state)&code=abc"))
        #expect(MALCallback.code(from: url, state: state) == "abc")
    }

    @Test("A state this attempt did not generate is rejected")
    func rejectsWrongState() throws {
        let url = try #require(callback("state=other&code=abc"))
        #expect(MALCallback.code(from: url, state: state) == nil)
    }

    @Test("Missing, empty and repeated parameters are rejected")
    func rejectsMalformedParameters() throws {
        let missingCode = try #require(callback("state=\(state)"))
        #expect(MALCallback.code(from: missingCode, state: state) == nil)

        let emptyCode = try #require(callback("state=\(state)&code="))
        #expect(MALCallback.code(from: emptyCode, state: state) == nil)

        let repeatedState = try #require(callback("state=\(state)&state=\(state)&code=abc"))
        #expect(MALCallback.code(from: repeatedState, state: state) == nil)
    }

    @Test("A foreign host, scheme, path or fragment is rejected")
    func rejectsForeignCallback() throws {
        let wrongHost = try #require(URL(string: "org.aniledger.ios://elsewhere?state=\(state)&code=abc"))
        #expect(MALCallback.code(from: wrongHost, state: state) == nil)

        let wrongScheme = try #require(URL(string: "https://oauth?state=\(state)&code=abc"))
        #expect(MALCallback.code(from: wrongScheme, state: state) == nil)

        let withPath = try #require(URL(string: "org.aniledger.ios://oauth/extra?state=\(state)&code=abc"))
        #expect(MALCallback.code(from: withPath, state: state) == nil)

        let withFragment = try #require(URL(string: "org.aniledger.ios://oauth?state=\(state)&code=abc#next"))
        #expect(MALCallback.code(from: withFragment, state: state) == nil)
    }
}
