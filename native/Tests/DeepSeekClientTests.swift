import Core
import Security
@testable import SummaryService
import XCTest

/// DeepSeek response decoding (no network) + SecretStore round-trip for the API key.
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

    func testSecretStoreRoundTrip() {
        let account = "test-deepseek-key-\(UUID().uuidString)"
        defer { SecretStore.delete(account) }
        XCTAssertNil(SecretStore.get(account))
        XCTAssertTrue(SecretStore.set("sk-test-123", account: account))
        XCTAssertEqual(SecretStore.get(account), "sk-test-123")
        XCTAssertTrue(SecretStore.set("sk-updated", account: account))
        XCTAssertEqual(SecretStore.get(account), "sk-updated")
        XCTAssertTrue(SecretStore.delete(account))
        XCTAssertNil(SecretStore.get(account))
    }

    /// A key saved by builds ≤1.5.0 (login keychain) must transparently move into
    /// the encrypted file on first read, and the keychain item must be gone.
    func testKeychainMigration() {
        let account = "test-migrate-\(UUID().uuidString)"
        defer { SecretStore.delete(account) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kslff.ember",
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("sk-legacy".utf8)
        ]
        XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(SecretStore.get(account), "sk-legacy")
        let find: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kslff.ember",
            kSecAttrAccount as String: account
        ]
        XCTAssertEqual(SecItemCopyMatching(find as CFDictionary, nil), errSecItemNotFound)
        XCTAssertEqual(SecretStore.get(account), "sk-legacy")
    }
}
