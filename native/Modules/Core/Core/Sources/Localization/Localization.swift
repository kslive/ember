import Combine
import SwiftUI

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en
    case ru
    case zh

    public var id: String {
        rawValue
    }

    public var nativeName: String {
        switch self {
        case .en: "English"
        case .ru: "Русский"
        case .zh: "简体中文"
        }
    }

    public var bcp47: String {
        switch self {
        case .en: "en-US"
        case .ru: "ru-RU"
        case .zh: "zh-CN"
        }
    }

    public var flag: String {
        switch self {
        case .en: "🇬🇧"
        case .ru: "🇷🇺"
        case .zh: "🇨🇳"
        }
    }

    /// The persisted UI language (reads `LocaleManager.storageKey`, defaults to `.en`).
    /// Single source of truth so the `"ember.language"` key/decode isn't repeated.
    public static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: LocaleManager.storageKey) ?? "en") ?? .en
    }
}

/// Runtime locale manager — switches UI language instantly (no app restart).
/// Strings live in `LocalizedStrings`; features extend the table by registering.
@MainActor
public final class LocaleManager: ObservableObject {
    @Published public var language: AppLanguage

    public static let storageKey = "ember.language"

    public init(language: AppLanguage? = nil) {
        if let language {
            self.language = language
        } else if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
                  let stored = AppLanguage(rawValue: raw) {
            self.language = stored
        } else {
            let pref = Locale.preferredLanguages.first ?? "en"
            if pref.hasPrefix("ru") { self.language = .ru } else if pref.hasPrefix("zh") { self.language = .zh } else { self.language = .en }
        }
    }

    public func setLanguage(_ language: AppLanguage) {
        withAnimation(.easeInOut(duration: 0.3)) { self.language = language }
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
    }

    /// Look up a localized string by key, falling back to English, then the key itself.
    public func t(_ key: String) -> String {
        LocalizedStrings.table[language]?[key]
            ?? LocalizedStrings.table[.en]?[key]
            ?? key
    }

    /// Look up with simple `{name}`-style interpolation.
    public func t(_ key: String, _ args: [String: String]) -> String {
        var s = t(key)
        for (k, v) in args {
            s = s.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return s
    }
}
