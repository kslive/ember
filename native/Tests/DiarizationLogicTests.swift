@testable import Core
import XCTest

/// Channel-based speaker labels (mic → "Я"/"[Я]", system → "Собеседник"/"[С]").
/// No ML speaker diarization — the AI infers distinct participants from content.
final class DiarizationLogicTests: XCTestCase {
    func testSpeakerLabelText() {
        XCTAssertEqual(SpeakerLabel.text(source: .mic, me: "Я", them: "Собеседник"), "Я")
        XCTAssertEqual(SpeakerLabel.text(source: .system, me: "Я", them: "Собеседник"), "Собеседник")
        XCTAssertNil(SpeakerLabel.text(source: .unknown, me: "Я", them: "Собеседник"))
    }

    func testSpeakerTag() {
        XCTAssertEqual(SpeakerLabel.tag(source: .mic, meShort: "Я", themShort: "С"), "[Я]")
        XCTAssertEqual(SpeakerLabel.tag(source: .system, meShort: "Я", themShort: "С"), "[С]")
        XCTAssertNil(SpeakerLabel.tag(source: .unknown, meShort: "Я", themShort: "С"))
    }
}
