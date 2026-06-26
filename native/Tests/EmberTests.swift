@testable import Core
@testable import PersistenceService
@testable import SummaryService
import XCTest

final class EmberTests: XCTestCase {
    func testTimecode() {
        XCTAssertEqual(Format.timecode(0), "00:00")
        XCTAssertEqual(Format.timecode(9), "00:09")
        XCTAssertEqual(Format.timecode(75), "01:15")
        XCTAssertEqual(Format.timecode(3599), "59:59")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(0, language: .en), "0 min")
        XCTAssertEqual(Format.duration(1920, language: .en), "32 min")
        XCTAssertEqual(Format.duration(1920, language: .ru), "32 мин")
        XCTAssertTrue(Format.duration(3720, language: .en).contains("h"))
    }

    func testAudioLevel() {
        XCTAssertEqual(AudioLevel.rms([]), 0)
        XCTAssertEqual(AudioLevel.rms([0, 0, 0]), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevel.rms([0.5, 0.5, 0.5]), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AudioLevel.meter(0), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevel.meter(0.04), 0.6, accuracy: 0.0001)
        XCTAssertEqual(AudioLevel.meter(0.25), 1, accuracy: 0.0001)
    }

    func testDateGroup() throws {
        let cal = Calendar.current
        XCTAssertEqual(DateGroup.of(Date()), .today)
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: Date()))
        XCTAssertEqual(DateGroup.of(yesterday), .yesterday)
        let old = try XCTUnwrap(cal.date(byAdding: .day, value: -10, to: Date()))
        if case .day = DateGroup.of(old) {} else { XCTFail("expected .day") }
    }

    func testCatalogs() {
        XCTAssertNotNil(SummaryCatalog.spec(for: SummaryCatalog.defaultId))
        XCTAssertEqual(SummaryCatalog.all.count, 3)
        XCTAssertTrue(SummaryCatalog.all.contains { $0.badge == .recommended })
        XCTAssertNotNil(TranscriptionCatalog.all.first { $0.id == TranscriptionCatalog.defaultId })
    }

    func testLocalizationCompleteness() {
        let en = Set(LocalizedStrings.en.keys)
        for lang in [LocalizedStrings.ru, LocalizedStrings.zh] {
            let missing = en.subtracting(Set(lang.keys))
            XCTAssertTrue(missing.isEmpty, "Missing translations: \(missing.sorted())")
        }
    }

    @MainActor
    func testMeetingStore() {
        let store = MeetingStore(inMemory: true)
        XCTAssertTrue(store.meetings.isEmpty)

        let m = Meeting(title: "Test meeting", durationSeconds: 120)
        store.upsert(m)
        XCTAssertEqual(store.meetings.count, 1)
        XCTAssertEqual(store.meetings.first?.title, "Test meeting")

        store.rename(m.id, title: "Renamed")
        XCTAssertEqual(store.meetings.first?.title, "Renamed")

        let segs = [
            TranscriptSegment(meetingId: m.id, text: "hello", startSeconds: 0, endSeconds: 1),
            TranscriptSegment(meetingId: m.id, text: "world", startSeconds: 1, endSeconds: 2)
        ]
        store.saveTranscript(meetingId: m.id, segments: segs)
        XCTAssertEqual(store.transcript(meetingId: m.id).count, 2)
        XCTAssertEqual(store.transcript(meetingId: m.id).first?.text, "hello")

        let summary = MeetingSummary(tldr: "tl", decisions: ["d1"], tasks: [SummaryTask(text: "t1", assignee: "Sam")], markdown: "# Summary")
        store.saveSummary(meetingId: m.id, summary: summary)
        let loaded = store.summary(meetingId: m.id)
        XCTAssertEqual(loaded?.markdown, "# Summary")
        XCTAssertEqual(loaded?.tasks.first?.assignee, "Sam")

        store.delete(m.id)
        XCTAssertTrue(store.meetings.isEmpty)
        XCTAssertTrue(store.transcript(meetingId: m.id).isEmpty)
        XCTAssertNil(store.summary(meetingId: m.id))
    }

    @MainActor
    func testMeetingStoreSourceRoundTrip() {
        let store = MeetingStore(inMemory: true)
        let m = Meeting(title: "M", durationSeconds: 2)
        store.upsert(m)
        store.saveTranscript(meetingId: m.id, segments: [
            TranscriptSegment(meetingId: m.id, text: "mine", startSeconds: 0, endSeconds: 1, source: .mic),
            TranscriptSegment(meetingId: m.id, text: "theirs", startSeconds: 1, endSeconds: 2, source: .system)
        ])
        let loaded = store.transcript(meetingId: m.id)
        XCTAssertEqual(loaded.first { $0.text == "mine" }?.source, .mic)
        XCTAssertEqual(loaded.first { $0.text == "theirs" }?.source, .system)
    }

    @MainActor
    func testMeetingStoreOrdersNewestFirst() {
        let store = MeetingStore(inMemory: true)
        store.upsert(Meeting(title: "old", createdAt: Date(timeIntervalSince1970: 1000)))
        store.upsert(Meeting(title: "new", createdAt: Date(timeIntervalSince1970: 2000)))
        XCTAssertEqual(store.meetings.first?.title, "new")
        XCTAssertEqual(store.meetings.last?.title, "old")
    }

    func testAudioLevelNegativeSamples() {
        XCTAssertEqual(AudioLevel.rms([-0.5, -0.5]), 0.5, accuracy: 0.0001)
    }
}
