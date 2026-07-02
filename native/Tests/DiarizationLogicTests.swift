@testable import Core
import XCTest

/// Pure diarization mapping + speaker labels (no FluidAudio SDK needed).
final class DiarizationLogicTests: XCTestCase {
    private func sys(_ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m", text: "x", startSeconds: start, endSeconds: end, source: .system)
    }

    func testAssignNumbersSpeakersByFirstAppearance() {
        let segs = [sys(0, 4), sys(6, 9)]
        let turns = [SpeakerTurn(rawId: "spk_x", start: 0, end: 5),
                     SpeakerTurn(rawId: "spk_y", start: 5.5, end: 10)]
        let out = DiarizationMap.assign(segs, turns: turns)
        XCTAssertEqual(out[0].speaker, 1)
        XCTAssertEqual(out[1].speaker, 2)
    }

    func testAssignSingleSpeakerStaysUnnumbered() {
        let out = DiarizationMap.assign([sys(0, 4)], turns: [SpeakerTurn(rawId: "only", start: 0, end: 5)])
        XCTAssertEqual(out[0].speaker, 0)
    }

    func testAssignLeavesMicUntouched() {
        let mic = TranscriptSegment(meetingId: "m", text: "me", startSeconds: 0, endSeconds: 4, source: .mic)
        let turns = [SpeakerTurn(rawId: "a", start: 0, end: 5), SpeakerTurn(rawId: "b", start: 5, end: 9)]
        let out = DiarizationMap.assign([mic], turns: turns)
        XCTAssertEqual(out[0].speaker, 0)
        XCTAssertEqual(out[0].source, .mic)
    }

    func testAssignNoOverlapStaysZero() {
        let turns = [SpeakerTurn(rawId: "a", start: 0, end: 5), SpeakerTurn(rawId: "b", start: 5, end: 9)]
        let out = DiarizationMap.assign([sys(20, 24)], turns: turns)
        XCTAssertEqual(out[0].speaker, 0)
    }

    func testAssignEmptyTurnsNoChange() {
        let out = DiarizationMap.assign([sys(0, 4)], turns: [])
        XCTAssertEqual(out[0].speaker, 0)
    }

    func testSpeakerLabel() {
        XCTAssertEqual(SpeakerLabel.text(source: .mic, speaker: 0, me: "Я", them: "Собеседник"), "Я")
        XCTAssertEqual(SpeakerLabel.text(source: .system, speaker: 0, me: "Я", them: "Собеседник"), "Собеседник")
        XCTAssertEqual(SpeakerLabel.text(source: .system, speaker: 2, me: "Я", them: "Собеседник"), "Собеседник 2")
        XCTAssertNil(SpeakerLabel.text(source: .unknown, speaker: 0, me: "Я", them: "Собеседник"))
    }

    func testSpeakerTag() {
        XCTAssertEqual(SpeakerLabel.tag(source: .mic, speaker: 0, meShort: "Я", themShort: "С"), "[Я]")
        XCTAssertEqual(SpeakerLabel.tag(source: .system, speaker: 0, meShort: "Я", themShort: "С"), "[С]")
        XCTAssertEqual(SpeakerLabel.tag(source: .system, speaker: 1, meShort: "Я", themShort: "С"), "[С1]")
        XCTAssertEqual(SpeakerLabel.tag(source: .system, speaker: 2, meShort: "Я", themShort: "С"), "[С2]")
        XCTAssertNil(SpeakerLabel.tag(source: .unknown, speaker: 0, meShort: "Я", themShort: "С"))
    }

    func testAssignDropsPhantomShortSpeaker() {
        let turns = [SpeakerTurn(rawId: "a", start: 0, end: 20),
                     SpeakerTurn(rawId: "b", start: 21, end: 40),
                     SpeakerTurn(rawId: "c", start: 40.5, end: 41.5)]
        let segs = [sys(0, 4), sys(22, 26), sys(40.6, 41.4)]
        let out = DiarizationMap.assign(segs, turns: turns)
        XCTAssertEqual(out[0].speaker, 1)
        XCTAssertEqual(out[1].speaker, 2)
        XCTAssertEqual(out[2].speaker, 0)
    }
}
