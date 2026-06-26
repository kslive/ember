import SwiftUI

public enum EmberRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 11
    public static let lg: CGFloat = 14
    public static let pill: CGFloat = 999
}

/// Typography — bundled Geist / Geist Mono (exact PostScript names), fixed-size
/// so it matches the mockup pixel metrics (no Dynamic Type scaling).
/// Call `EmberFonts.register()` once at launch.
public enum EmberType {
    public static func display(_ size: CGFloat = 36) -> Font {
        .custom("Geist-Light", fixedSize: size)
    }

    public static func regular(_ size: CGFloat) -> Font {
        .custom("Geist-Regular", fixedSize: size)
    }

    public static func medium(_ size: CGFloat) -> Font {
        .custom("Geist-Medium", fixedSize: size)
    }

    public static func semibold(_ size: CGFloat) -> Font {
        .custom("Geist-SemiBold", fixedSize: size)
    }

    public static func bold(_ size: CGFloat) -> Font {
        .custom("Geist-Bold", fixedSize: size)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .medium ? "GeistMono-Medium" : "GeistMono-Regular", fixedSize: size)
    }
}

public extension View {
    /// Orange glow under accent controls (0 8 24 rgba(249,115,22,.3)).
    func emberAccentGlow(_ opacity: Double = 0.3, radius: CGFloat = 22, y: CGFloat = 8) -> some View {
        shadow(color: EmberColor.accent.opacity(opacity), radius: radius, x: 0, y: y)
    }
}
