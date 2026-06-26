@testable import Core
import XCTest

/// Time/duration formatting and sidebar date grouping.
final class FormatTests: XCTestCase {
    func testTimecode() {
        XCTAssertEqual(Format.timecode(0), "00:00")
        XCTAssertEqual(Format.timecode(65), "01:05")
        XCTAssertEqual(Format.timecode(-5), "00:00")
        XCTAssertEqual(Format.timecode(3599), "59:59")
    }

    func testDurationMinutes() {
        XCTAssertEqual(Format.duration(32 * 60, language: .ru), "32 мин")
        XCTAssertEqual(Format.duration(32 * 60, language: .en), "32 min")
    }

    func testDurationHours() {
        XCTAssertEqual(Format.duration(3900, language: .en), "1 h 05 min")
        XCTAssertEqual(Format.duration(3900, language: .ru), "1 ч 05 мин")
    }

    func testClock() throws {
        var c = DateComponents(); c.year = 2026; c.month = 1; c.day = 2; c.hour = 9; c.minute = 7
        let d = try XCTUnwrap(Calendar.current.date(from: c))
        XCTAssertEqual(Format.clock(d, language: .ru), "09:07")
    }

    func testDateGroupToday() {
        XCTAssertEqual(DateGroup.of(Date()), .today)
    }

    func testDateGroupYesterday() throws {
        let y = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        XCTAssertEqual(DateGroup.of(y), .yesterday)
    }

    func testDateGroupOlderIsDay() throws {
        let old = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -10, to: Date()))
        if case .day = DateGroup.of(old) { } else { XCTFail("expected .day for a 10-day-old date") }
    }

    func testDurationChinese() {
        XCTAssertTrue(Format.duration(32 * 60, language: .zh).contains("分钟"))
        XCTAssertTrue(Format.duration(3900, language: .zh).contains("小时"))
    }

    func testDurationSubMinuteSeconds() {
        XCTAssertEqual(Format.duration(30, language: .en), "30 sec")
        XCTAssertEqual(Format.duration(30, language: .ru), "30 сек")
        XCTAssertTrue(Format.duration(30, language: .zh).contains("秒"))
    }

    func testTimecodeRoundsAndNoHourWrap() {
        XCTAssertEqual(Format.timecode(65.7), "01:06")
        XCTAssertEqual(Format.timecode(3661), "61:01")
    }
}
