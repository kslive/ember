@testable import Core
import XCTest

/// Custom summary templates: YAML-header parsing, `{{LANGUAGE}}` substitution,
/// language naming (only ru/en/zh exist) and filename → id slugging. Pure logic —
/// no filesystem side effects.
final class SummaryTemplatesTests: XCTestCase {
    func testParseHeader() {
        let content = """
        ---
        name: My Template
        description: A short note
        ---

        Body line one.
        Body line two.
        """
        let parsed = SummaryTemplates.parse(content, fallbackName: "fallback")
        XCTAssertEqual(parsed.name, "My Template")
        XCTAssertEqual(parsed.description, "A short note")
        XCTAssertEqual(parsed.body, "Body line one.\nBody line two.")
    }

    func testParseNoHeaderFallsBackToFilename() {
        let parsed = SummaryTemplates.parse("Just a body, no header.", fallbackName: "notes")
        XCTAssertEqual(parsed.name, "notes")
        XCTAssertEqual(parsed.description, "")
        XCTAssertEqual(parsed.body, "Just a body, no header.")
    }

    func testFileContentRoundTrips() {
        let file = SummaryTemplates.fileContent(name: "Round", description: "trip", body: "Hello {{LANGUAGE}}.")
        let parsed = SummaryTemplates.parse(file, fallbackName: "x")
        XCTAssertEqual(parsed.name, "Round")
        XCTAssertEqual(parsed.description, "trip")
        XCTAssertEqual(parsed.body, "Hello {{LANGUAGE}}.")
    }

    /// The token is filled with the transcript's language; nothing else is appended.
    func testLanguageSubstitution() {
        let body = "Write in {{LANGUAGE}} only."
        XCTAssertEqual(
            body.replacingOccurrences(of: SummaryTemplates.placeholder, with: SummaryTemplates.languageName("ru")),
            "Write in Russian only."
        )
    }

    func testLanguageNameThreeLanguages() {
        XCTAssertEqual(SummaryTemplates.languageName("ru"), "Russian")
        XCTAssertEqual(SummaryTemplates.languageName("zh"), "Chinese")
        XCTAssertEqual(SummaryTemplates.languageName("en"), "English")
        XCTAssertEqual(SummaryTemplates.languageName("xx"), "English")
    }

    /// 8 built-ins (Standard + 7), each with a native ru/en/zh variant: unique
    /// filenames, non-empty name/description/body, a `# ` title line, and — because
    /// built-ins are native to their language — NO `{{LANGUAGE}}` token.
    func testBuiltinsAreWellFormed() {
        XCTAssertEqual(SummaryTemplates.builtins.count, 8)
        let files = SummaryTemplates.builtins.map(\.file)
        XCTAssertEqual(Set(files).count, files.count, "built-in filenames must be unique")
        XCTAssertTrue(files.contains("Standard.md"))
        for builtin in SummaryTemplates.builtins {
            for lang in AppLanguage.allCases {
                let v = builtin.variant(for: lang)
                XCTAssertFalse(v.name.isEmpty, "\(builtin.file) \(lang.rawValue) name")
                XCTAssertFalse(v.description.isEmpty, "\(builtin.file) \(lang.rawValue) description")
                XCTAssertTrue(v.body.contains("# "), "\(builtin.file) \(lang.rawValue) must define a title line")
                XCTAssertFalse(v.body.contains(SummaryTemplates.placeholder),
                               "\(builtin.file) \(lang.rawValue) is native — no {{LANGUAGE}} token")
                let parsed = SummaryTemplates.parse(
                    SummaryTemplates.fileContent(name: v.name, description: v.description, body: v.body),
                    fallbackName: "x"
                )
                XCTAssertEqual(parsed.name, v.name)
                XCTAssertEqual(parsed.body, v.body)
            }
        }
    }

    /// Each built-in resolves to the requested language's variant.
    func testBuiltinVariantPerLanguage() {
        let standard = SummaryTemplates.standardBuiltin
        XCTAssertEqual(standard.variant(for: .ru).name, "Стандартный")
        XCTAssertEqual(standard.variant(for: .en).name, "Standard")
        XCTAssertEqual(standard.variant(for: .zh).name, "标准")
    }

    func testSlug() {
        XCTAssertEqual(SummaryTemplates.slug("Standard"), "standard")
        XCTAssertEqual(SummaryTemplates.slug("Протокол встречи"), "протокол-встречи")
        XCTAssertEqual(SummaryTemplates.slug("Meeting  Notes!"), "meeting-notes")
        XCTAssertEqual(SummaryTemplates.slug(""), "template")
    }
}
