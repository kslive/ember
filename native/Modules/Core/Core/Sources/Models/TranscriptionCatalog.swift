import Foundation

/// Speech-to-text backend a transcription model runs on.
public enum TranscriptionEngine: Hashable, Sendable {
    /// Whisper via WhisperKit (CoreML / ANE), multilingual.
    case whisperKit
    /// GigaAM v3 via sherpa-onnx, Russian only.
    case gigaAM
}

/// A downloadable speech-to-text model.
public struct TranscriptionModelSpec: Identifiable, Hashable, Sendable {
    /// Persisted in settings; for WhisperKit it is also the model variant folder name.
    public let id: String
    public let displayName: String
    /// Approximate download size; also the denominator of the download progress.
    public let sizeMB: Int
    public let ramHintGB: Int
    public let badge: ModelBadge?
    public let engine: TranscriptionEngine

    public init(id: String, displayName: String, sizeMB: Int, ramHintGB: Int, badge: ModelBadge? = nil,
                engine: TranscriptionEngine) {
        self.id = id
        self.displayName = displayName
        self.sizeMB = sizeMB
        self.ramHintGB = ramHintGB
        self.badge = badge
        self.engine = engine
    }
}

public enum TranscriptionCatalog {
    /// A titled section of the model picker (onboarding + settings).
    public struct Group: Sendable {
        public let titleKey: String
        public let models: [TranscriptionModelSpec]
    }

    public static let defaultId = "openai_whisper-large-v3_turbo"

    /// Sorted by size, ascending.
    public static let all: [TranscriptionModelSpec] = [
        TranscriptionModelSpec(id: "gigaam-v3-rnnt", displayName: "GigaAM v3", sizeMB: 230, ramHintGB: 1,
                               engine: .gigaAM),
        TranscriptionModelSpec(id: "openai_whisper-small", displayName: "Small", sizeMB: 480, ramHintGB: 1,
                               engine: .whisperKit),
        TranscriptionModelSpec(id: "openai_whisper-medium", displayName: "Medium", sizeMB: 1500, ramHintGB: 2,
                               engine: .whisperKit),
        TranscriptionModelSpec(id: "openai_whisper-large-v3_turbo", displayName: "Large V3 Turbo", sizeMB: 1600,
                               ramHintGB: 3, badge: .recommended, engine: .whisperKit)
    ]

    /// Every model of `all` sits in exactly one group.
    public static let groups: [Group] = [
        Group(titleKey: "models.group.russian", models: all.filter { $0.engine == .gigaAM }),
        Group(titleKey: "models.group.multilingual", models: all.filter { $0.engine == .whisperKit })
    ]

    public static func spec(for id: String) -> TranscriptionModelSpec? {
        all.first { $0.id == id }
    }

    /// Unknown ids are treated as WhisperKit variants.
    public static func engine(for id: String) -> TranscriptionEngine {
        spec(for: id)?.engine ?? .whisperKit
    }
}
