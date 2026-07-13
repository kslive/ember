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

/// Accent color preset: the solid base (buttons, dots, rings) plus the tinted
/// text shades for dark/light appearance. Triads follow the Tailwind 500/400/700
/// pattern the mockup's orange was built from.
public struct AccentPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let base: String
    public let textDark: String
    public let textLight: String

    public static let ember = AccentPreset(id: "ember", base: "F97316", textDark: "FB923C", textLight: "C2410C")
    public static let emerald = AccentPreset(id: "emerald", base: "10B981", textDark: "34D399", textLight: "047857")
    public static let blue = AccentPreset(id: "blue", base: "3B82F6", textDark: "60A5FA", textLight: "1D4ED8")
    public static let violet = AccentPreset(id: "violet", base: "8B5CF6", textDark: "A78BFA", textLight: "6D28D9")
    public static let pink = AccentPreset(id: "pink", base: "EC4899", textDark: "F472B6", textLight: "BE185D")
    public static let teal = AccentPreset(id: "teal", base: "14B8A6", textDark: "2DD4BF", textLight: "0F766E")

    public static let all: [AccentPreset] = [.ember, .emerald, .blue, .violet, .pink, .teal]

    public static func preset(id: String) -> AccentPreset {
        all.first { $0.id == id } ?? .ember
    }

    /// The active preset, read by the EmberColor tokens on every render. Written
    /// on the main thread (ThemeManager) before the root view rebuilds.
    public nonisolated(unsafe) static var current: AccentPreset =
        preset(id: UserDefaults.standard.string(forKey: "ember.accent") ?? "ember")
}

@MainActor
public final class ThemeManager: ObservableObject {
    @Published public var theme: AppTheme
    @Published public var accentId: String

    private static let storageKey = "ember.theme"
    private static let accentKey = "ember.accent"

    public init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppTheme(rawValue: raw) {
            theme = stored
        } else {
            theme = .auto
        }
        accentId = AccentPreset.current.id
    }

    public func setTheme(_ theme: AppTheme) {
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
    }

    public func setAccent(_ preset: AccentPreset) {
        AccentPreset.current = preset
        accentId = preset.id
        UserDefaults.standard.set(preset.id, forKey: Self.accentKey)
    }
}
