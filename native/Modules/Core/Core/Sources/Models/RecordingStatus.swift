import Foundation

/// Lifecycle of the recording engine.
public enum RecordingStatus: String, Codable, Sendable {
    case idle
    case starting
    case recording
    case paused
    case completed
}
