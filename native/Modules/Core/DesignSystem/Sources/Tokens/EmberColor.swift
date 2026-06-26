import AppKit
import SwiftUI

public extension Color {
    /// Initialize from a hex string (`#RRGGBB` or `#RRGGBBAA`, with or without `#`).
    init(hex: String, opacity: Double = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a * opacity)
    }
}

/// A color that resolves differently for light/dark appearance, backed by a
/// dynamic NSColor so it tracks the system/window appearance automatically.
func dynamicColor(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? dark : light
    })
}

private func ns(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    if s.count == 8 {
        return NSColor(srgbRed: CGFloat((v >> 24) & 0xFF) / 255,
                       green: CGFloat((v >> 16) & 0xFF) / 255,
                       blue: CGFloat((v >> 8) & 0xFF) / 255,
                       alpha: CGFloat(v & 0xFF) / 255)
    }
    _ = s
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255,
                   alpha: alpha)
}

/// Ember semantic color tokens — exact values from the redesign mockup.
/// Dark / light pairs resolve automatically with the active appearance.
public enum EmberColor {
    public static let bg = dynamicColor(dark: ns("0E0E10"), light: ns("FAF9F7"))
    public static let surface = dynamicColor(dark: ns("161618"), light: ns("F0EDE8"))
    public static let surface2 = dynamicColor(dark: ns("1C1C1F"), light: ns("FFFFFF"))
    public static let text = dynamicColor(dark: ns("F5F5F4"), light: ns("1C1B1A"))
    public static let text2 = dynamicColor(dark: ns("A1A1A0"), light: ns("605D58"))
    public static let text3 = dynamicColor(dark: ns("6B6B6A"), light: ns("908D88"))
    public static let accent = Color(hex: "F97316")
    public static let accentText = dynamicColor(dark: ns("FB923C"), light: ns("C2410C"))
    public static let accentWeak = dynamicColor(dark: ns("F97316", 0.13), light: ns("F97316", 0.10))
    public static let border = dynamicColor(dark: NSColor(white: 1, alpha: 0.07), light: NSColor(white: 0, alpha: 0.07))
    public static let borderStrong = dynamicColor(dark: NSColor(white: 1, alpha: 0.13), light: NSColor(white: 0, alpha: 0.14))
    public static let rec = dynamicColor(dark: ns("EF4444"), light: ns("DC2626"))
    public static let good = dynamicColor(dark: ns("34D399"), light: ns("0F9D6B"))
    public static let warn = dynamicColor(dark: ns("FBBF24"), light: ns("B45309"))
}
