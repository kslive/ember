import Core
import XCTest

/// Pure event-picking logic behind "meeting titles from Apple Calendar".
final class CalendarTitlesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func cand(_ title: String, startOffset: TimeInterval, endOffset: TimeInterval,
                      allDay: Bool = false) -> CalendarTitles.Candidate {
        CalendarTitles.Candidate(title: title, start: now.addingTimeInterval(startOffset),
                                 end: now.addingTimeInterval(endOffset), isAllDay: allDay)
    }

    func testOngoingEventWins() {
        XCTAssertEqual(CalendarTitles.pick(from: [cand("Daily sync", startOffset: -600, endOffset: 1200)], at: now),
                       "Daily sync")
    }

    func testUpcomingWithinToleranceCounts() {
        XCTAssertEqual(CalendarTitles.pick(from: [cand("Планёрка", startOffset: 120, endOffset: 3600)], at: now),
                       "Планёрка")
    }

    func testUpcomingBeyondToleranceIgnored() {
        XCTAssertNil(CalendarTitles.pick(from: [cand("Later", startOffset: 600, endOffset: 3600)], at: now))
    }

    func testFinishedEventIgnored() {
        XCTAssertNil(CalendarTitles.pick(from: [cand("Done", startOffset: -3600, endOffset: -300)], at: now))
    }

    func testAllDayAndUntitledSkipped() {
        let list = [cand("Birthday", startOffset: -10000, endOffset: 10000, allDay: true),
                    cand("   ", startOffset: -600, endOffset: 600)]
        XCTAssertNil(CalendarTitles.pick(from: list, at: now))
    }

    func testLatestStartWinsAmongOverlapping() {
        let list = [cand("Long planning", startOffset: -3000, endOffset: 3000),
                    cand("1:1 с Димой", startOffset: 60, endOffset: 1800)]
        XCTAssertEqual(CalendarTitles.pick(from: list, at: now), "1:1 с Димой")
    }

    func testTitleTrimmed() {
        XCTAssertEqual(CalendarTitles.pick(from: [cand("  Sync  ", startOffset: -60, endOffset: 600)], at: now),
                       "Sync")
    }

    func testEmptyListNil() {
        XCTAssertNil(CalendarTitles.pick(from: [], at: now))
    }
}
