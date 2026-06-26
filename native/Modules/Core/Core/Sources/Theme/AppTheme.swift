import Combine
import SwiftUI

public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    case auto

    public var id: String {
        rawValue
    }

    /// nil = follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .auto: nil
        }
    }
}

@MainActor
public final class ThemeManager: ObservableObject {
    @Published public var theme: AppTheme

    private static let storageKey = "ember.theme"

    public init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppTheme(rawValue: raw) {
            theme = stored
        } else {
            theme = .auto
        }
    }

    public func setTheme(_ theme: AppTheme) {
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
    }
}
