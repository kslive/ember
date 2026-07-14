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
    /// Merges the separately-transcribed mic and system passes into one timeline,
    /// dropping near-duplicates caused by acoustic bleed. Without headphones the mic
    /// picks up the speaker output, so the other side's speech is transcribed by BOTH
    /// passes.
    ///
    /// SYSTEM WINS, and dedup is strictly one-directional — a MIC candidate against a
    /// kept SYSTEM segment. Bleed physics only goes speaker→mic; comparing within one
    /// source could false-drop genuine repetition (С2 agreeing with С1 verbatim, the
    /// user dictating a phrase twice). Two tiers:
    ///
    /// STRICT (near in time): intervals within `window` seconds AND word-set Jaccard ≥
    /// `threshold` OR the smaller side's words CONTAINED in the other's ≥ `containment`,
    /// both ≥ `minWords` words.
    ///
    /// BLEED (nested in time): the mic interval sits INSIDE the system interval
    /// (± `nestSlack`) — there the mic heard the very audio the system segment
    /// transcribed, and ASR variance breaks exact-token measures (the same speech came
    /// out as "окулус"/"околоса" → containment 0.82 leaked). The mic segment drops when
    /// ≥ `bleedThreshold` of its ORDERED content words (≥ 3 chars, minus a small
    /// high-frequency stoplist, at least `bleedMinContent` of them) reappear in the
    /// system segment's word sequence in the same order (LCS). The order requirement is
    /// what keeps a genuine user comment built from the same topic nouns safe — echoed
    /// nouns rarely reproduce the source's exact sequence.
    ///
    /// Genuinely distinct simultaneous speech and short backchannels are kept. Used for
    /// BOTH the live monitor and the final saved transcript.
    public static func merge(
        mic: [TranscriptSegment],
        system: [TranscriptSegment],
        window: Double = 6,
        threshold: Double = 0.6,
        containment: Double = 0.85,
        minWords: Int = 3,
        bleedThreshold: Double = 0.65,
        bleedMinContent: Int = 5,
        nestSlack: Double = 1.5
    ) -> [TranscriptSegment] {
        struct SysInfo {
            let start: Double
            let end: Double
            let tokens: Set<String>
            let content: [String]
        }
        var kept = system.sorted { $0.startSeconds < $1.startSeconds }
        let sysInfo = kept.map { seg in
            let ordered = tokenizeOrdered(seg.text)
            return SysInfo(start: seg.startSeconds, end: max(seg.endSeconds, seg.startSeconds),
                           tokens: Set(ordered), content: contentTokens(ordered))
        }
        for seg in mic.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let ordered = tokenizeOrdered(seg.text)
            let tokens = Set(ordered)
            let content = contentTokens(ordered)
            let end = max(seg.endSeconds, seg.startSeconds)
            var isDup = false
            for info in sysInfo {
                if tokens.count >= minWords, info.tokens.count >= minWords,
                   max(seg.startSeconds, info.start) - min(end, info.end) <= window,
                   jaccard(tokens, info.tokens) >= threshold
                   || containmentRatio(tokens, info.tokens) >= containment {
                    isDup = true
                    break
                }
                if content.count >= bleedMinContent,
                   seg.startSeconds >= info.start - nestSlack, end <= info.end + nestSlack,
                   Double(lcsLength(content, info.content)) / Double(content.count) >= bleedThreshold {
                    isDup = true
                    break
                }
            }
            if !isDup { kept.append(seg) }
        }
        return kept.sorted { $0.startSeconds < $1.startSeconds }
    }

    /// Lowercased alphanumeric word set (handles Latin + Cyrillic; punctuation/markers
    /// like `*звук сцены*` reduce to their words so bleed pairs still match).
    static func tokenize(_ s: String) -> Set<String> {
        Set(tokenizeOrdered(s))
    }

    /// Ordered lowercased alphanumeric words, duplicates preserved — the bleed tier's
    /// LCS depends on repeated tokens ("пятьсот двенадцать гигабайт" twice must count
    /// twice). CJK runs (Chinese ASR output has no spaces — a whole sentence would be
    /// ONE "word", making every similarity measure 0-or-1) are split into overlapping
    /// character bigrams, the standard CJK indexing unit; non-CJK tokenization is
    /// byte-identical to before.
    static func tokenizeOrdered(_ s: String) -> [String] {
        var current = ""
        var currentIsCJK = false
        var words: [String] = []
        func flush() {
            guard !current.isEmpty else { return }
            if currentIsCJK {
                let chars = current.map(String.init)
                words.append(contentsOf: chars.count == 1
                    ? chars
                    : (0 ..< chars.count - 1).map { chars[$0] + chars[$0 + 1] })
            } else {
                words.append(current)
            }
            current = ""
        }
        for scalar in s.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                let cjk = isCJK(scalar)
                if cjk != currentIsCJK { flush(); currentIsCJK = cjk }
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return words
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7AF, 0xF900 ... 0xFAFF:
            true
        default:
            false
        }
    }

    /// High-frequency filler that survives the 3-char floor. Long system segments
    /// contain most of these anyway, so leaving them in would let an unrelated user
    /// comment "match" a long utterance by order luck.
    private static let bleedStoplist: Set<String> = [
        "уже", "тот", "как", "был", "это", "что", "все", "так", "вот", "там", "нет", "еще", "ещё",
        "the", "and", "was", "not", "you", "for"
    ]

    /// Content words for the bleed tier: ≥ 3 characters, stoplist removed. CJK bigrams
    /// (2 chars) always count as content — a bigram is already word-sized, and filler
    /// characters are diluted inside bigrams, so no CJK stoplist is needed.
    static func contentTokens(_ ordered: [String]) -> [String] {
        ordered.filter { token in
            guard !bleedStoplist.contains(token) else { return false }
            return token.count >= 3 || (!token.isEmpty && token.unicodeScalars.allSatisfy(isCJK))
        }
    }

    /// Longest common subsequence length over word arrays (two-row DP).
    static func lcsLength(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: b.count + 1)
        var cur = prev
        for x in a {
            for (j, y) in b.enumerated() {
                cur[j + 1] = x == y ? prev[j] + 1 : max(prev[j + 1], cur[j])
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Share of the SMALLER set's words present in the larger one (1.0 = full subset).
    static func containmentRatio(_ a: Set<String>, _ b: Set<String>) -> Double {
        let smaller = min(a.count, b.count)
        guard smaller > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(smaller)
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
