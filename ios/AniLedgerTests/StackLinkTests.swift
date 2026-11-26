import Foundation
import Testing

@testable import AniLedger

@Suite("Stack links")
struct StackLinkTests {
    private func url(_ value: String) throws -> URL {
        try #require(URL(string: value))
    }

    @Test("A stack URL names its stack")
    func readsStackID() throws {
        #expect(StackLink.stackID(from: try url("https://myanimelist.net/stacks/5329")) == 5329)
        #expect(StackLink.stackID(from: try url("https://www.myanimelist.net/stacks/5329/")) == 5329)
        #expect(StackLink.stackID(from: try url("http://myanimelist.net/stacks/6746")) == 6746)
    }

    @Test("Any other link is left alone")
    func rejectsOtherURLs() throws {
        #expect(StackLink.stackID(from: try url("https://myanimelist.net/anime/1")) == nil)
        #expect(StackLink.stackID(from: try url("https://myanimelist.net/stacks/")) == nil)
        #expect(StackLink.stackID(from: try url("https://myanimelist.net/stacks/abc")) == nil)
        #expect(StackLink.stackID(from: try url("https://example.com/stacks/5329")) == nil)
    }

    @Test("A description splits into text and stack links")
    func splitsSegments() {
        let segments = StackLink.segments(in: "Part 1: https://myanimelist.net/stacks/5329 and more")

        #expect(
            segments == [
                .text("Part 1: "),
                .stack(text: "https://myanimelist.net/stacks/5329", id: 5329),
                .text(" and more"),
            ])
    }

    @Test("A description without a stack link stays one run")
    func keepsPlainText() {
        #expect(StackLink.segments(in: "No links here.") == [.text("No links here.")])
        #expect(StackLink.segments(in: "") == [.text("")])
    }

    @Test("Several links keep their surrounding text in order")
    func keepsOrder() {
        let text = """
            Part 1: https://myanimelist.net/stacks/5329
            Part 2: https://myanimelist.net/stacks/6746
            """

        let segments = StackLink.segments(in: text)

        #expect(segments.count == 4)
        #expect(segments.first == .text("Part 1: "))
        #expect(segments[2] == .text("\nPart 2: "))
        #expect(segments.last == .stack(text: "https://myanimelist.net/stacks/6746", id: 6746))
    }
}
