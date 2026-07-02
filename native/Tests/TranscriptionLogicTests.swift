import Core
@testable import TranscriptionService
import WhisperKit
import XCTest

/// Live/file transcription text cleaning — strips WhisperKit control tokens.
final class TranscriptionLogicTests: XCTestCase {
    func testStripsControlTokens() {
        XCTAssertEqual(TranscriptionService.cleanText("<|startoftranscript|>Привет<|0.00|>"), "Привет")
    }

    func testStripsMultipleTokensAndTrims() {
        XCTAssertEqual(TranscriptionService.cleanText("  <|ru|><|transcribe|> Привет мир <|endoftext|> "), "Привет мир")
    }

    func testOnlyTokensBecomesEmpty() {
        XCTAssertEqual(TranscriptionService.cleanText("<|nospeech|>"), "")
    }

    func testPlainTextUnchanged() {
        XCTAssertEqual(TranscriptionService.cleanText("обычный текст"), "обычный текст")
    }

    func testHallucinationsAreDetected() {
        XCTAssertTrue(TranscriptionService.isHallucination("[музыка]"))
        XCTAssertTrue(TranscriptionService.isHallucination("Музыка"))
        XCTAssertTrue(TranscriptionService.isHallucination("Редактор субтитров А.Семкин"))
        XCTAssertTrue(TranscriptionService.isHallucination("Продолжение следует..."))
        XCTAssertTrue(TranscriptionService.isHallucination("[Music]"))
        XCTAssertTrue(TranscriptionService.isHallucination("Подписывайтесь"))
    }

    func testRealSpeechIsNotHallucination() {
        XCTAssertFalse(TranscriptionService.isHallucination("давай обсудим бюджет на квартал"))
        XCTAssertFalse(TranscriptionService.isHallucination("мне нравится эта музыка в проекте"))
        XCTAssertFalse(TranscriptionService.isHallucination("Привет, как дела"))
    }

    func testHallucinationPrefixBoundary() {
        XCTAssertTrue(TranscriptionService.isHallucination("музыка слышна"))
        XCTAssertFalse(TranscriptionService.isHallucination("музыка для релаксации и хорошего настроения вечером"))
    }

    /// YouTube-credits hallucinations detected ANYWHERE in the segment — the phantom
    /// recording produced "Субтитры создавал DimaTorzok" which slipped past the
    /// prefix+18 window and even reached the summary.
    func testHallucinationSubstringMarkers() {
        XCTAssertTrue(TranscriptionService.isHallucination("Субтитры создавал DimaTorzok"))
        XCTAssertTrue(TranscriptionService.isHallucination("Субтитры сделал DimaTorzok"))
        XCTAssertTrue(TranscriptionService.isHallucination("Subtitles by the Amara.org community"))
        XCTAssertFalse(TranscriptionService.isHallucination("нужно поправить субтитры к ролику до пятницы обязательно"))
    }

    func testDecodeOptionsStrictSetsThresholds() {
        let options = TranscriptionService.decodeOptions(language: "ru", strict: true)
        XCTAssertTrue(options.skipSpecialTokens)
        XCTAssertEqual(options.language, "ru")
        XCTAssertEqual(options.noSpeechThreshold ?? 0, 0.6, accuracy: 0.0001)
        XCTAssertEqual(options.compressionRatioThreshold ?? 0, 2.4, accuracy: 0.0001)
    }

    func testDecodeOptionsLenientKeepsBasics() {
        let options = TranscriptionService.decodeOptions(language: nil, strict: false)
        XCTAssertTrue(options.skipSpecialTokens)
        XCTAssertNil(options.language)
    }

    private func seg(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m", text: text, startSeconds: start, endSeconds: end)
    }

    func testCollapseRepeatsDegenerateRun() {
        let run = (0 ..< 12).map { seg("и", Double($0), Double($0) + 0.5) }
        let out = TranscriptionService.collapseRepeats(run)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(out[0].endSeconds, 11.5, accuracy: 0.001)
    }

    func testCollapseRepeatsNormalizesCaseAndPunctuation() {
        let out = TranscriptionService.collapseRepeats([seg("И.", 0, 1), seg("и", 1, 2), seg(" и ", 2, 3)])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].endSeconds, 3, accuracy: 0.001)
    }

    func testCollapseRepeatsKeepsAlternatingAndNormalSpeech() {
        let alt = [seg("и", 0, 1), seg("да", 1, 2), seg("и", 2, 3)]
        XCTAssertEqual(TranscriptionService.collapseRepeats(alt).count, 3)
        let speech = [seg("привет как дела", 0, 2), seg("нормально а у тебя", 2, 4)]
        XCTAssertEqual(TranscriptionService.collapseRepeats(speech).count, 2)
        XCTAssertTrue(TranscriptionService.collapseRepeats([]).isEmpty)
        XCTAssertEqual(TranscriptionService.collapseRepeats([seg("одно", 0, 1)]).count, 1)
    }

    func testHasSpeechFiltersPunctuationOnly() {
        XCTAssertFalse(TranscriptionService.hasSpeech("-"))
        XCTAssertFalse(TranscriptionService.hasSpeech("—"))
        XCTAssertFalse(TranscriptionService.hasSpeech("..."))
        XCTAssertFalse(TranscriptionService.hasSpeech("   "))
        XCTAssertFalse(TranscriptionService.hasSpeech(""))
        XCTAssertTrue(TranscriptionService.hasSpeech("привет"))
        XCTAssertTrue(TranscriptionService.hasSpeech("АЗС 2025"))
        XCTAssertTrue(TranscriptionService.hasSpeech("- Выложи"))
    }
}
