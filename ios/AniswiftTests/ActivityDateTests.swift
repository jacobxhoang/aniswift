import Foundation
import Testing

@testable import Aniswift

@Suite("Activity dates")
struct ActivityDateTests {
    @Test("ISO 8601 with and without fractional seconds")
    func iso8601() {
        #expect(activityDate("2026-11-25T10:30:00Z") != .distantPast)
        #expect(activityDate("2026-11-25T10:30:00.250Z") != .distantPast)
        #expect(activityDate("2026-11-25T10:30:00Z").formatted(.iso8601.year()) == "2026")
    }

    @Test("Plain calendar dates")
    func calendarDates() {
        #expect(activityDate("2026-11-25") != .distantPast)
        #expect(activityDate("Nov 25, 2026") != .distantPast)
        #expect(activityDate("Nov 25, 10:30 AM") != .distantPast)
    }

    @Test("Relative words resolve around now")
    func relativeWords() {
        let now = Date()
        #expect(abs(activityDate("today").timeIntervalSince(now)) < 60)
        let yesterday = activityDate("yesterday")
        #expect(yesterday < now)
        #expect(now.timeIntervalSince(yesterday) < 60 * 60 * 36)
    }

    @Test("A month and day after today is read as last year")
    func futureRollback() {
        let ahead = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let parsed = activityDate(formatter.string(from: ahead))
        #expect(parsed != .distantPast)
        #expect(parsed < Date())
    }

    @Test("Unknown and missing values are distant past")
    func unknown() {
        #expect(activityDate("last Tuesday-ish") == .distantPast)
        #expect(activityDate(nil) == .distantPast)
    }
}
