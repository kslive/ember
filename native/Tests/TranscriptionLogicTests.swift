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
