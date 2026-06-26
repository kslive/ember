import Core
import SwiftUI

/// Language selector chip (globe + native name) shown in screen headers.
/// Switches the UI language instantly.
public struct LanguageChip: View {
    @EnvironmentObject private var locale: LocaleManager

    public init() {}

    public var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button(lang.nativeName) { locale.setLanguage(lang) }
            }
        } label: {
            HStack(spacing: 7) {
                EmberIcon(.globe, size: 14, lineWidth: 1.8, color: EmberColor.text2)
                Text(locale.language.nativeName)
                    .font(EmberType.regular(13))
                    .foregroundStyle(EmberColor.text2)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(EmberColor.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .emberHover(cornerRadius: 9)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
