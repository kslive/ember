import Foundation

/// An action item of a summary.
public struct SummaryTask: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var text: String
    public var assignee: String?

    public init(id: String = UUID().uuidString, text: String, assignee: String? = nil) {
        self.id = id
        self.text = text
        self.assignee = assignee
    }
}

/// A meeting's summary: the Markdown document plus its structured parts.
public struct MeetingSummary: Hashable, Codable, Sendable {
    public var tldr: String
    public var decisions: [String]
    public var tasks: [SummaryTask]
    public var markdown: String
    /// Set when the user edited the summary by hand; nil for a generated one.
    public var editedAt: Date?

    public init(tldr: String = "", decisions: [String] = [], tasks: [SummaryTask] = [], markdown: String = "",
                editedAt: Date? = nil) {
        self.tldr = tldr
        self.decisions = decisions
        self.tasks = tasks
        self.markdown = markdown
        self.editedAt = editedAt
    }
}
