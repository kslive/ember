import AppKit
import Combine
import Foundation

/// App-wide list of summary templates for the pickers. Wraps `SummaryTemplates`
/// (the pure loader) and watches the Templates folder so a `.md` dropped in by
/// hand — or edited in place — appears everywhere automatically.
@MainActor
public final class TemplateStore: ObservableObject {
    @Published public private(set) var templates: [SummaryTemplate] = []
    private var watchSource: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?

    public init() {
        reload()
        startWatching()
    }

    public func reload() {
        templates = SummaryTemplates.all()
    }

    /// Reveals the Templates folder in Finder.
    public func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([SummaryTemplates.folder()])
    }

    /// Copies a picked `.md` into the Templates folder (overwriting a same-name file).
    /// Returns the new template's id, or nil on failure / non-md.
    @discardableResult
    public func importTemplate(from url: URL) -> String? {
        guard url.pathExtension.lowercased() == "md" else { return nil }
        let dest = SummaryTemplates.folder().appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return nil }
        reload()
        return SummaryTemplates.slug(dest.deletingPathExtension().lastPathComponent)
    }

    /// Rewrites `Standard.md` from the canonical code body.
    public func restoreStandard() {
        SummaryTemplates.restoreStandard()
        reload()
    }

    public func template(id: String) -> SummaryTemplate? {
        templates.first { $0.id == id }
    }

    private func startWatching() {
        watchSource?.cancel()
        let dir = SummaryTemplates.folder()
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
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
