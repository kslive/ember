import Foundation

/// Writes a meeting summary to disk as an Obsidian-flavoured `.md` file in the
/// user-chosen export folder (mirrors the old Tauri auto-export behavior).
public enum SummaryExport {
    /// YAML front-matter + markdown body (same shape as the Obsidian export).
    public static func frontMatter(markdown: String, title _: String, createdAt: Date, typeLabel: String) -> String {
        let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        let yaml = """
        ---
        date: \(d.string(from: createdAt))
        time: "\(t.string(from: createdAt))"
        device: "Mac"
        type: "\(typeLabel)"
        tags: [meeting]
        ---

        """
        return yaml + markdown + "\n"
    }

    /// Inverse of `frontMatter`: the markdown body of an exported file (used by the
    /// live editor's inbound sync — an external edit in Sage/Obsidian is compared
    /// and adopted WITHOUT its YAML header). Files without front matter pass through.
    public static func stripFrontMatter(_ content: String) -> String {
        guard content.hasPrefix("---\n") else { return content }
        let rest = content.dropFirst(4)
        guard let r = rest.range(of: "\n---\n") else { return content }
        return String(rest[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Per-day subfolder inside the export root: `dd.MM.yyyy` ("01.02.2026") —
    /// meetings group by date instead of piling into one flat list.
    public static func dateFolder(createdAt: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"
        return f.string(from: createdAt)
    }

    /// `<title>.md` — the date lives in the per-day folder, so the file name no
    /// longer repeats it; falls back to `HH-mm.md` when the title is empty.
    public static func fileName(title: String, createdAt: Date) -> String {
        let safe = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !safe.isEmpty { return "\(String(safe.prefix(100))).md" }
        let f = DateFormatter(); f.dateFormat = "HH-mm"
        return f.string(from: createdAt) + ".md"
    }

    /// Writes the summary to `<folder>/<dd.MM.yyyy>/` (the folder itself is the one
    /// chosen in Settings) and returns the file URL (nil on failure / empty input).
    @discardableResult
    public static func write(markdown: String, title: String, createdAt: Date,
                             typeLabel: String, folder: String) -> URL? {
        guard !folder.isEmpty, !markdown.isEmpty else { return nil }
        let dir = URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent(dateFolder(createdAt: createdAt), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(title: title, createdAt: createdAt))
        let content = frontMatter(markdown: markdown, title: title, createdAt: createdAt, typeLabel: typeLabel)
        do { try content.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}
