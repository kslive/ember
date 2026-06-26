import SwiftUI

/// Recording equalizer — 15 accent bars driven by audio levels (0...1).
/// When `paused`, bars collapse to a thin amber line.
public struct Equalizer: View {
    private let levels: [CGFloat]
    private let paused: Bool

    public static let barCount = 15

    public init(levels: [CGFloat], paused: Bool = false) {
        self.levels = levels
        self.paused = paused
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0 ..< Self.barCount, id: \.self) { i in
                let level = i < levels.count ? levels[i] : 0
                Capsule()
                    .fill(paused ? EmberColor.warn : EmberColor.accent)
                    .frame(width: 3, height: paused ? 4 : barHeight(level))
                    .opacity(paused ? 0.6 : 1)
            }
        }
        .frame(height: 40)
    }

    private func barHeight(_ level: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, level))
        return 6 + clamped * 34
    }
}
