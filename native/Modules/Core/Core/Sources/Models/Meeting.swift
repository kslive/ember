import Foundation

/// A recorded meeting. Its transcript segments and summary are stored separately,
/// keyed by `id`.
public struct Meeting: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var durationSeconds: Double?
    public var participantCount: Int?
    public var folderPath: String?
    /// Summary template the meeting was summarized with; empty until one is applied.
    public var templateId: String

    public init(id: String = UUID().uuidString, title: String, createdAt: Date = Date(), updatedAt: Date = Date(),
                durationSeconds: Double? = nil, participantCount: Int? = nil, folderPath: String? = nil,
                templateId: String = "") {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.durationSeconds = durationSeconds
        self.participantCount = participantCount
        self.folderPath = folderPath
        self.templateId = templateId
    }
}
