import SwiftUI

/// Bottom page indicator: dots (active elongated) + optional "шаг N из 3" label.
public struct OnboardingDots: View {
    private let active: Int
    private let total: Int
    private let label: String?

    public init(active: Int, total: Int = 3, label: String? = nil) {
        self.active = active
        self.total = total
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< total, id: \.self) { i in
                Capsule()
                    .fill(i == active ? EmberColor.accent : EmberColor.borderStrong)
                    .frame(width: i == active ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: active)
            }
            if let label {
                Text(label)
                    .font(EmberType.mono(11)).tracking(0.66)
                    .foregroundStyle(EmberColor.text3)
                    .padding(.leading, 6)
            }
        }
    }
}

/// Full-width primary CTA with a trailing arrow (onboarding intro screens).
public struct OnboardingCTA: View {
    private let title: String
    private let onTap: () -> Void

    public init(_ title: String, onTap: @escaping () -> Void) {
        self.title = title
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Text(title).font(EmberType.medium(15))
                EmberIcon(.arrowRight, size: 16, lineWidth: 2, color: .white)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(EmberColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: EmberRadius.md))
            .emberAccentGlow(0.3, radius: 24, y: 8)
        }
        .buttonStyle(EmberPressStyle())
        .hoverCursor()
    }
}

/// Footer bar for setup steps: Back + centered dots + Next/Finish.
public struct OnboardingFooter: View {
    private let backTitle: String
    private let onBack: () -> Void
    private let dotsActive: Int
    private let dotsTotal: Int
    private let nextTitle: String
    private let nextIsFinish: Bool
    private let nextEnabled: Bool
    private let showDots: Bool
    private let onNext: () -> Void

    public init(backTitle: String, onBack: @escaping () -> Void,
                dotsActive: Int, dotsTotal: Int = 3,
                nextTitle: String, nextIsFinish: Bool = false, nextEnabled: Bool = true,
                showDots: Bool = true,
                onNext: @escaping () -> Void) {
        self.backTitle = backTitle
        self.onBack = onBack
        self.dotsActive = dotsActive
        self.dotsTotal = dotsTotal
        self.nextTitle = nextTitle
        self.nextIsFinish = nextIsFinish
        self.nextEnabled = nextEnabled
        self.showDots = showDots
        self.onNext = onNext
    }

    public var body: some View {
        HStack {
            Button(action: onBack) {
                Text(backTitle)
                    .font(EmberType.medium(14)).foregroundStyle(EmberColor.text2)
                    .padding(.horizontal, 18).frame(height: 42)
                    .overlay(RoundedRectangle(cornerRadius: EmberRadius.md).strokeBorder(EmberColor.border, lineWidth: 1))
            }
            .buttonStyle(EmberPressStyle())
            .hoverCursor()

            Spacer()
            if showDots { OnboardingDots(active: dotsActive, total: dotsTotal) }
            Spacer()

            Button(action: onNext) {
                HStack(spacing: 8) {
                    Text(nextTitle).font(EmberType.medium(14))
                    EmberIcon(nextIsFinish ? .check : .arrowRight, size: 15, lineWidth: 2, color: .white)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22).frame(height: 42)
                .background(EmberColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: EmberRadius.md))
                .opacity(nextEnabled ? 1 : 0.45)
            }
            .buttonStyle(EmberPressStyle())
            .hoverCursor()
            .disabled(!nextEnabled)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(EmberColor.border).frame(height: 1) }
    }
}
