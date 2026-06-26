import Foundation

/// Pure updater logic (version compare, release selection, SHA parsing, GitHub
/// JSON decode) — no networking, fully unit-tested. Ported from the Sage app.
public enum UpdateLogic {
    /// Numeric semver comparison of "1.5.0" / "v1.5" / "1.5.0-beta.1" → -1/0/1.
    /// The prerelease suffix (after `-`) is ignored when comparing the core version.
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        func core(_ s: String) -> [Int] {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            let noV = (trimmed.hasPrefix("v") || trimmed.hasPrefix("V")) ? String(trimmed.dropFirst()) : trimmed
            let base = noV.split(separator: "-", maxSplits: 1).first.map(String.init) ?? noV
            return base.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let x = core(a), y = core(b)
        for i in 0 ..< max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    /// Is `candidate` strictly newer than `current`?
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compareVersions(candidate, current) > 0
    }

    /// True if a version tag actually parses to a number (its base segment contains a
    /// digit). A typo'd/non-numeric tag ("latest", "l.3.0") otherwise compares as 0 →
    /// silently "older than everything" → a real update would never be offered.
    public static func isParseableVersion(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let noV = (trimmed.hasPrefix("v") || trimmed.hasPrefix("V")) ? String(trimmed.dropFirst()) : trimmed
        let base = noV.split(separator: "-", maxSplits: 1).first.map(String.init) ?? noV
        return base.contains(where: \.isNumber)
    }

    /// Newest release matching the channel that is strictly newer than `current` (else nil).
    /// stable → non-prerelease only; beta → any (including prerelease).
    public static func pickUpdate(from releases: [UpdateRelease], current: String,
                                  channel: UpdateChannel) -> UpdateRelease? {
        releases
            .filter { channel == .beta || !$0.isPrerelease }
            .filter { isParseableVersion($0.version) }
            .filter { isNewer($0.version, than: current) }
            .max { compareVersions($0.version, $1.version) < 0 }
    }

    /// Extract a SHA-256 (exactly 64 hex) from text. Prefers a labelled "SHA256: <hash>"
    /// form; falls back to a standalone 64-hex token bounded by non-hex so a longer hex
    /// run is REJECTED (returns nil) rather than truncated to its first 64 chars.
    public static func sha256(fromNotes notes: String) -> String? {
        let ns = notes as NSString
        if let re = try? NSRegularExpression(pattern: "sha-?256[^a-fA-F0-9\\n]{0,8}([a-fA-F0-9]{64})(?![a-fA-F0-9])",
                                             options: [.caseInsensitive]),
            let m = re.firstMatch(in: notes, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
            return ns.substring(with: m.range(at: 1)).lowercased()
        }
        if let r = notes.range(of: "(?<![a-fA-F0-9])[a-fA-F0-9]{64}(?![a-fA-F0-9])", options: .regularExpression) {
            return String(notes[r]).lowercased()
        }
        return nil
    }

    /// Decode GitHub `/releases` JSON → `[UpdateRelease]` (zip asset + optional `.sha256` sidecar).
    public static func decodeGitHubReleases(_ data: Data) throws -> [UpdateRelease] {
        let raw = try JSONDecoder().decode([GHRelease].self, from: data)
        let iso = ISO8601DateFormatter()
        return raw.compactMap { r in
            guard let zip = r.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
                  let url = URL(string: zip.browser_download_url) else { return nil }
            let shaAsset = r.assets.first { $0.name.lowercased().hasSuffix(".sha256") }
            let shaFromNotes = sha256(fromNotes: r.body ?? "")
            let shaURL = shaAsset.flatMap { URL(string: $0.browser_download_url) }
            guard shaFromNotes != nil || shaURL != nil else { return nil }
            let version = (r.tag_name.hasPrefix("v") || r.tag_name.hasPrefix("V"))
                ? String(r.tag_name.dropFirst()) : r.tag_name
            return UpdateRelease(
                version: version,
                notes: r.body ?? "",
                downloadURL: url,
                sha256: shaFromNotes,
                sha256AssetURL: shaURL,
                sizeBytes: zip.size,
                publishedAt: r.published_at.flatMap { iso.date(from: $0) },
                isPrerelease: r.prerelease
            )
        }
    }

    /// Throttle helper: should a background check run given the last check time?
    public static func shouldCheck(last: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let body: String?
        let prerelease: Bool
        let published_at: String?
        let assets: [GHAsset]
    }

    private struct GHAsset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
    }
}
