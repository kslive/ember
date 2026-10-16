import Foundation

/// Capture channel a transcript segment came from. Raw values are persisted.
public enum TranscriptSource: String, Codable, Sendable {
    /// The user's microphone.
    case mic
    /// System audio — the other side of the call.
    case system
    /// No channel info (e.g. segments saved before it was tracked).
    case unknown

    /// Channel tag of the live transcript timeline.
    public var tag: String? {
        switch self {
        case .mic: "[mic]"
        case .system: "[mac]"
        case .unknown: nil
        }
    }
}

/// One timed line of a meeting transcript.
public struct TranscriptSegment: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var meetingId: String
    public var text: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var source: TranscriptSource

    public init(id: String = UUID().uuidString, meetingId: String, text: String, startSeconds: Double,
                endSeconds: Double, source: TranscriptSource = .unknown) {
        self.id = id
        self.meetingId = meetingId
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.source = source
    }

    /// `mm:ss` of the segment start.
    public var timecode: String {
        Format.timecode(startSeconds)
    }
}
