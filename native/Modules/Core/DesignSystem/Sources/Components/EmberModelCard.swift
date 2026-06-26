import Core
import SwiftUI

public enum ModelCardState: Equatable {
    case download
    case downloading(Double)
    case ready
    case selected
    case failed

    /// Maps a download state + selection into a card state (single source of
    /// truth, unit-tested).
    public static func from(_ state: ModelDownloadState, selected: Bool) -> ModelCardState {
        switch state {
        case let .downloading(p): .downloading(p)
        case .ready: selected ? .selected : .ready
        case .failed: .failed
        case .absent: .download
        }
    }
}

/// Model selection card (mockup EmberModelCard) — download/downloading/ready/
/// selected/failed states.
public struct EmberModelCard: View {
    @EnvironmentObject private var locale: LocaleManager
    private let name: String
    private let desc: String
    private let meta: String
    private let badge: String?
    private let state: ModelCardState
    private let totalMB: Int
    private let errorText: String?
    private let onAction: () -> Void

    public init(name: String, desc: String, meta: String, badge: String? = nil, state: ModelCardState, totalMB: Int = 0, errorText: String? = nil, onAction: @escaping () -> Void) {
        self.name = name
        self.desc = desc
        self.meta = meta
        self.badge = badge
        self.state = state
        self.totalMB = totalMB
        self.errorText = errorText
        self.onAction = onAction
    }

    private var isSelected: Bool {
        state == .selected
    }

    private func downloadingText(_ p: Double) -> String {
        if totalMB > 0 {
            let done = Int((p * Double(totalMB)).rounded())
            let unit = locale.language == .ru ? "МБ" : "MB"
            return "\(done) / \(totalMB) \(unit) · \(Int(p * 100))%"
        }
        return locale.t("model.downloading", ["p": "\(Int(p * 100))%"])
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Text(name)
                        .font(EmberType.semibold(15)).tracking(-0.15)
                        .foregroundStyle(EmberColor.text)
                    if let badge {
                        Text(badge)
                            .font(EmberType.mono(9.5)).tracking(0.76).textCase(.uppercase)
                            .foregroundStyle(EmberColor.accentText)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(EmberColor.accentWeak)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    statusLabel
                    Spacer(minLength: 0)
                }
                if state == .failed, let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(EmberType.regular(12.5)).lineSpacing(2)
                        .foregroundStyle(EmberColor.rec)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(desc)
                        .font(EmberType.regular(13)).lineSpacing(2)
                        .foregroundStyle(EmberColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(meta)
                    .font(EmberType.mono(11.5))
                    .foregroundStyle(EmberColor.text3)
                    .padding(.top, 2)
            }
            rightControl
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(isSelected ? EmberColor.accentWeak : EmberColor.surface2)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.28), value: state)
    }

    private var borderColor: Color {
        if state == .failed { return EmberColor.rec.opacity(0.4) }
        return isSelected ? EmberColor.accent : EmberColor.border
    }

    @ViewBuilder private var statusLabel: some View {
        switch state {
        case .ready, .selected:
            HStack(spacing: 5) {
                Circle().fill(EmberColor.good).frame(width: 6, height: 6)
                Text(locale.t(state == .selected ? "model.selected" : "model.ready"))
                    .font(EmberType.regular(11))
                    .foregroundStyle(EmberColor.good)
            }
        case .failed:
            HStack(spacing: 5) {
                Circle().fill(EmberColor.rec).frame(width: 6, height: 6)
                Text(locale.t("model.failed"))
                    .font(EmberType.regular(11))
                    .foregroundStyle(EmberColor.rec)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var rightControl: some View {
        switch state {
        case .download:
            Button(action: onAction) {
                HStack(spacing: 7) {
                    EmberIcon(.download, size: 14, lineWidth: 1.8, color: EmberColor.text)
                    Text(locale.t("model.download")).font(EmberType.medium(13)).foregroundStyle(EmberColor.text)
                }
                .padding(.horizontal, 14).frame(height: 34)
                .background(EmberColor.surface)
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(EmberColor.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(EmberPressStyle())
            .emberHover(cornerRadius: 11)

        case let .downloading(p):
            VStack(alignment: .trailing, spacing: 7) {
                Text(downloadingText(p))
                    .font(EmberType.mono(12))
                    .foregroundStyle(EmberColor.accentText)
                ZStack(alignment: .leading) {
                    Capsule().fill(EmberColor.surface).frame(height: 5)
                    Capsule().fill(EmberColor.accent).frame(width: max(4, 128 * p), height: 5)
                }
                .frame(width: 128)
            }

        case .failed:
            Button(action: onAction) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EmberColor.rec)
                    Text(locale.t("model.retry")).font(EmberType.medium(13)).foregroundStyle(EmberColor.rec)
                }
                .padding(.horizontal, 14).frame(height: 34)
                .background(EmberColor.rec.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(EmberColor.rec.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(EmberPressStyle())
            .emberHover(cornerRadius: 11)
            .transition(.opacity.combined(with: .scale(scale: 0.94)))

        case .ready:
            Button(action: onAction) {
                Text(locale.t("model.select")).font(EmberType.medium(13)).foregroundStyle(EmberColor.text)
                    .padding(.horizontal, 16).frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(EmberColor.borderStrong, lineWidth: 1))
            }
            .buttonStyle(EmberPressStyle())
            .emberHover(cornerRadius: 11)

        case .selected:
            Circle()
                .fill(EmberColor.accent)
                .frame(width: 26, height: 26)
                .overlay(EmberIcon(.check, size: 14, lineWidth: 2.6, color: .white))
        }
    }
}
