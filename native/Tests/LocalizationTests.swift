@testable import Core
import XCTest

/// Localization primitives: AppLanguage metadata, persisted-language resolution,
/// the lookup/fallback chain, `{name}` interpolation, and full 3-way table parity.
final class LocalizationTests: XCTestCase {
    func testBcp47() {
        XCTAssertEqual(AppLanguage.en.bcp47, "en-US")
        XCTAssertEqual(AppLanguage.ru.bcp47, "ru-RU")
        XCTAssertEqual(AppLanguage.zh.bcp47, "zh-CN")
    }

    func testNativeName() {
        XCTAssertEqual(AppLanguage.en.nativeName, "English")
        XCTAssertEqual(AppLanguage.ru.nativeName, "Русский")
        XCTAssertEqual(AppLanguage.zh.nativeName, "简体中文")
    }

    func testFlag() {
        XCTAssertEqual(AppLanguage.ru.flag, "🇷🇺")
        XCTAssertEqual(AppLanguage.zh.flag, "🇨🇳")
        XCTAssertEqual(AppLanguage.en.flag, "🇬🇧")
    }

    func testCurrentResolution() {
        UserDefaults.standard.removeObject(forKey: LocaleManager.storageKey)
        XCTAssertEqual(AppLanguage.current, .en)
        UserDefaults.standard.set("ru", forKey: LocaleManager.storageKey)
        XCTAssertEqual(AppLanguage.current, .ru)
        UserDefaults.standard.set("garbage", forKey: LocaleManager.storageKey)
        XCTAssertEqual(AppLanguage.current, .en)
        UserDefaults.standard.removeObject(forKey: LocaleManager.storageKey)
    }

    @MainActor func testLookupAndKeyFallback() {
        let manager = LocaleManager(language: .en)
        XCTAssertEqual(manager.t("nav.home"), "Home")
        XCTAssertEqual(manager.t("totally.unknown.key.xyz"), "totally.unknown.key.xyz")
    }

    @MainActor func testInterpolationReplacesAndLeavesUnknown() {
        let manager = LocaleManager(language: .en)
        let full = manager.t("onb.step", ["n": "2", "t": "3"])
        XCTAssertTrue(full.contains("2"))
        XCTAssertTrue(full.contains("3"))
        XCTAssertFalse(full.contains("{n}"))
        let partial = manager.t("onb.step", ["n": "2"])
        XCTAssertTrue(partial.contains("{t}"))
    }

    func testLocalizedStringsCurrentFallback() {
        UserDefaults.standard.set("ru", forKey: LocaleManager.storageKey)
        XCTAssertEqual(LocalizedStrings.current("nav.home"), "Главная")
        XCTAssertEqual(LocalizedStrings.current("no.such.key"), "no.such.key")
        UserDefaults.standard.removeObject(forKey: LocaleManager.storageKey)
    }

    func testTableParityBothDirections() {
        let en = Set(LocalizedStrings.en.keys)
        let ru = Set(LocalizedStrings.ru.keys)
        let zh = Set(LocalizedStrings.zh.keys)
        XCTAssertEqual(en, ru, "en↔ru key diff: \(en.symmetricDifference(ru).sorted())")
        XCTAssertEqual(en, zh, "en↔zh key diff: \(en.symmetricDifference(zh).sorted())")
    }
}
