import Foundation

/// Post-recording pipeline stage shown on a meeting while it is being processed.
public enum ProcessingStage: String, Sendable {
    /// Waiting for the calls to end (deferred processing).
    case queued
    case transcribe
    case summarize

    public var titleKey: String {
        "processing.stage.\(rawValue)"
    }

    /// The stages a finished recording runs through, in order.
    public static func plan(summarize: Bool) -> [ProcessingStage] {
        var stages: [ProcessingStage] = [.transcribe]
        if summarize { stages.append(.summarize) }
        return stages
    }
}

/// The current stage plus "step N of total" for the processing indicator.
public struct ProcessingProgress: Equatable, Sendable {
    public let stage: ProcessingStage
    public let step: Int
    public let total: Int

    public init(stage: ProcessingStage, step: Int, total: Int) {
        self.stage = stage
        self.step = step
        self.total = total
    }
}
