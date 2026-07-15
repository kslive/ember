import DesignSystem
import SwiftUI

/// Animated shimmer skeleton shaped like a summary (title, callout, sections,
/// text lines) — covers the web editor's ~1s cold start. A soft highlight sweeps
/// across the bars; colors adapt to light/dark via Ember tokens.
struct SummarySkeleton: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        shapes
            .foregroundStyle(EmberColor.surface)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: EmberColor.text.opacity(0.05), location: 0.4),
                            .init(color: EmberColor.text.opacity(0.09), location: 0.5),
                            .init(color: EmberColor.text.opacity(0.05), location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: -geo.size.width * 0.55 + phase * geo.size.width * 1.55)
                }
                .mask(shapes)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var shapes: some View {
        VStack(alignment: .leading, spacing: 13) {
            bar(width: 0.52, height: 19)
            RoundedRectangle(cornerRadius: 11)
                .frame(height: 86)
                .padding(.top, 6)
            bar(width: 0.34, height: 14).padding(.top, 12)
            bar(width: 1.0, height: 10)
            bar(width: 0.93, height: 10)
            bar(width: 0.97, height: 10)
            bar(width: 0.58, height: 10)
            bar(width: 0.28, height: 14).padding(.top, 12)
            bar(width: 0.88, height: 10)
            bar(width: 0.72, height: 10)
            Spacer(minLength: 0)
        }
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: height / 2)
                .frame(width: geo.size.width * width, height: height)
        }
        .frame(height: height)
    }
}
