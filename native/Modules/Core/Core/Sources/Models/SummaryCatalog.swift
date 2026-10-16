import Foundation

/// A local summary LLM: an MLX 4-bit conversion fetched from Hugging Face into
/// `ModelPaths.mlxModelDir(repoId)`.
public struct SummaryModelSpec: Identifiable, Hashable, Sendable {
    /// Persisted in settings (e.g. "qwen3:4b-2507").
    public let id: String
    public let repoId: String
    public let displayName: String
    /// Approximate download size; also the denominator of the download progress.
    public let sizeMB: Int
    public let contextTokens: Int
    /// Physical RAM the model needs; summaries refuse to load it on smaller Macs.
    public let ramHintGB: Int
    public let badge: ModelBadge?
    /// Localization key of a short note prepended to the card description.
    public let noteKey: String?

    public init(id: String, repoId: String, displayName: String, sizeMB: Int, contextTokens: Int, ramHintGB: Int,
                badge: ModelBadge? = nil, noteKey: String? = nil) {
        self.id = id
        self.repoId = repoId
        self.displayName = displayName
        self.sizeMB = sizeMB
        self.contextTokens = contextTokens
        self.ramHintGB = ramHintGB
        self.badge = badge
        self.noteKey = noteKey
    }
}

public enum SummaryCatalog {
    /// A titled section of the model picker (onboarding + settings).
    public struct Group: Sendable {
        public let titleKey: String
        public let models: [SummaryModelSpec]
    }

    public static let defaultId = "qwen3:4b-2507"

    /// Sorted by size and by RAM, ascending.
    public static let all: [SummaryModelSpec] = [
        SummaryModelSpec(id: "qwen3:1.7b-dwq", repoId: "mlx-community/Qwen3-1.7B-4bit-DWQ", displayName: "Qwen3 1.7B DWQ",
                         sizeMB: 1000, contextTokens: 40960, ramHintGB: 8, noteKey: "model.dwq.desc"),
        SummaryModelSpec(id: "qwen3:1.7b", repoId: "mlx-community/Qwen3-1.7B-4bit", displayName: "Qwen3 1.7B",
                         sizeMB: 1050, contextTokens: 40960, ramHintGB: 8),
        SummaryModelSpec(id: "qwen3:4b-2507", repoId: "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510",
                         displayName: "Qwen3 4B Instruct", sizeMB: 2300, contextTokens: 40960, ramHintGB: 8,
                         badge: .recommended, noteKey: "model.qwen2507.desc"),
        SummaryModelSpec(id: "qwen3:4b", repoId: "mlx-community/Qwen3-4B-4bit", displayName: "Qwen3 4B",
                         sizeMB: 2400, contextTokens: 40960, ramHintGB: 8),
        SummaryModelSpec(id: "qwen3:8b-dwq", repoId: "mlx-community/Qwen3-8B-4bit-DWQ", displayName: "Qwen3 8B DWQ",
                         sizeMB: 4650, contextTokens: 40960, ramHintGB: 16, badge: .balanced, noteKey: "model.dwq.desc"),
        SummaryModelSpec(id: "qwen3:8b", repoId: "mlx-community/Qwen3-8B-4bit", displayName: "Qwen3 8B",
                         sizeMB: 4700, contextTokens: 40960, ramHintGB: 16)
    ]

    /// Every model of `all` sits in exactly one group (by size class).
    public static let groups: [Group] = [
        Group(titleKey: "models.group.light", models: all.filter { $0.id.hasPrefix("qwen3:1.7b") }),
        Group(titleKey: "models.group.standard", models: all.filter { $0.id.hasPrefix("qwen3:4b") }),
        Group(titleKey: "models.group.max", models: all.filter { $0.id.hasPrefix("qwen3:8b") })
    ]

    public static func spec(for id: String) -> SummaryModelSpec? {
        all.first { $0.id == id }
    }
}
