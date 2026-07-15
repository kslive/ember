import AppKit
import Foundation

/// Opening exported notes in Sage (the author's local AI notes app) when it is
/// installed. Deep link: `sage://open?path=<file>` — added to Sage in tandem with
/// this integration. Older Sage builds without the scheme just get activated.
public enum SageIntegration {
    public static let bundleId = "com.sage.app"

    /// Canonical install first; the LaunchServices lookup is only a fallback (e.g.
    /// ~/Applications) because LS keeps stale registrations after the app was
    /// deleted and happily returns Trash or Xcode build-folder copies. Without
    /// these guards the UI would keep showing the Sage button after Sage is gone
    /// instead of falling back to Obsidian.
    public static var appURL: URL? {
        let canonical = URL(fileURLWithPath: "/Applications/Sage.app")
        if FileManager.default.fileExists(atPath: canonical.path) { return canonical }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              FileManager.default.fileExists(atPath: url.path),
              !url.path.contains("/.Trash/"),
              !url.path.contains("/Build/Products/"),
              !url.path.contains("/DerivedData/") else { return nil }
        return url
    }

    public static var isInstalled: Bool {
        appURL != nil
    }

    /// Deep-link URL for a note path (pure, testable — query encoding included).
    /// `root` names the vault root Sage should switch its space to when the file
    /// is outside the current one — without it Sage falls back to the file's
    /// PARENT folder, which since the per-day export subfolders would be a bare
    /// date folder instead of the user's vault. Older Sage builds ignore `root`.
    public static func openURL(forPath path: String, root: String? = nil) -> URL? {
        var comps = URLComponents()
        comps.scheme = "sage"
        comps.host = "open"
        var items = [URLQueryItem(name: "path", value: path)]
        if let root, !root.isEmpty { items.append(URLQueryItem(name: "root", value: root)) }
        comps.queryItems = items
        return comps.url
    }

    public static func open(file: URL, root: String? = nil) {
        guard let sage = appURL else { return }
        if let link = openURL(forPath: file.path, root: root),
           NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
            NSWorkspace.shared.open(link)
        } else {
            NSWorkspace.shared.openApplication(at: sage, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
