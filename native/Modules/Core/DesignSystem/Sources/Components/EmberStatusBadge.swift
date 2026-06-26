import SwiftUI

/// Recording status pill: red breathing dot + label + timer.
public struct RecordingBadge: View {
    private let label: String
    private let timecode: String

    public init(label: String, timecode: String) {
        self.label = label
        self.timecode = timecode
    }

    public var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(EmberColor.rec)
                .frame(width: 9, height: 9)
                .recPulse()
            Text(label)
                .font(EmberType.medium(13))
            Text(timecode)
                .font(EmberType.mono(13))
        }
        .foregroundStyle(EmberColor.rec)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(EmberColor.rec.opacity(0.12))
        .clipShape(Capsule())
    }
}
