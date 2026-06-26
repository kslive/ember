import SwiftUI

/// 44×24 toggle matching the mockup (white knob, accent track when on).
public struct EmberToggle: View {
    @Binding private var isOn: Bool

    public init(isOn: Binding<Bool>) {
        _isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? EmberColor.accent : EmberColor.borderStrong)
                .frame(width: 44, height: 24)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                        .offset(x: isOn ? 22 : 2)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(.plain)
    }
}
