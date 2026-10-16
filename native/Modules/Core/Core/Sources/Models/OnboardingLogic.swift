import Foundation

/// Pure onboarding rules — language picker table and step gating — kept out of
/// the view so they are unit-tested.
public enum OnboardingLogic {
    /// Language cards, in picker order.
    public static let langOrder: [AppLanguage] = [.ru, .en, .zh]

    /// Card title: the language's own name.
    public static func title(_ lang: AppLanguage) -> String {
        switch lang {
        case .en: "English"
        case .ru: "Русский"
        case .zh: "中文"
        }
    }

    /// Card subtitle in the current UI language. When the card is the UI language
    /// itself, Russian shows its English name instead of repeating the title.
    public static func subtitle(ui: AppLanguage, card: AppLanguage) -> String {
        switch ui {
        case .ru:
            switch card {
            case .ru: "Russian"
            case .en: "Английский"
            case .zh: "Китайский · упрощённый"
            }
        case .en:
            switch card {
            case .ru: "Russian"
            case .en: "English"
            case .zh: "Chinese · Simplified"
            }
        case .zh:
            switch card {
            case .ru: "俄语"
            case .en: "英语"
            case .zh: "简体中文"
            }
        }
    }

    public static func flag(_ lang: AppLanguage) -> String {
        switch lang {
        case .en: "🇬🇧"
        case .ru: "🇷🇺"
        case .zh: "🇨🇳"
        }
    }

    /// A model step unlocks "Next" only once its model is fully downloaded.
    public static func nextEnabled(_ state: ModelDownloadState?) -> Bool {
        state == .ready
    }
}
