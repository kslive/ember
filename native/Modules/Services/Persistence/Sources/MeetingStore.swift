import Combine
import Core
import Foundation
import GRDB

/// SQLite-backed store (GRDB) for meetings, transcripts and summaries.
@MainActor
public final class MeetingStore: ObservableObject {
    @Published public private(set) var meetings: [Meeting] = []
    /// True when the on-disk database couldn't be opened and we fell back to a
    /// volatile store — meetings won't survive a relaunch. Surfaced to the user.
    @Published public private(set) var persistenceDegraded = false

    private let dbQueue: DatabaseQueue

    public init(inMemory: Bool = false) {
        let (queue, degraded) = Self.openQueue(inMemory: inMemory)
        dbQueue = queue
        persistenceDegraded = degraded
        try? migrate()
        reload()
    }

    /// Opens the database without ever trapping: disk → unique temp file → in-memory.
    /// Returns whether we ended up in a degraded (non-persistent) state.
    private static func openQueue(inMemory: Bool) -> (DatabaseQueue, Bool) {
        if !inMemory {
            let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Ember", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let q = try? DatabaseQueue(path: dir.appendingPathComponent("ember.sqlite").path) { return (q, false) }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ember-\(UUID().uuidString).sqlite").path
            if let q = try? DatabaseQueue(path: tmp) { return (q, true) }
        }
        guard let q = try? DatabaseQueue() else { fatalError("Ember: cannot open any SQLite database") }
        return (q, !inMemory)
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "meeting") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
                t.column("duration", .double)
                t.column("participants", .integer)
                t.column("folderPath", .text)
            }
            try db.create(table: "segment") { t in
                t.column("id", .text).primaryKey()
                t.column("meetingId", .text).notNull().indexed()
                t.column("text", .text).notNull()
                t.column("startSeconds", .double).notNull()
                t.column("endSeconds", .double).notNull()
                t.column("idx", .integer).notNull()
            }
            try db.create(table: "summary") { t in
                t.column("meetingId", .text).primaryKey()
                t.column("tldr", .text).notNull()
                t.column("decisions", .text).notNull()
                t.column("tasks", .text).notNull()
                t.column("markdown", .text).notNull()
            }
        }
        migrator.registerMigration("v2-segment-source") { db in
            try db.alter(table: "segment") { t in
                t.add(column: "source", .text).notNull().defaults(to: "unknown")
            }
        }
        migrator.registerMigration("v3-segment-speaker") { db in
            try db.alter(table: "segment") { t in
                t.add(column: "speaker", .integer).notNull().defaults(to: 0)
            }
        }
        try migrator.migrate(dbQueue)
    }

    public func reload() {
        let rows = (try? dbQueue.read { db in
            try MeetingRow.order(Column("createdAt").desc).fetchAll(db)
        }) ?? []
        meetings = rows.map(\.model)
    }

    public func upsert(_ meeting: Meeting) {
        try? dbQueue.write { db in try MeetingRow(meeting).save(db) }
        reload()
    }

    public func rename(_ id: String, title: String) {
        try? dbQueue.write { db in
            try db.execute(sql: "UPDATE meeting SET title = ?, updatedAt = ? WHERE id = ?",
                           arguments: [title, Date().timeIntervalSince1970, id])
        }
        reload()
    }

    public func delete(_ id: String) {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM meeting WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM segment WHERE meetingId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM summary WHERE meetingId = ?", arguments: [id])
        }
        reload()
    }

    public func saveTranscript(meetingId: String, segments: [TranscriptSegment]) {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM segment WHERE meetingId = ?", arguments: [meetingId])
            for (i, s) in segments.enumerated() {
                try SegmentRow(s, idx: i).insert(db)
            }
        }
    }

    public func transcript(meetingId: String) -> [TranscriptSegment] {
        let rows = (try? dbQueue.read { db in
            try SegmentRow.filter(Column("meetingId") == meetingId).order(Column("idx")).fetchAll(db)
        }) ?? []
        return rows.map(\.model)
    }

    public func saveSummary(meetingId: String, summary: MeetingSummary) {
        try? dbQueue.write { db in try SummaryRow(meetingId: meetingId, summary).save(db) }
    }

    public func summary(meetingId: String) -> MeetingSummary? {
        let row = try? dbQueue.read { db in
            try SummaryRow.filter(key: meetingId).fetchOne(db)
        }
        return row?.model
    }

    /// One-time cleanup of the old demo/sample meetings (id prefix `demo-`) that earlier
    /// builds seeded on first launch. A real install must start empty.
    public func purgeDemo() {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM segment WHERE meetingId LIKE 'demo-%'")
            try db.execute(sql: "DELETE FROM summary WHERE meetingId LIKE 'demo-%'")
            try db.execute(sql: "DELETE FROM meeting WHERE id LIKE 'demo-%'")
        }
        reload()
    }
}

private struct MeetingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting"
    var id: String
    var title: String
    var createdAt: Double
    var updatedAt: Double
    var duration: Double?
    var participants: Int?
    var folderPath: String?

    init(_ m: Meeting) {
        id = m.id; title = m.title
        createdAt = m.createdAt.timeIntervalSince1970
        updatedAt = m.updatedAt.timeIntervalSince1970
        duration = m.durationSeconds
        participants = m.participantCount
        folderPath = m.folderPath
    }

    var model: Meeting {
        Meeting(id: id, title: title,
                createdAt: Date(timeIntervalSince1970: createdAt),
                updatedAt: Date(timeIntervalSince1970: updatedAt),
                durationSeconds: duration, participantCount: participants, folderPath: folderPath)
    }
}

private struct SegmentRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "segment"
    var id: String
    var meetingId: String
    var text: String
    var startSeconds: Double
    var endSeconds: Double
    var idx: Int
    var source: String
    var speaker: Int

    init(_ s: TranscriptSegment, idx: Int) {
        id = s.id; meetingId = s.meetingId; text = s.text
        startSeconds = s.startSeconds; endSeconds = s.endSeconds; self.idx = idx
        source = s.source.rawValue
        speaker = s.speaker
    }

    var model: TranscriptSegment {
        TranscriptSegment(id: id, meetingId: meetingId, text: text, startSeconds: startSeconds, endSeconds: endSeconds,
                          source: TranscriptSource(rawValue: source) ?? .unknown, speaker: speaker)
    }
}

private struct SummaryRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "summary"
    var meetingId: String
    var tldr: String
    var decisions: String
    var tasks: String
    var markdown: String

    init(meetingId: String, _ s: MeetingSummary) {
        self.meetingId = meetingId
        tldr = s.tldr
        decisions = (try? String(data: JSONEncoder().encode(s.decisions), encoding: .utf8) ?? "[]") ?? "[]"
        tasks = (try? String(data: JSONEncoder().encode(s.tasks), encoding: .utf8) ?? "[]") ?? "[]"
        markdown = s.markdown
    }

    var model: MeetingSummary {
        let dec = (try? JSONDecoder().decode([String].self, from: Data(decisions.utf8))) ?? []
        let tsk = (try? JSONDecoder().decode([SummaryTask].self, from: Data(tasks.utf8))) ?? []
        return MeetingSummary(tldr: tldr, decisions: dec, tasks: tsk, markdown: markdown)
    }
}
