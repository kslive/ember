import Foundation

/// Grounding blocks for the summary prompts: a speaker roster, verbatim key
/// numbers, and a verifier that keeps only extracted facts literally supported
/// by the transcript. All pure text processing — the hallucination guard for the
/// facts-then-write pipeline (an unverified generated "fact" injected into the
/// prompt gets woven into fluent prose where it is hardest to spot, so anything
/// the transcript does not literally back is silently dropped).
public enum SummaryGrounding {
    /// Unique speaker labels in order of first appearance, parsed from
    /// "Label: text" transcript lines (labels are short: "Я", "Собеседник 2"…).
    public static func roster(fromTranscript transcript: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in transcript.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, label.count <= 24, !label.contains("["),
                  seen.insert(label).inserted else { continue }
            out.append(label)
        }
        return out
    }

    /// Verbatim numeric mentions with a word of context on each side ("четыре
    /// дня", "шесть с половиной дней" stays out — digits only; "80 процентов",
    /// "6,5 дней", "три пятерки ноль" is beyond regex). Deduped, capped.
    public static func keyNumbers(fromTranscript transcript: String, cap: Int = 20) -> [String] {
        let pattern = "(?:[а-яёa-z]+[ \t]+)?\\d+(?:[.,]\\d+)?%?(?:[ \t]+[а-яёa-z]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        let ns = transcript as NSString
        for match in regex.matches(in: transcript, range: NSRange(location: 0, length: ns.length)) {
            let snippet = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard snippet.rangeOfCharacter(from: .decimalDigits) != nil,
                  seen.insert(snippet.lowercased()).inserted else { continue }
            out.append(snippet)
            if out.count >= cap { break }
        }
        return out
    }

    /// Keeps only fact lines the transcript supports. Matching is calibrated for
    /// inflected Russian: content words compare by 5-char prefix (задача/задачу
    /// collapse), the extractor's own tag ([Задача]…) is stripped before checking,
    /// its connective verbs are tolerated by the 0.6 threshold — but EVERY digit
    /// token must occur in the transcript literally (numbers are what hallucinate
    /// most damagingly).
    public static func verifiedFacts(_ facts: String, transcript: String) -> String {
        let exact = Set(words(transcript))
        let prefixes = Set(exact.map { String($0.prefix(5)) })
        let kept = facts.components(separatedBy: "\n").filter { line in
            let untagged = line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            let tokens = words(untagged)
            guard tokens.count >= 3 else { return !untagged.trimmingCharacters(in: .whitespaces).isEmpty }
            let digits = tokens.filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }
            guard digits.allSatisfy(exact.contains) else { return false }
            let content = tokens.filter { $0.count >= 3 }
            guard !content.isEmpty else { return true }
            let supported = content.filter { prefixes.contains(String($0.prefix(5))) }.count
            return Double(supported) / Double(content.count) >= 0.6
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
