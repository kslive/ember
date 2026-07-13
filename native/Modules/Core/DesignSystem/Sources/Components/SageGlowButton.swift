import SwiftUI

/// Sage-branded action button: a capsule wrapped in Sage's signature rotating
/// AI-glow border (stroke layers with different blur riding an angular gradient —
/// the same look as Sage's inline AI input highlight). Uses Sage's brand green
/// regardless of Ember's accent, so the button reads as "Sage".
public struct SageGlowButton: View {
    private let title: String
    private let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var rotation = 0.0
    @State private var hovering = false

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    private var brand: Color {
        scheme == .dark ? Color(hex: "4CC38A") : Color(hex: "16895A")
    }

    private var glint: Color {
        scheme == .dark ? Color(white: 1, opacity: 0.95) : brand.opacity(0.45)
    }

    private var sweep: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: brand, location: 0.0),
                .init(color: brand.opacity(0.6), location: 0.22),
                .init(color: glint, location: 0.5),
                .init(color: brand.opacity(0.6), location: 0.78),
                .init(color: brand, location: 1.0)
            ]),
            center: .center, angle: .degrees(rotation)
        )
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(brand).frame(width: 6, height: 6)
                Text(title).font(EmberType.medium(12.5)).foregroundStyle(brand)
                    .lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Capsule().fill(EmberColor.surface.opacity(hovering ? 1 : 0.65)))
            .overlay {
                ZStack {
                    Capsule().stroke(sweep, lineWidth: 3).blur(radius: 6).opacity(hovering ? 0.8 : 0.55)
                    Capsule().stroke(sweep, lineWidth: 1.6).blur(radius: 2)
                    Capsule().strokeBorder(sweep, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverCursor()
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.2), value: hovering)
        .onAppear {
            rotation = 0
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { rotation = 360 }
        }
    }
}
