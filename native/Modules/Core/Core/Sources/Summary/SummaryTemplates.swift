import Foundation

/// A user-selectable summary template: a `.md` file with a small YAML header
/// (`name`, `description`) plus a body that IS the system prompt (structure +
/// rules). The body carries its own language handling via the `{{LANGUAGE}}`
/// token, replaced with the transcript's language before use — nothing else is
/// appended. Self-contained, mirroring the shipped `SummaryPrompts` form.
public struct SummaryTemplate: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let body: String
    public let isStandard: Bool
    public let fileURL: URL?

    public init(id: String, name: String, description: String, body: String,
                isStandard: Bool = false, fileURL: URL? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.body = body
        self.isStandard = isStandard
        self.fileURL = fileURL
    }
}

/// Loads / seeds / renders summary templates stored as `.md` files under
/// `Application Support/Ember/Templates`. Pure file + string processing — the
/// pipeline reads a rendered system prompt by id, the UI lists all templates.
public enum SummaryTemplates {
    public static let standardId = "standard"
    public static let placeholder = "{{LANGUAGE}}"

    public static func folder() -> URL {
        let dir = ModelPaths.appSupport().appendingPathComponent("Templates", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Serializes a template file: YAML header + body.
    public static func fileContent(name: String, description: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body)
        """
    }

    /// Parses a template file. `name`/`description` come from the YAML header (falling
    /// back to the filename / empty); the body is everything after the header.
    public static func parse(_ content: String, fallbackName: String) -> (name: String, description: String, body: String) {
        var name = fallbackName
        var description = ""
        var body = content
        if content.hasPrefix("---\n"), let end = content.dropFirst(4).range(of: "\n---\n") {
            let header = String(content.dropFirst(4)[..<end.lowerBound])
            body = String(content.dropFirst(4)[end.upperBound...])
            for line in header.components(separatedBy: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if key == "name", !value.isEmpty { name = value }
                if key == "description" { description = value }
            }
        }
        return (name, description, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Rewrites `Standard.md` from the built-in body for the current app language.
    @discardableResult
    public static func restoreStandard() -> URL? {
        let v = standardBuiltin.variant(for: AppLanguage.current)
        let url = folder().appendingPathComponent(standardBuiltin.file)
        let content = fileContent(name: v.name, description: v.description, body: v.body)
        return (try? content.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    /// All templates in the folder, sorted with Standard first then by name. The id
    /// is the lowercased file stem ("standard", "protokol-vstrechi", …).
    public static func all() -> [SummaryTemplate] {
        seedBuiltins(for: AppLanguage.current)
        let dir = folder()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "md" } ?? []
        let templates = files.compactMap { url -> SummaryTemplate? in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            let id = slug(stem)
            let parsed = parse(content, fallbackName: stem)
            return SummaryTemplate(id: id, name: parsed.name, description: parsed.description,
                                   body: parsed.body, isStandard: id == standardId, fileURL: url)
        }
        return templates.sorted { a, b in
            if a.isStandard != b.isStandard { return a.isStandard }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public static func template(id: String) -> SummaryTemplate? {
        all().first { $0.id == id }
    }

    /// Rendered system prompt for the pipeline: the chosen template's body with
    /// `{{LANGUAGE}}` filled in with the transcript's language. Returns nil when the
    /// id is unknown / unreadable so the caller falls back to the code default
    /// (`SummaryPrompts.system`) — a summary never fails because of a broken file.
    public static func renderedSystem(id: String, languageCode: String) -> String? {
        guard let t = template(id: id), !t.body.isEmpty else { return nil }
        return t.body.replacingOccurrences(of: placeholder, with: languageName(languageCode))
    }

    /// English name of the language for the `{{LANGUAGE}}` token. The app offers
    /// only ru/en/zh, so those are the only cases; anything else writes in English.
    static func languageName(_ code: String) -> String {
        switch code.prefix(2) {
        case "ru": "Russian"
        case "zh": "Chinese"
        default: "English"
        }
    }

    /// Filename stem → stable id: lowercased, spaces/punctuation → "-".
    static func slug(_ stem: String) -> String {
        let lowered = stem.lowercased()
        let mapped = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "template" : collapsed
    }
}
