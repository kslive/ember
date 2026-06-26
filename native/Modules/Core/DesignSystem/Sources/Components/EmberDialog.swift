import SwiftUI

public enum DialogTone {
    case danger, warning, info
}

/// Confirmation dialog (mockup EmberDialog) — backdrop + 420pt card, 3 tones.
public struct EmberDialog: View {
    private let tone: DialogTone
    private let title: String
    private let message: String
    private let confirmLabel: String
    private let cancelLabel: String
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(tone: DialogTone, title: String, message: String, confirmLabel: String, cancelLabel: String,
                onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.tone = tone
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { onCancel() }
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                EmberIcon(toneIcon, size: 19, lineWidth: 1.8, color: toneColor)
                    .frame(width: 40, height: 40)
                    .background(toneBg)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(EmberType.semibold(16.5)).tracking(-0.16).foregroundStyle(EmberColor.text)
                    Text(message).font(EmberType.regular(13.5)).lineSpacing(2).foregroundStyle(EmberColor.text2)
                }
                Spacer(minLength: 0)
                Button(action: onCancel) { EmberIcon(.close, size: 16, lineWidth: 2, color: EmberColor.text3) }
                    .buttonStyle(EmberPressStyle())
                    .hoverCursor()
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

            HStack(spacing: 9) {
                Spacer()
                Button(action: onCancel) {
                    Text(cancelLabel).font(EmberType.medium(13.5)).foregroundStyle(EmberColor.text)
                        .padding(.horizontal, 16).frame(height: 38)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(EmberColor.borderStrong, lineWidth: 1))
                }
                .buttonStyle(EmberPressStyle())
                .keyboardShortcut(.cancelAction)
                .hoverCursor()
                Button(action: onConfirm) {
                    Text(confirmLabel).font(EmberType.semibold(13.5)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 38)
                        .background(toneColor)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(EmberPressStyle())
                .keyboardShortcut(.defaultAction)
                .hoverCursor()
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(EmberColor.border).frame(height: 1) }
        }
        .frame(width: 420)
        .background(EmberColor.surface2)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(EmberColor.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.5), radius: 35, x: 0, y: 24)
    }

    private var toneIcon: EmberIcon.Glyph {
        switch tone {
        case .danger: .trash
        case .warning, .info: .sparkle
        }
    }

    private var toneColor: Color {
        switch tone {
        case .danger: EmberColor.rec
        case .warning: EmberColor.warn
        case .info: EmberColor.accent
        }
    }

    private var toneBg: Color {
        switch tone {
        case .danger: Color(hex: "EF4444", opacity: 0.13)
        case .warning: Color(hex: "F59E0B", opacity: 0.14)
        case .info: EmberColor.accentWeak
        }
    }
}

/// Rename dialog with a text field.
public struct RenameDialog: View {
    @State private var text: String
    private let title: String
    private let confirmLabel: String
    private let cancelLabel: String
    private let onConfirm: (String) -> Void
    private let onCancel: () -> Void

    public init(initial: String, title: String, confirmLabel: String, cancelLabel: String,
                onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initial)
        self.title = title
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { onCancel() }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(EmberType.semibold(16.5)).foregroundStyle(EmberColor.text)
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(EmberType.regular(14)).foregroundStyle(EmberColor.text)
                        .padding(.horizontal, 14).frame(height: 42)
                        .background(EmberColor.surface)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(EmberColor.accent, lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

                HStack(spacing: 9) {
                    Spacer()
                    Button(action: onCancel) {
                        Text(cancelLabel).font(EmberType.medium(13.5)).foregroundStyle(EmberColor.text)
                            .padding(.horizontal, 16).frame(height: 38)
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(EmberColor.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(EmberPressStyle())
                    .keyboardShortcut(.cancelAction)
                    .hoverCursor()
                    Button(action: { onConfirm(text.trimmingCharacters(in: .whitespaces)) }, label: {
                        Text(confirmLabel).font(EmberType.semibold(13.5)).foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(height: 38)
                            .background(EmberColor.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                    })
                    .buttonStyle(EmberPressStyle())
                    .keyboardShortcut(.defaultAction)
                    .hoverCursor()
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .overlay(alignment: .top) { Rectangle().fill(EmberColor.border).frame(height: 1) }
            }
            .frame(width: 420)
            .background(EmberColor.surface2)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(EmberColor.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.5), radius: 35, x: 0, y: 24)
        }
    }
}
