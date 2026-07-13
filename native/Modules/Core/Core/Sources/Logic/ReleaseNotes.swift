import Foundation

/// Extracts the app-language section from a GitHub release body. Ember release notes
/// are trilingual (`## 🇬🇧 English — …`, `## 🇷🇺 Русский — …`, `## 🇨🇳 中文 — …`)
/// with a shared `---` footer (install hint + SHA256) that users don't need to see.
public enum ReleaseNotes {
    /// Language markers accepted in a `## ` section heading.
    private static func markers(for language: AppLanguage) -> [String] {
        switch language {
        case .en: ["🇬🇧", "English"]
        case .ru: ["🇷🇺", "Русск"]
        case .zh: ["🇨🇳", "中文"]
        }
    }

    private static let allMarkers = ["🇬🇧", "English", "🇷🇺", "Русск", "🇨🇳", "中文"]

    /// The localized section of the notes (footer stripped). Falls back to the whole
    /// stripped body when the language sections aren't found (non-trilingual notes).
    public static func localizedSection(_ body: String, language: AppLanguage) -> String {
        let stripped = stripFooter(body)
        let lines = stripped.components(separatedBy: "\n")
        let wanted = markers(for: language)

        var collected: [String] = []
        var inSection = false
        for line in lines {
            let isHeading = line.hasPrefix("## ")
            if isHeading, wanted.contains(where: { line.contains($0) }) {
                inSection = true
                continue
            }
            if isHeading, allMarkers.contains(where: { line.contains($0) }) {
                if inSection { break }
                continue
            }
            if inSection { collected.append(line) }
        }
        let section = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? stripped : section
    }

    /// Drops everything from the LAST `---` separator (install hint, SHA256 line).
    static func stripFooter(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        if let cut = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            return lines[..<cut].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
