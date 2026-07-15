import AppKit
import Core
import Foundation

/// State of the live summary editor for the CURRENTLY open meeting. Lives on
/// AppModel (one instance app-wide), NOT in view @State — the detail container
/// re-creates its views on every `revision` bump and would wipe in-progress
/// typing.
///
/// Save pipeline: every edit re-arms ONE 0.8s debounce that persists to the DB
/// and re-writes the exported .md (via `onSave`) — Sage/Obsidian watch that file
/// and update live. Inbound: a directory watcher on the meeting's date folder
/// picks up external edits (directory-level events survive atomic replace-by-
/// rename); the file wins ONLY when the local buffer has no unsaved typing.
/// Because the DB is written before the file, our own write echoes back as
/// body == text and is ignored — no hash bookkeeping needed.
@MainActor
public final class SummaryEditorModel: ObservableObject {
    @Published public var text = "" {
        didSet {
            guard !suppressDidSet, text != lastSaved else { return }
            scheduleSave()
        }
    }

    public let controller = SummaryEditorController()
    public private(set) var meetingId: String?
    /// Which meeting has finished its post-open "settle" window: even a WARM
    /// webview repaints/measures a freshly pushed document for ~0.5s (black flash,
    /// layout jumps) — the skeleton covers that window on every open. Lives here,
    /// not in view @State, so container churn can't re-trigger the shimmer.
    @Published public var settledId: String?
    /// The user touched this meeting's summary at least once this session —
    /// drives the regenerate-over-edits confirmation before the DB row's
    /// `editedAt` has round-tripped through a container reload.
    public private(set) var everEdited = false
    /// Debounced write-through: (meetingId, markdown) → DB + export file.
    public var onSave: ((String, String) -> Void)?

    private var fileURL: URL?
    private var lastSaved = ""
    private var suppressDidSet = false
    private var saveTask: Task<Void, Never>?
    private var watchSource: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?
    private var quitObserver: NSObjectProtocol?

    public var dirty: Bool {
        text != lastSaved
    }

    public init() {
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushNow() }
        }
    }

    /// Binds the editor to a meeting's summary. Same meeting + unchanged DB text
    /// → keep the live buffer (container reloads must not clobber typing).
    /// Same meeting + CHANGED DB text → the DB wins (a regenerate just landed;
    /// the UI gates that path, so a pending draft is discarded deliberately).
    /// Different meeting → flush the old draft first, then adopt.
    public func open(meetingId id: String, markdown: String, fileURL url: URL?) {
        if meetingId == id, markdown == lastSaved {
            fileURL = url
            rebuildWatcher()
            return
        }
        if meetingId == id {
            saveTask?.cancel()
        } else {
            flushNow()
            everEdited = false
            controller.beginSwitch()
        }
        meetingId = id
        fileURL = url
        settledId = nil
        adopt(markdown)
        rebuildWatcher()
    }

    /// Writes any pending edit immediately (meeting switch, app quit, opening
    /// the file in Sage/Obsidian).
    public func flushNow() {
        saveTask?.cancel()
        guard let meetingId, dirty else { return }
        lastSaved = text
        onSave?(meetingId, text)
    }

    public func closeCurrent() {
        flushNow()
        watchSource?.cancel()
        watchSource = nil
        meetingId = nil
        fileURL = nil
    }

    private func adopt(_ markdown: String) {
        suppressDidSet = true
        lastSaved = markdown
        text = markdown
        suppressDidSet = false
    }

    private func scheduleSave() {
        everEdited = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.flushNow()
        }
    }

    /// Watches the date FOLDER (not the file: Sage/Ember replace files by rename,
    /// which churns the file's inode and silently kills a file-level watcher).
    private func rebuildWatcher() {
        watchSource?.cancel()
        watchSource = nil
        guard let dir = fileURL?.deletingLastPathComponent() else { return }
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchSource = src
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadFromFile() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Inbound external edit: adopt the file body only when it genuinely differs
    /// and the local buffer is clean — unsaved typing always wins over the file.
    /// Adopting via `text` re-arms the save, which persists the file's content
    /// into the DB and re-echoes to the file (a no-op next event).
    private func reloadFromFile() {
        guard let fileURL, meetingId != nil, !dirty,
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let body = SummaryExport.stripFrontMatter(content)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty,
              trimmedBody != text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        text = trimmedBody
    }
}
