@testable import Core
@testable import MeetingsFeature
import XCTest

/// Pure logic of the live summary editor bridge (ported from Sage) — the epoch
/// protocol that prevents stale/echo document overwrites, and the front-matter
/// strip used by the inbound file sync.
@MainActor
final class SummaryEditorTests: XCTestCase {
    func testDocActionAcceptsMatchingEpoch() {
        let a = SummaryWebEditorView.Coordinator.docAction(incomingEpoch: 3, currentEpoch: 3, text: "hi", flush: false)
        XCTAssertEqual(a, .apply(text: "hi", flush: false))
    }

    func testDocActionIgnoresStaleEpoch() {
        XCTAssertEqual(SummaryWebEditorView.Coordinator.docAction(incomingEpoch: 2, currentEpoch: 3,
                                                                  text: "old tail", flush: false), .ignore)
    }

    func testDocActionIgnoresMissingFields() {
        XCTAssertEqual(SummaryWebEditorView.Coordinator.docAction(incomingEpoch: nil, currentEpoch: 1,
                                                                  text: "x", flush: false), .ignore)
        XCTAssertEqual(SummaryWebEditorView.Coordinator.docAction(incomingEpoch: 1, currentEpoch: 1,
                                                                  text: nil, flush: true), .ignore)
    }

    func testDocActionCarriesFlush() {
        let a = SummaryWebEditorView.Coordinator.docAction(incomingEpoch: 5, currentEpoch: 5, text: "t", flush: true)
        XCTAssertEqual(a, .apply(text: "t", flush: true))
    }

    func testAcceptFetchedValidatesEpoch() {
        XCTAssertEqual(SummaryEditorController.acceptFetched(["text": "buf", "epoch": 7], lastPushedEpoch: 7), "buf")
        XCTAssertNil(SummaryEditorController.acceptFetched(["text": "buf", "epoch": 6], lastPushedEpoch: 7))
        XCTAssertNil(SummaryEditorController.acceptFetched(["epoch": 7], lastPushedEpoch: 7))
        XCTAssertNil(SummaryEditorController.acceptFetched(nil, lastPushedEpoch: 7))
    }

    func testThemeJSONHasAllEditorVars() throws {
        for dark in [true, false] {
            let json = SummaryWebEditorView.themeJSON(isDark: dark)
            let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])
            for key in ["--bg", "--bg1", "--bg2", "--bg3", "--bd", "--bd2", "--tx", "--tx2", "--tx3", "--ac", "--acs"] {
                XCTAssertNotNil(dict[key], "missing \(key) (dark=\(dark))")
            }
        }
    }

    func testStripFrontMatterRemovesYAML() {
        let content = "---\ndate: 2026-07-15\ntags: [meeting]\n---\n\n# Тема\n\nтело\n"
        XCTAssertEqual(SummaryExport.stripFrontMatter(content), "# Тема\n\nтело")
    }

    func testStripFrontMatterPassthroughWithoutYAML() {
        XCTAssertEqual(SummaryExport.stripFrontMatter("# Тема\nтело"), "# Тема\nтело")
        XCTAssertEqual(SummaryExport.stripFrontMatter("---\nunclosed"), "---\nunclosed")
    }

    func testExportRoundTripThroughStrip() {
        let md = "# Планёрка\n\n> [!tip] Итог\n\n## Обсуждение\nпункт"
        let full = SummaryExport.frontMatter(markdown: md, title: "Планёрка", createdAt: Date(), typeLabel: "Встреча")
        XCTAssertEqual(SummaryExport.stripFrontMatter(full), md)
    }
}
