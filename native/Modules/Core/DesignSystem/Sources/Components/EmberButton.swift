import SwiftUI

public enum EmberButtonStyleKind {
    case primary
    case secondary
    case ghost
}

public struct EmberButton: View {
    private let title: String
    private let kind: EmberButtonStyleKind
    private let fullWidth: Bool
    private let height: CGFloat
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    public init(
        _ title: String,
        kind: EmberButtonStyleKind = .primary,
        fullWidth: Bool = false,
        height: CGFloat = 44,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.fullWidth = fullWidth
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(EmberType.medium(14))
                .foregroundStyle(foreground)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .padding(.horizontal, fullWidth ? 0 : 18)
                .background(background)
                .overlay(Color.white.opacity(hoverOverlay))
                .overlay(
                    RoundedRectangle(cornerRadius: EmberRadius.md)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: EmberRadius.md))
        }
        .buttonStyle(EmberPressStyle())
        .onHoverState($hovering)
        .hoverCursor()
        .animation(.easeOut(duration: 0.12), value: hovering)
        .modifier(GlowIfPrimary(enabled: kind == .primary && isEnabled))
    }

    private var hoverOverlay: Double {
        guard hovering, isEnabled else { return 0 }
        return kind == .primary ? 0.10 : 0.05
    }

    private var foreground: Color {
        guard isEnabled else { return EmberColor.text3 }
        switch kind {
        case .primary: return .white
        case .secondary, .ghost: return EmberColor.text2
        }
    }

    @ViewBuilder private var background: some View {
        if !isEnabled {
            EmberColor.surface
        } else {
            switch kind {
            case .primary: EmberColor.accent
            case .secondary: EmberColor.surface2
            case .ghost: Color.clear
            }
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: .clear
        case .secondary, .ghost: isEnabled ? EmberColor.border : .clear
        }
    }
}

private struct GlowIfPrimary: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.emberAccentGlow() } else { content }
    }
}
