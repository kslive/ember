import AppKit
import SwiftUI

/// Press feedback: a subtle scale-down while pressed.
public struct EmberPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Pointing-hand cursor while hovered (balanced push/pop, safe on disappear).
public struct HoverCursor: ViewModifier {
    @State private var inside = false
    public func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != inside else { return }
                inside = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if inside { NSCursor.pop(); inside = false } }
    }
}

public extension View {
    func hoverCursor() -> some View {
        modifier(HoverCursor())
    }

    /// Reports hover state into a binding (for highlight effects).
    func onHoverState(_ binding: Binding<Bool>) -> some View {
        onHover { binding.wrappedValue = $0 }
    }
}

/// Subtle hover highlight (theme-aware overlay) + pointing-hand cursor, for rows
/// and cards. Lightens in dark mode, darkens in light mode.
public struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    let cornerRadius: CGFloat
    let intensity: Double

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(hovering ? intensity : 0))
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering = $0 }
            .hoverCursor()
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

public extension View {
    func emberHover(cornerRadius: CGFloat = 9, intensity: Double = 0.06) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, intensity: intensity))
    }
}
