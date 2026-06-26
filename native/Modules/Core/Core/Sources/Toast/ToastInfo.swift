import Foundation

/// A transient in-app toast message.
public struct ToastInfo: Identifiable, Equatable, Sendable {
    public enum Tone: Sendable { case info, good, warn, error }
    public let id = UUID()
    public let text: String
    public let tone: Tone
    public init(_ text: String, tone: Tone = .info) {
        self.text = text
        self.tone = tone
    }

    public static func == (a: ToastInfo, b: ToastInfo) -> Bool {
        a.id == b.id
    }
}
