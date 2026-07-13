@testable import Core
import XCTest

/// Extraction of the app-language section from trilingual GitHub release notes
/// (drives the one-time "What's new" announcement after an update).
final class ReleaseNotesTests: XCTestCase {
    private let body = """
    ## 🇬🇧 English — Ember 1.5.0 — DeepSeek cloud summaries

    - **NEW: optional DeepSeek API key** for summaries.
    - **NEW: narrative summaries.**

    ## 🇷🇺 Русский — Ember 1.5.0 — Саммари через DeepSeek

    - **НОВОЕ: опциональный ключ DeepSeek API** для саммари.
    - **НОВОЕ: повествовательные саммари.**

    ## 🇨🇳 中文 — Ember 1.5.0 — DeepSeek 云端摘要

    - **新功能：可选的 DeepSeek API 密钥**。

    ---
    Requires macOS 14.4+ (Apple Silicon). Ad-hoc signed.

    SHA256: abc123
    """

    func testExtractsRussianSection() {
        let s = ReleaseNotes.localizedSection(body, language: .ru)
        XCTAssertTrue(s.contains("повествовательные саммари"))
        XCTAssertFalse(s.contains("NEW: optional DeepSeek"))
        XCTAssertFalse(s.contains("新功能"))
        XCTAssertFalse(s.contains("SHA256"))
        XCTAssertFalse(s.contains("Requires macOS"))
    }

    func testExtractsEnglishSection() {
        let s = ReleaseNotes.localizedSection(body, language: .en)
        XCTAssertTrue(s.contains("narrative summaries"))
        XCTAssertFalse(s.contains("НОВОЕ"))
    }

    func testExtractsChineseSection() {
        let s = ReleaseNotes.localizedSection(body, language: .zh)
        XCTAssertTrue(s.contains("新功能"))
        XCTAssertFalse(s.contains("narrative"))
    }

    func testFallsBackToWholeBodyWithoutLanguageSections() {
        let plain = "Just some notes\n\n- one fix\n\n---\nSHA256: def"
        let s = ReleaseNotes.localizedSection(plain, language: .ru)
        XCTAssertTrue(s.contains("one fix"))
        XCTAssertFalse(s.contains("SHA256"))
    }

    func testStripFooterWithoutSeparatorKeepsAll() {
        XCTAssertEqual(ReleaseNotes.stripFooter("  hello\nworld  "), "hello\nworld")
    }
}
