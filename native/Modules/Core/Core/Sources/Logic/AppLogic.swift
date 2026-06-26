import Foundation

public enum MeetingSearch {
    /// Filters meetings by a free-text query, matching the title OR the start
    /// time (`HH:mm`). An empty/whitespace query returns everything.
    public static func filter(_ meetings: [Meeting], query: String, language: AppLanguage) -> [Meeting] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return meetings }
        let looksLikeTime = q.contains(":") || (q.count >= 2 && q.allSatisfy(\.isNumber))
        return meetings.filter {
            $0.title.lowercased().contains(q)
                || (looksLikeTime && Format.clock($0.createdAt, language: language).contains(q))
        }
    }
}

public enum Nav {
    /// Next selection index when pressing ↑/↓ in a list of `count` items.
    /// `nil` current → first row; otherwise clamps to the bounds (no wrap).
    public static func adjacentIndex(count: Int, current: Int?, delta: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        return max(0, min(count - 1, current + delta))
    }
}

public enum LiveMerge {
    /// Folds a freshly-transcribed tail into the running transcript: every
    /// segment except the last is *confirmed* (locked); the last stays a live
    /// hypothesis. `fresh` timecodes must already be offset onto the timeline.
    /// Returns the new confirmed list, the full live list to display, and the
    /// updated confirmed-sample boundary.
    public static func apply(
        confirmed: [TranscriptSegment],
        fresh: [TranscriptSegment],
        confirmedSamples: Int,
        totalSamples: Int,
        sampleRate: Double = 16000
    ) -> (confirmed: [TranscriptSegment], live: [TranscriptSegment], confirmedSamples: Int) {
        guard !fresh.isEmpty else { return (confirmed, confirmed, confirmedSamples) }
        var conf = confirmed
        var cs = confirmedSamples
        if fresh.count > 1 {
            let toConfirm = fresh.dropLast()
            conf.append(contentsOf: toConfirm)
            if let lastEnd = toConfirm.last?.endSeconds {
                cs = min(totalSamples, Int(lastEnd * sampleRate))
            }
        }
        let live = conf + [fresh[fresh.count - 1]]
        return (conf, live, cs)
    }
}

public enum TranscriptMerge {
    /// Merges the separately-transcribed mic and system segments into one timeline
    /// and drops near-duplicates. Without headphones the mic picks up the speaker
    /// output (acoustic bleed), so the same speech is transcribed by BOTH passes —
    /// this collapses those duplicates while keeping genuinely distinct, simultaneous
    /// speech (different words at the same time) and short repeated backchannels.
    ///
    /// A segment is a duplicate of an already-kept one when their starts are within
    /// `window` seconds AND their word sets overlap by ≥ `threshold` (Jaccard). Only
    /// segments with ≥ `minWords` words are eligible (short "да"/"раз" never collapse).
    /// Time-ordered interleave of mic + system WITHOUT dedup — for the LIVE monitor.
    /// Live must always SHOW both channels ([mic] = me, [mac] = the other side) so the
    /// user can see the mic is capturing; without headphones the mic picks up speaker
    /// bleed and the dedup in `merge` would otherwise (non-deterministically, via the
    /// unstable equal-timestamp sort) drop the mic copy and leave only [mac]. The FINAL
    /// transcript still uses `merge` (dedup) for a clean saved result.
    public static func interleave(mic: [TranscriptSegment], system: [TranscriptSegment]) -> [TranscriptSegment] {
        (mic + system).sorted { $0.startSeconds < $1.startSeconds }
    }

    public static func merge(
        mic: [TranscriptSegment],
        system: [TranscriptSegment],
        window: Double = 6,
        threshold: Double = 0.6,
        minWords: Int = 3
    ) -> [TranscriptSegment] {
        let all = (mic + system).sorted { $0.startSeconds < $1.startSeconds }
        var kept: [TranscriptSegment] = []
        var keptInfo: [(start: Double, tokens: Set<String>)] = []
        for seg in all {
            let tokens = tokenize(seg.text)
            if tokens.count >= minWords {
                var isDup = false
                for info in keptInfo.reversed() {
                    if seg.startSeconds - info.start > window { break }
                    if info.tokens.count >= minWords, jaccard(tokens, info.tokens) >= threshold {
                        isDup = true; break
                    }
                }
                if isDup { continue }
            }
            kept.append(seg)
            keptInfo.append((seg.startSeconds, tokens))
        }
        return kept
    }

    /// Lowercased alphanumeric word set (handles Latin + Cyrillic; punctuation/markers
    /// like `*звук сцены*` reduce to their words so bleed pairs still match).
    static func tokenize(_ s: String) -> Set<String> {
        var current = ""
        var words: Set<String> = []
        for scalar in s.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.insert(current); current = ""
            }
        }
        if !current.isEmpty { words.insert(current) }
        return words
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let inter = a.intersection(b).count
        let uni = a.union(b).count
        return uni == 0 ? 0 : Double(inter) / Double(uni)
    }
}

public enum SummaryMarkdown {
    /// The AI-generated meeting name = first `# ` heading of the summary markdown.
    public static func extractTitle(_ md: String) -> String? {
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") {
                let t = String(line.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: " #*_\""))
                return t.isEmpty ? nil : String(t.prefix(80))
            }
        }
        return nil
    }

    /// Generic titles the model falls back to when it can't find a real topic — we
    /// reject these and derive a better title from the TL;DR instead.
    private static let genericTitles: Set<String> = [
        "анализ встречи", "встреча", "совещание", "созвон", "обсуждение", "планёрка", "планерка",
        "новая запись", "запись", "заметка", "встреча прошла успешно", "успешная встреча", "успешно",
        "текущее состояние", "итог встречи", "итоги встречи",
        "meeting", "discussion", "sync", "standup", "stand-up", "catch-up", "catch up", "weekly",
        "call", "notes", "new recording", "recording", "successful meeting", "meeting went well",
        "the meeting went well", "current status", "meeting summary",
        "会议", "讨论", "同步会", "站会", "例会", "新录音", "会议顺利", "成功的会议", "当前状态", "会议纪要"
    ]

    /// Filler stems: a title containing any of these is boilerplate, not a topic.
    private static let fillerStems = ["прошла успешно", "прошло успешно", "успешн", "went well",
                                      "successful", "текущее состояни", "current status", "顺利", "成功"]

    private static func isGeneric(_ title: String) -> Bool {
        let norm = title.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!:·-—\""))
        if genericTitles.contains(norm) { return true }
        return fillerStems.contains { norm.contains($0) }
    }

    /// First sentence/clause of the `> [!tip]` TL;DR callout, trimmed to a title-sized phrase.
    public static func tldrTitle(_ md: String) -> String? {
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("> [!tip]") else { continue }
            var body = String(line.dropFirst("> [!tip]".count))
            if let r = body.range(of: "tl;dr", options: .caseInsensitive) { body = String(body[r.upperBound...]) }
            body = body.trimmingCharacters(in: CharacterSet(charactersIn: " :—-"))
            let firstSentence = body.split(whereSeparator: { ".!?".contains($0) }).first.map(String.init) ?? body
            let words = firstSentence.split(separator: " ").prefix(8).joined(separator: " ")
            let t = words.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : String(t.prefix(64))
        }
        return nil
    }

    /// Best meeting title: the `# ` heading unless it's generic/missing, in which case
    /// fall back to a phrase from the TL;DR.
    public static func title(from md: String) -> String? {
        if let h1 = extractTitle(md), !isGeneric(h1) { return h1 }
        if let tldr = tldrTitle(md), !isGeneric(tldr) { return tldr }
        return extractTitle(md)
    }
}

public enum SummarySanitize {
    /// Drops bullets that duplicate an earlier bullet anywhere in the document, then
    /// removes section headings (`## …` and non-tip `> [!…]` callouts) left with no
    /// content — so the same restated line can't appear across five sections.
    public static func dedupeSections(_ md: String) -> String {
        var seen = Set<String>()
        var kept: [String] = []
        for raw in md.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if isBullet(t) {
                let key = normalizeBullet(t)
                if !key.isEmpty {
                    if seen.contains(key) { continue }
                    seen.insert(key)
                }
            }
            kept.append(raw)
        }
        return dropEmptySections(kept).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like `dedupeSections`, but ALSO drops bullets that merely echo a transcript line
    /// (a weak model often re-lists utterances instead of synthesizing). A bullet whose
    /// word-set matches any transcript line (Jaccard ≥ 0.8, ≥3 words) is removed; emptied
    /// sections are then dropped. The transcript may carry speaker prefixes ("Me:"/"Я:").
    public static func clean(_ md: String, transcript: String) -> String {
        let txLines: [Set<String>] = transcript.components(separatedBy: "\n").compactMap {
            let toks = TranscriptMerge.tokenize(stripSpeaker($0))
            return toks.count >= 3 ? toks : nil
        }
        var seen = Set<String>()
        var kept: [String] = []
        for raw in md.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if isBullet(t) {
                let key = normalizeBullet(t)
                if !key.isEmpty {
                    if seen.contains(key) { continue }
                    let toks = Set(key.split(separator: " ").map(String.init))
                    if toks.count >= 3, txLines.contains(where: { TranscriptMerge.jaccard($0, toks) >= 0.8 }) {
                        continue
                    }
                    seen.insert(key)
                }
            }
            kept.append(raw)
        }
        return dropEmptySections(kept).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips a leading short "Speaker: " prefix so transcript lines compare on content.
    static func stripSpeaker(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: ": "), t.distance(from: t.startIndex, to: r.lowerBound) <= 15 {
            return String(t[r.upperBound...])
        }
        return t
    }

    static func isBullet(_ t: String) -> Bool {
        t.hasPrefix("- ")
    }

    /// A section heading that REQUIRES body content (a bare `## X` or a non-tip callout
    /// label like `> [!warning] Risks`). The `> [!tip]` callout is content itself.
    static func isSectionHeading(_ t: String) -> Bool {
        if t.hasPrefix("## ") { return true }
        if t.hasPrefix("> [!"), !t.lowercased().hasPrefix("> [!tip") { return true }
        return false
    }

    static func normalizeBullet(_ s: String) -> String {
        var t = s
        for p in ["- [ ] ", "- [x] ", "- [X] ", "- "] where t.hasPrefix(p) {
            t = String(t.dropFirst(p.count)); break
        }
        let scalars = t.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || $0 == " " ? Character($0) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// Removes a section heading whose body (until the next heading / H1) has no
    /// non-empty content line.
    static func dropEmptySections(_ lines: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if isSectionHeading(t) {
                var j = i + 1
                var hasContent = false
                while j < lines.count {
                    let tj = lines[j].trimmingCharacters(in: .whitespaces)
                    if isSectionHeading(tj) || tj.hasPrefix("# ") || tj.hasPrefix("> [!tip") { break }
                    if !tj.isEmpty { hasContent = true }
                    j += 1
                }
                if hasContent { out.append(lines[i]) } else { i = j; continue }
            } else {
                out.append(lines[i])
            }
            i += 1
        }
        return out
    }
}
