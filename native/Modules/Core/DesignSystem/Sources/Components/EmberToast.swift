import Core
import SwiftUI

/// Transient in-app toast banner (paired with native notifications).
public struct EmberToast: View {
    private let info: ToastInfo
    public init(info: ToastInfo) {
        self.info = info
    }

    public var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(info.text).font(EmberType.medium(13.5)).foregroundStyle(EmberColor.text)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(EmberColor.surface2)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(EmberColor.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 10)
    }

    private var color: Color {
        switch info.tone {
        case .info: EmberColor.accent
        case .good: EmberColor.good
        case .warn: EmberColor.warn
        case .error: EmberColor.rec
        }
    }
}
