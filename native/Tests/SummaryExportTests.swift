@testable import Core
import XCTest

/// Auto-export of summaries to the chosen Markdown folder (General settings).
final class SummaryExportTests: XCTestCase {
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    func testFileNameFromTitle() {
        XCTAssertEqual(SummaryExport.fileName(title: "Планёрка по релизу", createdAt: date(2026, 6, 1, 10, 0)),
                       "2026-06-01 — Планёрка по релизу.md")
    }

    func testFileNameSanitizesIllegalChars() {
        XCTAssertEqual(SummaryExport.fileName(title: "a/b:c*d?", createdAt: date(2026, 6, 1, 10, 0)),
                       "2026-06-01 — a-b-c-d-.md")
    }

    func testFileNameEmptyFallsBackToDate() {
        XCTAssertEqual(SummaryExport.fileName(title: "   ", createdAt: date(2026, 6, 1, 9, 7)), "2026-06-01-09-07.md")
    }

    func testFrontMatterContainsYAMLAndBody() {
        let fm = SummaryExport.frontMatter(markdown: "# Тема\nтекст", title: "Тема",
                                           createdAt: date(2026, 6, 1, 9, 7), typeLabel: "Встреча")
        XCTAssertTrue(fm.contains("date: 2026-06-01"))
        XCTAssertTrue(fm.contains("time: \"09:07\""))
        XCTAssertTrue(fm.contains("type: \"Встреча\""))
        XCTAssertTrue(fm.contains("tags: [meeting]"))
        XCTAssertTrue(fm.contains("# Тема"))
    }

    func testWriteCreatesFile() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ember-export-\(UUID().uuidString)")
        let url = SummaryExport.write(markdown: "# X\nbody", title: "X", createdAt: date(2026, 6, 1, 10, 0),
                                      typeLabel: "Meeting", folder: dir.path)
        XCTAssertNotNil(url)
        if let url {
            XCTAssertEqual(url.lastPathComponent, "2026-06-01 — X.md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            XCTAssertTrue(content.contains("tags: [meeting]"))
            XCTAssertTrue(content.contains("body"))
        }
        try? FileManager.default.removeItem(at: dir)
    }

    func testWriteEmptyFolderReturnsNil() {
        XCTAssertNil(SummaryExport.write(markdown: "x", title: "t", createdAt: Date(), typeLabel: "m", folder: ""))
    }

    func testWriteEmptyMarkdownReturnsNil() {
        XCTAssertNil(SummaryExport.write(markdown: "", title: "t", createdAt: Date(), typeLabel: "m",
                                         folder: FileManager.default.temporaryDirectory.path))
    }
}
