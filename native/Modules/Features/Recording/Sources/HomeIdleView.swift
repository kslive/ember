import Core
import DesignSystem
import SwiftUI

/// Home / "Ready to record" idle screen (mockup H2).
public struct HomeIdleView: View {
    @EnvironmentObject private var locale: LocaleManager
    private let isEmpty: Bool
    private let onStart: () -> Void

    public init(isEmpty: Bool = false, onStart: @escaping () -> Void) {
        self.isEmpty = isEmpty
        self.onStart = onStart
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                LanguageChip()
            }
            .frame(height: 60)
            .padding(.horizontal, 26)

            Spacer()

            VStack(spacing: 14) {
                Text(locale.t(isEmpty ? "home.empty.title" : "home.ready.title"))
                    .font(EmberType.display(isEmpty ? 36 : 38))
                    .tracking(-0.76)
                    .foregroundStyle(EmberColor.text)

                Text(locale.t(isEmpty ? "home.empty.subtitle" : "home.ready.subtitle"))
                    .font(EmberType.regular(15))
                    .foregroundStyle(EmberColor.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)

                VStack(spacing: 20) {
                    RecordButton(onTap: onStart)
                    Text(locale.t("home.shortcut"))
                        .font(EmberType.mono(12))
                        .tracking(0.24)
                        .foregroundStyle(EmberColor.text3)
                }
                .padding(.top, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmberColor.bg)
    }
}

/// The large round start-recording button with its glowing ring.
struct RecordButton: View {
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(EmberColor.accent)
                    .frame(width: 76, height: 76)
                    .haloPulse(color: EmberColor.accent, maxScale: 1.45)
                Circle()
                    .strokeBorder(EmberColor.accent.opacity(0.3), lineWidth: 1)
                    .frame(width: 94, height: 94)
                Circle()
                    .fill(EmberColor.accent)
                    .frame(width: 76, height: 76)
                    .shadow(color: EmberColor.accent.opacity(0.4), radius: 30, x: 0, y: 10)
                EmberIcon(.mic, size: 26, lineWidth: 2, color: .white)
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .frame(width: 94, height: 94)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .hoverCursor()
    }
}
