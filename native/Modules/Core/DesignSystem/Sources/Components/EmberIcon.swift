import SwiftUI

/// Custom line icons drawn to exactly match the mockup's inline SVGs (lucide
/// style, 24×24 viewBox). NOT SF Symbols. Stroke + fill rendered via Canvas.
public struct EmberIcon: View {
    public enum Glyph {
        case search, home, settings, globe, mic, pause, play
        case download, check, close, chevronRight, trash, sparkle
        case lock, bolt, file, arrowRight
        case waves, copy, minus
    }

    private let glyph: Glyph
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let color: Color

    public init(_ glyph: Glyph, size: CGFloat = 16, lineWidth: CGFloat = 1.8, color: Color = EmberColor.text) {
        self.glyph = glyph
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 24.0
            let tf = CGAffineTransform(scaleX: s, y: s)
            let stroke = StrokeStyle(lineWidth: lineWidth * s, lineCap: .round, lineJoin: .round)

            func line(_ pts: [CGPoint]) {
                var p = Path()
                p.move(to: pts[0])
                for pt in pts.dropFirst() {
                    p.addLine(to: pt)
                }
                ctx.stroke(p.applying(tf), with: .color(color), style: stroke)
            }
            func ellipse(_ r: CGRect) {
                ctx.stroke(Path(ellipseIn: r).applying(tf), with: .color(color), style: stroke)
            }
            func dot(_ c: CGPoint, _ r: CGFloat) {
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect).applying(tf), with: .color(color))
            }
            func fillBar(_ rect: CGRect, _ corner: CGFloat) {
                ctx.fill(Path(roundedRect: rect, cornerRadius: corner).applying(tf), with: .color(color))
            }
            func arc(_ build: (inout Path) -> Void) {
                var p = Path(); build(&p)
                ctx.stroke(p.applying(tf), with: .color(color), style: stroke)
            }

            switch glyph {
            case .search:
                ellipse(CGRect(x: 4, y: 4, width: 14, height: 14))
                line([CGPoint(x: 16.5, y: 16.5), CGPoint(x: 21, y: 21)])

            case .home:
                line([CGPoint(x: 3, y: 10.5), CGPoint(x: 12, y: 3), CGPoint(x: 21, y: 10.5)])
                line([CGPoint(x: 5, y: 9.5), CGPoint(x: 5, y: 21), CGPoint(x: 19, y: 21), CGPoint(x: 19, y: 9.5)])

            case .settings:
                line([CGPoint(x: 4, y: 8), CGPoint(x: 20, y: 8)])
                line([CGPoint(x: 4, y: 16), CGPoint(x: 20, y: 16)])
                dot(CGPoint(x: 9, y: 8), 2.3)
                dot(CGPoint(x: 15, y: 16), 2.3)

            case .globe:
                ellipse(CGRect(x: 3, y: 3, width: 18, height: 18))
                line([CGPoint(x: 3, y: 12), CGPoint(x: 21, y: 12)])
                ellipse(CGRect(x: 8, y: 3, width: 8, height: 18))

            case .mic:
                arc { p in p.addRoundedRect(in: CGRect(x: 9, y: 2, width: 6, height: 11), cornerSize: CGSize(width: 3, height: 3)) }
                arc { p in
                    p.move(to: CGPoint(x: 5, y: 11))
                    p.addLine(to: CGPoint(x: 5, y: 12))
                    p.addQuadCurve(to: CGPoint(x: 19, y: 12), control: CGPoint(x: 12, y: 20.5))
                    p.addLine(to: CGPoint(x: 19, y: 11))
                }
                line([CGPoint(x: 12, y: 18.5), CGPoint(x: 12, y: 22)])
                line([CGPoint(x: 8.5, y: 22), CGPoint(x: 15.5, y: 22)])

            case .pause:
                fillBar(CGRect(x: 7.5, y: 5, width: 3.4, height: 14), 1.5)
                fillBar(CGRect(x: 13.1, y: 5, width: 3.4, height: 14), 1.5)

            case .play:
                var tri = Path()
                tri.move(to: CGPoint(x: 8, y: 5))
                tri.addLine(to: CGPoint(x: 19, y: 12))
                tri.addLine(to: CGPoint(x: 8, y: 19))
                tri.closeSubpath()
                ctx.fill(tri.applying(tf), with: .color(color))

            case .download:
                line([CGPoint(x: 12, y: 3), CGPoint(x: 12, y: 15)])
                line([CGPoint(x: 7, y: 11), CGPoint(x: 12, y: 16), CGPoint(x: 17, y: 11)])
                line([CGPoint(x: 4, y: 20), CGPoint(x: 20, y: 20)])

            case .check:
                line([CGPoint(x: 5, y: 12), CGPoint(x: 10, y: 17), CGPoint(x: 20, y: 6)])

            case .close:
                line([CGPoint(x: 6, y: 6), CGPoint(x: 18, y: 18)])
                line([CGPoint(x: 18, y: 6), CGPoint(x: 6, y: 18)])

            case .minus:
                line([CGPoint(x: 6, y: 12), CGPoint(x: 18, y: 12)])

            case .copy:
                arc { p in
                    p.addRoundedRect(in: CGRect(x: 9, y: 9, width: 12, height: 12),
                                     cornerSize: CGSize(width: 2, height: 2))
                }
                arc { p in
                    p.move(to: CGPoint(x: 15.5, y: 5))
                    p.addLine(to: CGPoint(x: 7, y: 5))
                    p.addQuadCurve(to: CGPoint(x: 4.5, y: 7.5), control: CGPoint(x: 4.5, y: 5))
                    p.addLine(to: CGPoint(x: 4.5, y: 15.5))
                }

            case .chevronRight:
                line([CGPoint(x: 9, y: 6), CGPoint(x: 15, y: 12), CGPoint(x: 9, y: 18)])

            case .trash:
                line([CGPoint(x: 3, y: 6), CGPoint(x: 21, y: 6)])
                line([CGPoint(x: 8, y: 6), CGPoint(x: 8, y: 4), CGPoint(x: 16, y: 4), CGPoint(x: 16, y: 6)])
                line([CGPoint(x: 18.5, y: 6), CGPoint(x: 17.5, y: 20.5), CGPoint(x: 6.5, y: 20.5), CGPoint(x: 5.5, y: 6)])
                line([CGPoint(x: 10, y: 11), CGPoint(x: 10, y: 17)])
                line([CGPoint(x: 14, y: 11), CGPoint(x: 14, y: 17)])

            case .sparkle:
                var p = Path()
                let pts: [CGPoint] = [
                    CGPoint(x: 12, y: 2.5), CGPoint(x: 13.7, y: 10.3), CGPoint(x: 21.5, y: 12), CGPoint(x: 13.7, y: 13.7),
                    CGPoint(x: 12, y: 21.5), CGPoint(x: 10.3, y: 13.7), CGPoint(x: 2.5, y: 12), CGPoint(x: 10.3, y: 10.3)
                ]
                p.move(to: pts[0])
                for pt in pts.dropFirst() {
                    p.addLine(to: pt)
                }
                p.closeSubpath()
                ctx.fill(p.applying(tf), with: .color(color))

            case .waves:
                dot(CGPoint(x: 12, y: 12), 2.4)
                arc { p in p.addArc(center: CGPoint(x: 12, y: 12), radius: 5, startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false) }
                arc { p in p.addArc(center: CGPoint(x: 12, y: 12), radius: 5, startAngle: .degrees(130), endAngle: .degrees(230), clockwise: false) }
                arc { p in p.addArc(center: CGPoint(x: 12, y: 12), radius: 9.5, startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false) }
                arc { p in p.addArc(center: CGPoint(x: 12, y: 12), radius: 9.5, startAngle: .degrees(130), endAngle: .degrees(230), clockwise: false) }

            case .lock:
                arc { p in p.addRoundedRect(in: CGRect(x: 5, y: 11, width: 14, height: 10), cornerSize: CGSize(width: 2.5, height: 2.5)) }
                arc { p in
                    p.move(to: CGPoint(x: 8, y: 11))
                    p.addLine(to: CGPoint(x: 8, y: 8))
                    p.addQuadCurve(to: CGPoint(x: 16, y: 8), control: CGPoint(x: 12, y: 2.5))
                    p.addLine(to: CGPoint(x: 16, y: 11))
                }
                dot(CGPoint(x: 12, y: 15.5), 1.5)

            case .bolt:
                var z = Path()
                let zp: [CGPoint] = [
                    CGPoint(x: 13, y: 2), CGPoint(x: 3, y: 14), CGPoint(x: 12, y: 14),
                    CGPoint(x: 11, y: 22), CGPoint(x: 21, y: 10), CGPoint(x: 12, y: 10)
                ]
                z.move(to: zp[0])
                for pt in zp.dropFirst() {
                    z.addLine(to: pt)
                }
                z.closeSubpath()
                ctx.fill(z.applying(tf), with: .color(color))

            case .file:
                arc { p in p.addRoundedRect(in: CGRect(x: 5, y: 3, width: 14, height: 18), cornerSize: CGSize(width: 2.5, height: 2.5)) }
                arc { p in
                    p.move(to: CGPoint(x: 14, y: 3))
                    p.addLine(to: CGPoint(x: 14, y: 8))
                    p.addLine(to: CGPoint(x: 19, y: 8))
                }

            case .arrowRight:
                line([CGPoint(x: 4, y: 12), CGPoint(x: 20, y: 12)])
                line([CGPoint(x: 13, y: 5), CGPoint(x: 20, y: 12), CGPoint(x: 13, y: 19)])
            }
        }
        .frame(width: size, height: size)
    }
}
