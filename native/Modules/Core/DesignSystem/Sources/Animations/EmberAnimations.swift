import SwiftUI

/// `recPulse` — recording dot breathing (opacity 1 ↔ .35, ~1.4s).
public struct RecPulse: ViewModifier {
    @State private var on = false
    public init() {}
    public func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// `caretBlink` — text caret (1s blink).
public struct CaretBlink: ViewModifier {
    @State private var on = false
    public init() {}
    public func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// `softPulse` — gentle attention pulse for an icon that stays visible
/// (scale 0.94 ↔ 1.14, opacity .55 ↔ 1, ~1.5s). Used for the summary sparkle.
public struct SoftPulse: ViewModifier {
    @State private var on = false
    public init() {}
    public func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.14 : 0.94)
            .opacity(on ? 1 : 0.55)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// `haloPulse` — a continuously breathing accent halo placed *behind* a circular
/// control (the control itself is untouched). Used for the sidebar dot + mic button.
public struct HaloPulse: ViewModifier {
    @State private var on = false
    let color: Color
    let maxScale: CGFloat
    public init(color: Color, maxScale: CGFloat) {
        self.color = color; self.maxScale = maxScale
    }

    public func body(content: Content) -> some View {
        content.background(
            Circle()
                .fill(color)
                .scaleEffect(on ? maxScale : 1)
                .opacity(on ? 0 : 0.35)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: on)
                .onAppear { on = true }
        )
    }
}

/// `shimmerSweep` — a soft highlight band sweeping across the view, masked to the
/// view's own shape. THE skeleton shimmer: no scale, no opacity pulse (a scale
/// pulse on placeholder bars reads as "zooming", not loading).
public struct ShimmerSweep: ViewModifier {
    @State private var phase: CGFloat = 0
    public init() {}
    public func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: EmberColor.text.opacity(0.05), location: 0.4),
                            .init(color: EmberColor.text.opacity(0.09), location: 0.5),
                            .init(color: EmberColor.text.opacity(0.05), location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: -geo.size.width * 0.55 + phase * geo.size.width * 1.55)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

public extension View {
    func recPulse() -> some View {
        modifier(RecPulse())
    }

    func caretBlink() -> some View {
        modifier(CaretBlink())
    }

    func softPulse() -> some View {
        modifier(SoftPulse())
    }

    func haloPulse(color: Color, maxScale: CGFloat = 1.6) -> some View {
        modifier(HaloPulse(color: color, maxScale: maxScale))
    }

    func shimmerSweep() -> some View {
        modifier(ShimmerSweep())
    }
}
