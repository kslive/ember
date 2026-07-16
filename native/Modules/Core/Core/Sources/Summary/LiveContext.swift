import Foundation

/// The live "what's being discussed right now" snapshot shown in the overlay:
/// a topic line, discussion points, the latest open question — and a suggested
/// reply when a question was aimed at the user (the "I zoned out and got asked
/// something" rescue).
public struct LiveContext: Equatable, Sendable {
    public let topic: String
    public let points: [String]
    public let question: String?
    public let answer: String?

    public init(topic: String, points: [String], question: String? = nil, answer: String? = nil) {
        self.topic = topic
        self.points = points
        self.question = question
        self.answer = answer
    }
}

/// Prompts + parsing + pacing for the live-context overlay. Prompts are NATIVE
/// per app language (headings/answers come out right with no on-the-fly
/// translation — same lesson as the built-in summary templates). Pure logic,
/// fully testable; the engine that calls models lives in the App layer.
public enum LiveContextLogic {
    /// Default catalog id of the overlay's local model (fast 1.7B, ~1 GB).
    public static let localModelId = "qwen3:1.7b-dwq"

    /// The ONLY local models the overlay may run, in preference order. Bench on a
    /// real transcript (KV prefix cache, 8-pass grid): the 1.7B pair ≈ 1.8s/pass —
    /// the speed default; the 4B pair ≈ 3.1-3.5s/pass with noticeably sharper
    /// substance — allowed as the user's quality option. 8B stays post-summary-
    /// only (too slow for live), 0.6B was removed (hallucinated).
    public static let allowedLocalIds = ["qwen3:1.7b-dwq", "qwen3:1.7b", "qwen3:4b-2507", "qwen3:4b"]

    /// Bench-picked sampling per model family (same grid): 1.7B best at 0.4/0.95;
    /// 4B fastest and cleanest at Qwen's official non-thinking 0.7/0.8/topK20
    /// (3.48s vs 3.71s mean at 0.4/0.95, equal validity).
    public static func liveSampling(repoId: String) -> (temperature: Float, topP: Float, topK: Int) {
        repoId.contains("1.7B") ? (0.4, 0.95, 0) : (0.7, 0.8, 20)
    }

    /// Resolves which downloaded local model serves the overlay: the user's pick
    /// when it's an allowed model on disk, else the first downloaded allowed one.
    /// nil = no allowed model downloaded — the overlay needs the cloud or is
    /// unavailable.
    public static func pickLocalModel(selected: String, downloadedIds: [String]) -> String? {
        if allowedLocalIds.contains(selected), downloadedIds.contains(selected) { return selected }
        return allowedLocalIds.first { downloadedIds.contains($0) }
    }

    /// Native system prompt for the overlay generation. Written for the "I zoned
    /// out — catch me up NOW" use case: substance from the conversation (claims,
    /// numbers, names, the actual question asked), never meta talk about speakers.
    public static func system(for lang: AppLanguage) -> String {
        switch lang {
        case .ru:
            """
            Ты — живой суфлёр встречи. Читаешь хвост ЖИВОГО транскрипта (может обрываться) и спасаешь человека, который отвлёкся: за 5 секунд он должен понять, О ЧЁМ ИДЁТ РЕЧЬ ПРЯМО СЕЙЧАС.
            Формат ответа, без преамбулы:
            строка 1 — тема разговора прямо сейчас (3–6 слов, конкретная);
            2–4 строки «- » — СУТЬ происходящего: что именно утверждают, предлагают, решают; сохраняй конкретику — имена, цифры, названия, сроки. КАЖДЫЙ пункт — одна мысль, МАКСИМУМ 2 коротких предложения. Это ГЛАВНАЯ часть ответа.
            ТОЛЬКО если в САМОМ КОНЦЕ транскрипта прозвучал явный вопрос, ожидающий ответа: строка «Вопрос: <сам вопрос своими словами>» и сразу за ней «Ответ: <короткая подсказка, как ответить по контексту — 1 предложение>». Если такого вопроса нет — эти строки НЕ выводи вовсе.
            ЗАПРЕЩЕНО: упоминать метки «Я»/«Собеседник», писать «участник говорит/обсуждают тему» и прочие общие слова — только само содержание. Обычный текст без markdown-разметки (никаких **, #, `). Ничего не выдумывай. До 80 слов. Пиши по-русски.
            """
        case .en:
            """
            You are a live meeting prompter. You read the tail of a LIVE transcript (possibly cut off) and rescue someone who zoned out: within 5 seconds they must grasp WHAT IS BEING DISCUSSED RIGHT NOW.
            Reply shape, no preamble:
            line 1 — the topic right now (3–6 words, specific);
            2–4 lines starting with "- " — the SUBSTANCE: what exactly is being claimed, proposed, decided; keep specifics — names, numbers, deadlines. EACH line — one thought, AT MOST 2 short sentences. This is the MAIN part of the reply.
            ONLY if an explicit question awaiting an answer was asked at the VERY END of the transcript: a line "Q: <the question, paraphrased>" immediately followed by "Reply: <a short suggestion how to answer in context — 1 sentence>". If there is no such question — do NOT output these lines at all.
            FORBIDDEN: mentioning "Me"/"Speaker" labels, writing "the participant says / they discuss a topic" or any such filler — only the content itself. Plain text, no markdown (no **, #, `). Invent nothing. Up to 80 words. Write in English.
            """
        case .zh:
            """
            你是会议的实时提词员。你阅读实时转写的末尾片段（可能被截断），拯救走神的人：5 秒内他必须明白此刻正在讨论什么。
            回答格式，不要前言：
            第 1 行 —— 此刻的主题（3–6 个词，要具体）；
            2–4 行以「- 」开头 —— 实质内容：具体在主张、提议、决定什么；保留具体信息——人名、数字、名称、期限。每行一个要点，最多 2 个短句。这是回答的主体。
            仅当转写的最末尾出现了等待回答的明确问题时：一行「问题：<用自己的话复述该问题>」，紧接着「回答：<结合上下文的简短回答建议——1 句话>」。若没有这样的问题——完全不要输出这两行。
            禁止：提及「我」「对方」等标签，禁止写「参与者在讨论某话题」之类的空话——只写内容本身。纯文本，不要 markdown 标记（不要 **、#、`）。不要编造。不超过 80 个词。用中文写。
            """
        }
    }

    /// System prompt for the LOCAL (small, 1-2B) model — the cloud prompt above
    /// overwhelms it: on the user's screen it produced bare "Вопрос" blocks and
    /// echoed transcript lines instead of substance. Small models follow ONE
    /// compact few-shot example far more reliably than a list of rules, so this
    /// prompt is shorter, stricter about the shape, and shows the exact expected
    /// output once (including a REAL question case, so Q/A still works locally —
    /// the user kept that feature).
    public static func systemLocal(for lang: AppLanguage) -> String {
        switch lang {
        case .ru:
            """
            Ты — живой суфлёр встречи. По хвосту живого транскрипта скажи, О ЧЁМ РЕЧЬ ПРЯМО СЕЙЧАС.
            Формат ответа, без преамбулы:
            строка 1 — тема сейчас (3–6 слов);
            2–3 строки «- » — суть: что утверждают, предлагают, решают; с конкретикой (имена, цифры, сроки). Каждая — одна мысль, максимум 2 коротких предложения.
            Если в САМОМ КОНЦЕ прозвучал явный вопрос — добавь «Вопрос: <вопрос>» и «Ответ: <короткая подсказка>»; обе строки только с текстом после двоеточия. Нет вопроса — не пиши эти строки.
            Описывай то, что обсуждают в САМОМ КОНЦЕ транскрипта (последние реплики); более раннее — только фон. Пересказывай СВОИМИ словами — не копируй фразы транскрипта. Без markdown. Ничего не выдумывай. До 60 слов. Пиши по-русски.

            Пример 1 (обычный случай — вопроса нет).
            Транскрипт: «Собеседник: бюджет маркетинга режем на десять процентов, эти деньги переносим на разработку, наймём двух инженеров»
            Твой ответ:
            Перераспределение бюджета
            - Маркетинг урезают на 10%, деньги уходят в разработку
            - Планируют нанять двух инженеров

            Пример 2 (в самом конце прозвучал вопрос).
            Транскрипт: «Я: тестирование займёт три дня, начнём в понедельник. Собеседник: бэк готов, а релиз пятнадцатого реально?»
            Твой ответ:
            Сроки релиза
            - Тестирование займёт три дня, старт в понедельник
            - Бэкенд уже готов
            Вопрос: успеем ли выпустить релиз 15-го?
            Ответ: да, если тесты начнутся в понедельник.
            """
        case .en:
            """
            You are a live meeting prompter. From the tail of a live transcript, say WHAT IS BEING DISCUSSED RIGHT NOW.
            Reply shape, no preamble:
            line 1 — the topic right now (3–6 words);
            2–3 lines starting with "- " — the substance: what is being claimed, proposed, decided; keep specifics (names, numbers, deadlines). Each line — one thought, at most 2 short sentences.
            Only if an explicit question was asked at the VERY END: add "Q: <the question>" and "Reply: <a short suggestion>"; both lines must have text after the colon. No such question — do not write these lines.
            Describe what is being discussed at the VERY END of the transcript (the latest lines); earlier text is background only. Rephrase in YOUR OWN words — never copy transcript phrases. No markdown. Invent nothing. Up to 60 words. Write in English.

            Example 1 (the usual case — no question).
            Transcript: "Speaker: marketing budget gets cut ten percent, the money moves to engineering, we hire two engineers"
            Your reply:
            Budget reallocation
            - Marketing cut by 10%, money moves to engineering
            - Two engineers to be hired

            Example 2 (a question at the very end).
            Transcript: "Me: testing takes three days, we start Monday. Speaker: backend is done, is the release on the 15th realistic?"
            Your reply:
            Release timeline
            - Testing takes three days, starting Monday
            - Backend is already done
            Q: can we ship on the 15th?
            Reply: yes, if testing starts on Monday.
            """
        case .zh:
            """
            你是会议的实时提词员。根据实时转写的末尾片段，说出此刻正在讨论什么。
            回答格式，不要前言：
            第 1 行 —— 此刻的主题（3–6 个词）；
            2–3 行以「- 」开头 —— 实质内容：在主张、提议、决定什么；保留具体信息（人名、数字、期限）。每行一个要点，最多 2 个短句。
            仅当转写最末尾出现明确问题时：加一行「问题：<问题>」和「回答：<简短建议>」；两行冒号后必须有内容。没有问题就不要写这两行。
            描述转写最末尾（最新几句）正在讨论的内容；更早的内容仅作背景。用自己的话改述——不要照抄转写原句。不要 markdown。不要编造。不超过 60 个词。用中文写。

            示例 1（通常情况——没有问题）。
            转写：「对方：市场预算削减百分之十，这笔钱转到研发，再招两名工程师」
            你的回答：
            预算重新分配
            - 市场预算削减 10%，转到研发
            - 计划招聘两名工程师

            示例 2（末尾出现了问题）。
            转写：「我：测试需要三天，周一开始。对方：后端已完成，15 号发布现实吗？」
            你的回答：
            发布时间安排
            - 测试需要三天，周一开始
            - 后端已经完成
            问题：能否在 15 号发布？
            回答：可以，只要测试周一开始。
            """
        }
    }

    /// Strips a leading `<think>…</think>` block from a (possibly partial) reply.
    /// nil while the model is still inside an UNCLOSED think block — nothing is
    /// showable yet. Small Qwen3 sometimes emits the block despite `/no_think`.
    public static func visibleText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<think>") else { return raw }
        guard let close = trimmed.range(of: "</think>") else { return nil }
        return String(trimmed[close.upperBound...])
    }

    /// Parses the model's reply into a LiveContext. First non-empty line → topic,
    /// "- " lines → points (max 2), a question-prefixed line → question.
    /// Garbage (empty / markdown fence only) → nil so the overlay keeps the
    /// previous snapshot instead of flashing junk.
    public static func parse(_ raw: String) -> LiveContext? {
        let questionMarkers = ["Вопрос:", "Q:", "问题：", "问题:"]
        let answerMarkers = ["Ответ:", "Reply:", "Answer:", "A:", "回答：", "回答:"]
        var topic: String?
        var points: [String] = []
        var question: String?
        var answer: String?
        for line in raw.components(separatedBy: "\n") {
            var t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("```") else { continue }
            if let marker = answerMarkers.first(where: { t.hasPrefix($0) }) {
                let a = t.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if !a.isEmpty { answer = a }
                continue
            }
            if let marker = questionMarkers.first(where: { t.hasPrefix($0) }) {
                let q = t.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if !q.isEmpty { question = q }
                continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("• ") {
                if points.count < 3 {
                    let p = stripSpeakerLabel(t.dropFirst(2).trimmingCharacters(in: .whitespaces))
                    if !p.isEmpty, !hasPlaceholder(p), !points.contains(where: { nearDuplicatePoints($0, p) }) {
                        points.append(p)
                    }
                }
                continue
            }
            if topic == nil {
                while t.hasPrefix("#") {
                    t.removeFirst()
                }
                let cleaned = stripLeadingLabel(t.trimmingCharacters(in: .whitespaces))
                if !cleaned.isEmpty, !isBareMarker(cleaned) { topic = cleaned }
            }
        }
        guard let topic else { return nil }
        return LiveContext(topic: topic, points: points, question: question, answer: answer)
    }

    /// A small model sometimes emits a NAKED format label ("Вопрос", "Ответ:",
    /// "Тема") with no content — on the user's screen those became whole feed
    /// entries titled «Вопрос». Such a line must never be taken as the topic.
    private static let bareMarkers: Set<String> = [
        "вопрос", "ответ", "тема", "суть", "q", "a", "topic", "question",
        "answer", "reply", "问题", "回答", "主题",
        "тема сейчас", "текущая тема", "тема урока", "topic now", "current topic",
        "lesson topic", "当前主题", "课题"
    ]
    static func isBareMarker(_ line: String) -> Bool {
        var t = line.lowercased()
        while let last = t.last, last == ":" || last == "：" || last == " " {
            t.removeLast()
        }
        return bareMarkers.contains(t)
    }

    /// The model hallucinates template placeholders when it lacks a fact —
    /// "Учебник Бажинова (сайт: [название])". A point carrying a letters-only
    /// [bracketed] stub is noise.
    static func hasPlaceholder(_ s: String) -> Bool {
        s.range(of: "\\[[^\\]0-9]+\\]", options: .regularExpression) != nil
    }

    /// "Тема: обучение физики" → "обучение физики": the model sometimes labels
    /// the topic line despite the format examples — strip a leading format label.
    private static func stripLeadingLabel(_ s: String) -> String {
        guard let colon = s.firstIndex(where: { $0 == ":" || $0 == "：" }),
              isBareMarker(String(s[..<colon])) else { return s }
        return String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    /// "- Собеседник: мы будем изучать физику" → "мы будем изучать физику":
    /// speaker labels are banned by the prompt but small models leak them.
    private static let speakerLabels: Set<String> = ["я", "собеседник", "me", "speaker", "我", "对方"]
    private static func stripSpeakerLabel(_ s: String) -> String {
        guard let colon = s.firstIndex(where: { $0 == ":" || $0 == "：" }),
              speakerLabels.contains(String(s[..<colon]).trimmingCharacters(in: .whitespaces).lowercased())
        else { return s }
        return String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Two bullet points that say the same thing (small models love emitting a
    /// rephrased duplicate) — Jaccard ≥ 0.6 over stemmed words, OR containment:
    /// one point almost entirely inside the other is one thought too ("введённая
    /// древнегреческим учёным" ⊂ "введённая Аристотелем как «фюзис»").
    static func nearDuplicatePoints(_ a: String, _ b: String) -> Bool {
        let ta = topicTokens(a), tb = topicTokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let inter = Double(ta.intersection(tb).count)
        if inter / Double(ta.union(tb).count) >= 0.6 { return true }
        return inter / Double(min(ta.count, tb.count)) >= 0.7
    }

    /// Plain-text export of the overlay feed (the copy-all button): timecoded
    /// blocks in the same shape the card renders, Q/A markers in the feed's
    /// language.
    public static func exportText(_ items: [(at: TimeInterval, context: LiveContext)],
                                  lang: AppLanguage) -> String {
        let qa: (q: String, a: String) = switch lang {
        case .ru: ("Вопрос", "Ответ")
        case .en: ("Q", "Reply")
        case .zh: ("问题", "回答")
        }
        return items.map { item in
            var lines = ["[\(Format.timecode(item.at))] \(item.context.topic)"]
            lines += item.context.points.map { "- \($0)" }
            if let q = item.context.question { lines.append("\(qa.q): \(q)") }
            if let a = item.context.answer { lines.append("\(qa.a): \(a)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// Do two topic lines describe the SAME discussion? Drives the feed's
    /// merge-under-one-topic rule: while the topic holds, snapshots ENRICH the
    /// existing block; a new topic opens a new block. Stemmed-token Jaccard —
    /// wording drifts between regenerations, the subject doesn't.
    public static func sameTopic(_ a: String, _ b: String) -> Bool {
        let ta = topicTokens(a), tb = topicTokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return ta == tb }
        return Double(ta.intersection(tb).count) / Double(ta.union(tb).count) >= 0.5
    }

    /// Enriches a topic block with a fresh snapshot: existing points STAY (the
    /// user: «именно прям ДОПОЛНЯТЬ, а не стирать»), new distinct ones append
    /// below, rephrased duplicates are absorbed; the topic wording never flips
    /// (no visual jumping). Q/A is transient — always the latest.
    public static func enriched(_ base: LiveContext, with parsed: LiveContext) -> LiveContext {
        var points = base.points
        for p in parsed.points {
            if let i = points.firstIndex(where: { nearDuplicatePoints($0, p) }) {
                // Same thought — keep the FULLER wording (a refinement, not an
                // erasure: "введённая учёным" → "введённая Аристотелем как фюзис").
                if p.count > points[i].count { points[i] = p }
            } else {
                points.append(p)
            }
        }
        // NEVER drop the older points (the user's rule: «дополнять, а не
        // стирать») — overflow just stops accepting new ones; the ENGINE closes
        // a full block and opens a continuation below instead.
        if points.count > 12 { points = Array(points.prefix(12)) }
        return LiveContext(topic: base.topic, points: points,
                           question: parsed.question, answer: parsed.answer)
    }

    /// Echo guard: a "topic" that is a VERBATIM run of the transcript tail is the
    /// model copying input instead of summarizing (a whole raw ASR line showed up
    /// as a feed entry). Normalized substring match; short topics are exempt —
    /// a genuine 3-word topic can legitimately appear in speech.
    public static func isEcho(topic: String, tail: String) -> Bool {
        let t = normalizeForEcho(topic)
        guard t.count >= 25 else { return false }
        return normalizeForEcho(tail).contains(t)
    }

    private static func normalizeForEcho(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Real-time pacing: single-flight latest-wins with a BREATHER between passes.
    /// The breather is ROUTE-AWARE — it exists to rest the GPU, and only the LOCAL
    /// model uses the GPU: back-to-back local generations kept it at 100% duty and
    /// lagged the whole Mac, and a hot machine needs a longer local rest. The cloud
    /// pass is network-bound (zero local compute), so it gets a minimal floor and
    /// IGNORES thermal state — recording+ASR+video already run the Mac hot, and an
    /// 8s cloud pause turned "live" into 15s-stale content. Silence never generates.
    public static func shouldGenerate(inFlight: Bool, newChars: Int, sinceLast: TimeInterval,
                                      thermal: ProcessInfo.ThermalState, cloud: Bool) -> Bool {
        guard !inFlight, newChars >= 24 else { return false }
        if cloud { return sinceLast >= 1 }
        if thermal == .serious || thermal == .critical { return sinceLast >= 6 }
        // 2s local breather: with the KV prefix cache a pass is ~1-1.5s, so this
        // keeps the GPU near ~40% duty (the 3s floor dated from 3-4s cold passes).
        return sinceLast >= 2
    }

    /// Crude stemming via 4-char prefixes: Russian inflection defeated exact-token
    /// Jaccard ("класс/классе", "математики/математикой"), and verb forms diverge
    /// at the 5th letter ("изучение/изучающий/изучить") — 4 catches them all.
    private static func topicTokens(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
            .map { String($0.prefix(4)) })
    }

    /// Small Qwen leaks foreign-script fragments into Russian/English output
    /// ("более深入", "Стиموс", "изучает自然界的现象") — CJK, Arabic, Hebrew,
    /// Hangul. For non-Chinese feeds: an infected topic invalidates the snapshot,
    /// infected points are dropped.
    public static func rejectForeignScript(_ ctx: LiveContext, lang: AppLanguage) -> LiveContext? {
        guard lang != .zh else { return ctx }
        guard !containsCJK(ctx.topic) else { return nil }
        let points = ctx.points.filter { !containsCJK($0) }
        let question = ctx.question.flatMap { containsCJK($0) ? nil : $0 }
        return LiveContext(topic: ctx.topic, points: points, question: question,
                           answer: question == nil ? nil : ctx.answer.flatMap { containsCJK($0) ? nil : $0 })
    }

    static func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x3400 ... 0x4DBF).contains(v) || (0x4E00 ... 0x9FFF).contains(v)
                || (0x3040 ... 0x30FF).contains(v) || (0xF900 ... 0xFAFF).contains(v)
                || (0x0590 ... 0x05FF).contains(v) || (0x0600 ... 0x06FF).contains(v)
                || (0xAC00 ... 0xD7AF).contains(v)
        }
    }
}
