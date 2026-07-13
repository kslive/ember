import Core
@testable import SummaryService
import XCTest

/// DeepSeek response decoding (no network) + Keychain round-trip for the API key.
final class DeepSeekClientTests: XCTestCase {
    func testDecodeModelsList() throws {
        let json = Data("""
        {"object":"list","data":[{"id":"deepseek-v4-flash","object":"model","owned_by":"deepseek"},
                                 {"id":"deepseek-v4-pro","object":"model","owned_by":"deepseek"}]}
        """.utf8)
        XCTAssertEqual(try DeepSeekClient.decodeModels(json), ["deepseek-v4-flash", "deepseek-v4-pro"])
    }

    func testDecodeChatContent() throws {
        let json = Data("""
        {"id":"x","choices":[{"index":0,"message":{"role":"assistant","content":"  # Тема\\n\\nТекст саммари.  "},
        "finish_reason":"stop"}],"usage":{"total_tokens":10}}
        """.utf8)
        XCTAssertEqual(try DeepSeekClient.decodeChat(json), "# Тема\n\nТекст саммари.")
    }

    func testDecodeChatEmptyContentThrows() {
        let json = Data(#"{"choices":[{"message":{"role":"assistant","content":"   "}}]}"#.utf8)
        XCTAssertThrowsError(try DeepSeekClient.decodeChat(json))
        let none = Data(#"{"choices":[]}"#.utf8)
        XCTAssertThrowsError(try DeepSeekClient.decodeChat(none))
    }

    func testDecodeModelsGarbageThrows() {
        XCTAssertThrowsError(try DeepSeekClient.decodeModels(Data("not json".utf8)))
    }

    func testKeychainRoundTrip() {
        let account = "test-deepseek-key-\(UUID().uuidString)"
        defer { KeychainStore.delete(account) }
        XCTAssertNil(KeychainStore.get(account))
        XCTAssertTrue(KeychainStore.set("sk-test-123", account: account))
        XCTAssertEqual(KeychainStore.get(account), "sk-test-123")
        XCTAssertTrue(KeychainStore.set("sk-updated", account: account))
        XCTAssertEqual(KeychainStore.get(account), "sk-updated")
        XCTAssertTrue(KeychainStore.delete(account))
        XCTAssertNil(KeychainStore.get(account))
    }
}
