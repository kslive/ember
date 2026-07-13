import Core
import DesignSystem
import SwiftUI

/// One-time post-update announcement: the GitHub release notes of the version the
/// user just updated into, rendered in the app's language. Modal over the whole app.
struct WhatsNewOverlay: View {
    let version: String
    let markdown: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { onClose() }
            card
        }
    }

    /// Sized-to-content notes body: ViewThatFits picks the plain variant while it
    /// fits under the 380pt cap (card hugs the text), else the scrolling variant.
    private var notes: some View {
        NotesMarkdown(md: markdown)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                EmberIcon(.sparkle, size: 19, lineWidth: 1.8, color: EmberColor.accentText)
                    .frame(width: 40, height: 40)
                    .background(EmberColor.accentWeak)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                Text(LocalizedStrings.current("whatsnew.title").replacingOccurrences(of: "{v}", with: version))
                    .font(EmberType.semibold(17)).tracking(-0.2)
                    .foregroundStyle(EmberColor.text)
                Spacer()
            }
            .padding(24)

            ViewThatFits(in: .vertical) {
                notes
                ScrollView { notes }.scrollIndicators(.never)
            }
            .frame(maxHeight: 380)

            Rectangle().fill(EmberColor.border).frame(height: 1)
            HStack {
                Spacer()
                EmberButton(LocalizedStrings.current("whatsnew.ok"), kind: .primary, height: 38, action: onClose)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 560)
        .background(EmberColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 70, x: 0, y: 30)
    }
}

/// Tiny renderer for release-note markdown: `##`/`###` headings, `- ` bullets,
/// inline **bold**, plain paragraphs. Enough for our notes format.
private struct NotesMarkdown: View {
    let md: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(md.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    Color.clear.frame(height: 3)
                } else if line.hasPrefix("### ") {
                    Text(inline(String(line.dropFirst(4)))).font(EmberType.semibold(13.5)).foregroundStyle(EmberColor.text).padding(.top, 5)
                } else if line.hasPrefix("## ") {
                    Text(inline(String(line.dropFirst(3)))).font(EmberType.semibold(14.5)).foregroundStyle(EmberColor.text).padding(.top, 7)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 10) {
                        Text("—").font(EmberType.regular(13.5)).foregroundStyle(EmberColor.accentText)
                        Text(inline(String(line.dropFirst(2)))).font(EmberType.regular(13.5)).lineSpacing(3).foregroundStyle(EmberColor.text2)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text(inline(line)).font(EmberType.regular(13.5)).lineSpacing(3).foregroundStyle(EmberColor.text2)
                }
            }
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
