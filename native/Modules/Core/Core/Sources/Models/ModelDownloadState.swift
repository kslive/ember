import Foundation

/// Download state of one catalog model (transcription or summary).
public enum ModelDownloadState: Equatable, Sendable {
    case absent
    /// Progress in 0...1.
    case downloading(Double)
    case ready
    /// Error message for the model card; may be empty.
    case failed(String)
}
