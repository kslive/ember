@testable import Core
import XCTest

/// Live-context overlay logic: native prompts, model-output parsing and the
/// real-time single-flight pacing. Pure functions — no models, no windows.
final class LiveContextTests: XCTestCase {
    func testPromptsAreNativePerLanguage() {
        let ru = LiveContextLogic.system(for: .ru)
        let en = LiveContextLogic.system(for: .en)
        let zh = LiveContextLogic.system(for: .zh)
        XCTAssertTrue(ru.contains("по-русски"))
        XCTAssertTrue(en.contains("in English"))
        XCTAssertTrue(zh.contains("用中文"))
        for prompt in [ru, en, zh] {
            XCTAssertFalse(prompt.contains("{{LANGUAGE}}"), "native prompts carry no token")
            XCTAssertTrue(prompt.contains("80"), "word cap present")
        }
    }

    func testParseFullShape() {
        let raw = """
        Перенос релиза на октябрь
        - Обсуждают сроки тестирования
        - Решают, кто ведёт регресс
        Вопрос: успеет ли команда к 15-му?
        """
        let ctx = LiveContextLogic.parse(raw)
        XCTAssertEqual(ctx?.topic, "Перенос релиза на октябрь")
        XCTAssertEqual(ctx?.points.count, 2)
        XCTAssertEqual(ctx?.points.first, "Обсуждают сроки тестирования")
        XCTAssertEqual(ctx?.question, "успеет ли команда к 15-му?")
    }

    func testParseTopicOnlyAndHeadingCleanup() {
        let ctx = LiveContextLogic.parse("## Бюджет на квартал\n")
        XCTAssertEqual(ctx?.topic, "Бюджет на квартал")
        XCTAssertEqual(ctx?.points, [])
        XCTAssertNil(ctx?.question)
    }

    func testParseEnglishQuestionMarker() {
        let ctx = LiveContextLogic.parse("Budget review\nQ: who owns the forecast?")
        XCTAssertEqual(ctx?.question, "who owns the forecast?")
    }

    /// The reply suggestion — the "I zoned out and got asked" rescue line.
    func testParseAnswerSuggestion() {
        let ctx = LiveContextLogic.parse("""
        Сроки релиза
        - Обсуждают перенос на октябрь
        Вопрос: успеем ли к 15-му?
        Ответ: можно подтвердить 15-е, если регресс начнётся на этой неделе.
        """)
        XCTAssertEqual(ctx?.question, "успеем ли к 15-му?")
        XCTAssertEqual(ctx?.answer, "можно подтвердить 15-е, если регресс начнётся на этой неделе.")
        let en = LiveContextLogic.parse("Release plan\nQ: when?\nReply: by Friday.")
        XCTAssertEqual(en?.answer, "by Friday.")
        XCTAssertNil(LiveContextLogic.parse("Release plan\n- point")?.answer)
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(LiveContextLogic.parse(""))
        XCTAssertNil(LiveContextLogic.parse("```\n```"))
        XCTAssertNil(LiveContextLogic.parse("\n\n  \n"))
    }

    /// Route-aware pacing. Local: 2s GPU breather between passes (cached passes
    /// run ~1-1.5s; back-to-back generations pegged the GPU and lagged the Mac),
    /// 6s when hot. Cloud: 1s floor and thermal IGNORED — it costs no local
    /// compute, and throttling it by heat made "live" content 15s stale.
    /// In-flight or silence → never.
    func testShouldGenerate() {
        XCTAssertTrue(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 24, sinceLast: 2, thermal: .nominal, cloud: false))
        XCTAssertTrue(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 500, sinceLast: 60, thermal: .fair, cloud: false))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 500, sinceLast: 1, thermal: .nominal, cloud: false))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: true, newChars: 500, sinceLast: 60, thermal: .nominal, cloud: false))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 0, sinceLast: 60, thermal: .nominal, cloud: false))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 23, sinceLast: 60, thermal: .nominal, cloud: false))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 100, sinceLast: 3, thermal: .serious, cloud: false))
        XCTAssertTrue(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 100, sinceLast: 7, thermal: .serious, cloud: false))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 100, sinceLast: 5, thermal: .critical, cloud: false))
        XCTAssertTrue(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 24, sinceLast: 1, thermal: .nominal, cloud: true))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 24, sinceLast: 0.5, thermal: .nominal, cloud: true))
        XCTAssertTrue(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 100, sinceLast: 1.2, thermal: .serious, cloud: true))
        XCTAssertTrue(LiveContextLogic.shouldGenerate(inFlight: false, newChars: 100, sinceLast: 1.2, thermal: .critical, cloud: true))
        XCTAssertFalse(LiveContextLogic.shouldGenerate(inFlight: true, newChars: 500, sinceLast: 60, thermal: .nominal, cloud: true))
    }

    func testLocalModelIdExistsInCatalog() {
        XCTAssertNotNil(SummaryCatalog.spec(for: LiveContextLogic.localModelId))
        XCTAssertNil(SummaryCatalog.spec(for: "qwen3:0.6b"), "0.6B was removed — hallucinated in the overlay")
    }

    /// Overlay local models: the 1.7B pair (speed default) and the 4B pair
    /// (quality option) — user's pick when downloaded, else the first allowed
    /// downloaded one, else nil. 8B stays post-summary-only.
    func testPickLocalModel() {
        XCTAssertEqual(LiveContextLogic.pickLocalModel(selected: "qwen3:1.7b",
                                                       downloadedIds: ["qwen3:1.7b", "qwen3:1.7b-dwq"]),
                       "qwen3:1.7b")
        XCTAssertEqual(LiveContextLogic.pickLocalModel(selected: "qwen3:1.7b",
                                                       downloadedIds: ["qwen3:1.7b-dwq", "qwen3:4b"]),
                       "qwen3:1.7b-dwq")
        XCTAssertEqual(LiveContextLogic.pickLocalModel(selected: "qwen3:4b-2507",
                                                       downloadedIds: ["qwen3:4b-2507", "qwen3:1.7b-dwq"]),
                       "qwen3:4b-2507", "the 4B series is allowed (quality option)")
        XCTAssertEqual(LiveContextLogic.pickLocalModel(selected: "qwen3:8b-dwq",
                                                       downloadedIds: ["qwen3:8b-dwq", "qwen3:1.7b-dwq"]),
                       "qwen3:1.7b-dwq", "8B is never allowed — falls back")
        XCTAssertNil(LiveContextLogic.pickLocalModel(selected: "qwen3:1.7b-dwq",
                                                     downloadedIds: ["qwen3:8b", "qwen3:8b-dwq"]),
                     "no allowed model on disk → overlay needs the cloud or is unavailable")
        XCTAssertNil(LiveContextLogic.pickLocalModel(selected: "qwen3:1.7b-dwq", downloadedIds: []))
    }

    /// Bench-picked per-family sampling: 1.7B at 0.4/0.95, 4B at Qwen's official
    /// non-thinking 0.7/0.8/topK20.
    func testLiveSampling() {
        let s17 = LiveContextLogic.liveSampling(repoId: "mlx-community/Qwen3-1.7B-4bit-DWQ")
        XCTAssertEqual(s17.temperature, 0.4)
        XCTAssertEqual(s17.topK, 0)
        let s4 = LiveContextLogic.liveSampling(repoId: "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510")
        XCTAssertEqual(s4.temperature, 0.7)
        XCTAssertEqual(s4.topP, 0.8)
        XCTAssertEqual(s4.topK, 20)
    }

    /// Every allowed overlay model must exist in the shared catalog, DWQ first.
    func testAllowedLocalIdsAreCatalogModels() {
        for id in LiveContextLogic.allowedLocalIds {
            XCTAssertNotNil(SummaryCatalog.spec(for: id), id)
        }
        XCTAssertEqual(LiveContextLogic.allowedLocalIds.first, LiveContextLogic.localModelId)
    }

    /// The LOCAL prompt: native per language, carries the few-shot example
    /// (small models follow one example better than a rule list) and the
    /// "own words" anti-echo rule.
    func testLocalPromptsAreNativeWithFewShot() {
        let ru = LiveContextLogic.systemLocal(for: .ru)
        let en = LiveContextLogic.systemLocal(for: .en)
        let zh = LiveContextLogic.systemLocal(for: .zh)
        XCTAssertTrue(ru.contains("по-русски"))
        XCTAssertTrue(en.contains("in English"))
        XCTAssertTrue(zh.contains("用中文"))
        for (prompt, marker) in [(ru, "Вопрос:"), (en, "Q:"), (zh, "问题：")] {
            XCTAssertFalse(prompt.contains("{{LANGUAGE}}"))
            XCTAssertTrue(prompt.contains("- "), "bullet shape shown in the example")
            XCTAssertTrue(prompt.contains(marker), "Q/A stays available locally")
            XCTAssertTrue(prompt.contains("60"), "word cap present")
        }
    }

    /// A naked format label must never become a feed topic (the user's screen
    /// filled with entries titled just «Вопрос»).
    func testParseRejectsBareMarkerAsTopic() {
        XCTAssertNil(LiveContextLogic.parse("Вопрос"))
        XCTAssertNil(LiveContextLogic.parse("Вопрос:\nОтвет:"))
        let ctx = LiveContextLogic.parse("Вопрос\nСроки релиза\n- тесты три дня")
        XCTAssertEqual(ctx?.topic, "Сроки релиза")
        XCTAssertEqual(LiveContextLogic.parse("Тема:\nБюджет квартала")?.topic, "Бюджет квартала")
    }

    /// Echo guard: a long verbatim transcript run as "topic" is the model
    /// copying input; a short genuine topic or a paraphrase is fine.
    func testIsEcho() {
        let tail = "вот у меня в башке отложилось так словно я его брал ну месяца может быть три четыре назад"
        XCTAssertTrue(LiveContextLogic.isEcho(topic: "Вот у меня в башке отложилось так словно я его", tail: tail))
        XCTAssertFalse(LiveContextLogic.isEcho(topic: "Впечатления от консоли", tail: tail))
        XCTAssertFalse(LiveContextLogic.isEcho(topic: "месяца может быть", tail: tail), "short topics exempt")
        XCTAssertTrue(LiveContextLogic.isEcho(topic: "У МЕНЯ В БАШКЕ, ОТЛОЖИЛОСЬ — так словно я его брал",
                                              tail: tail), "normalization ignores case/punctuation")
    }

    /// Small Qwen3 sometimes emits <think> despite /no_think: hidden while the
    /// block is unclosed (partial stream), stripped once closed, untouched otherwise.
    func testVisibleTextStripsThinking() {
        XCTAssertNil(LiveContextLogic.visibleText("<think>hm, the user is"))
        XCTAssertEqual(LiveContextLogic.visibleText("<think>hm</think>\nТема дня"), "\nТема дня")
        XCTAssertEqual(LiveContextLogic.visibleText("Тема дня\n- пункт"), "Тема дня\n- пункт")
        XCTAssertNil(LiveContextLogic.visibleText("  <think>"))
    }

    func testParseAllowsThreePoints() {
        let ctx = LiveContextLogic.parse("Сроки релиза\n- a\n- b\n- c\n- d")
        XCTAssertEqual(ctx?.points, ["a", "b", "c"])
    }

    /// A small model loves emitting the same bullet twice in different words —
    /// near-duplicate points collapse inside one snapshot.
    func testParseDedupesNearDuplicatePoints() {
        let ctx = LiveContextLogic.parse("""
        Сроки релиза
        - Тестирование займёт три дня, начнут в понедельник
        - Тестирование займёт три дня, старт в понедельник
        - Бэкенд уже готов
        """)
        XCTAssertEqual(ctx?.points.count, 2)
        XCTAssertEqual(ctx?.points.last, "Бэкенд уже готов")
    }

    /// Qwen 1.7B leaks CJK fragments into Russian output ("изучает自然界的现象"):
    /// a CJK topic invalidates the snapshot, CJK points are dropped — unless the
    /// feed language IS Chinese.
    func testRejectForeignScript() {
        let leaky = LiveContext(topic: "Появление физики",
                                points: ["Изучает自然界 и законы", "В седьмом классе — экскурсия"])
        let cleaned = LiveContextLogic.rejectForeignScript(leaky, lang: .ru)
        XCTAssertEqual(cleaned?.points, ["В седьмом классе — экскурсия"])
        XCTAssertNil(LiveContextLogic.rejectForeignScript(LiveContext(topic: "更深入 изучение", points: []),
                                                          lang: .ru))
        let zh = LiveContext(topic: "预算讨论", points: ["市场预算削减 10%"])
        XCTAssertEqual(LiveContextLogic.rejectForeignScript(zh, lang: .zh)?.topic, "预算讨论")
    }

    /// Merge-under-one-topic: stemmed matching survives Russian morphology and
    /// rephrasing; a genuinely new subject opens a new block.
    func testSameTopic() {
        XCTAssertTrue(LiveContextLogic.sameTopic("Экскурсия по физике", "Экскурса физики"))
        XCTAssertTrue(LiveContextLogic.sameTopic("Что такое физика", "Что такое физика?"))
        XCTAssertFalse(LiveContextLogic.sameTopic("Экскурсия по физике", "Перераспределение бюджета"))
        XCTAssertTrue(LiveContextLogic.sameTopic("", ""))
        XCTAssertFalse(LiveContextLogic.sameTopic("Бюджет", ""))
    }

    /// Block enrichment: old points STAY, new distinct ones append, rephrased
    /// duplicates are absorbed, the topic wording never flips, Q/A is latest.
    func testEnriched() {
        let base = LiveContext(topic: "Что такое физика",
                               points: ["Физика — наука о природе", "Слово из греческого «фюзис»"])
        let update = LiveContext(topic: "Тема: Что такое физика?",
                                 points: ["Физика — это наука о природе и её законах",
                                          "Аристотель ввёл это слово в науку"],
                                 question: "кто придумал слово?", answer: "Аристотель.")
        let merged = LiveContextLogic.enriched(base, with: update)
        XCTAssertEqual(merged.topic, "Что такое физика", "topic wording stays stable")
        XCTAssertEqual(merged.points, ["Физика — это наука о природе и её законах", "Слово из греческого «фюзис»",
                                       "Аристотель ввёл это слово в науку"],
                       "same thought upgraded to the fuller wording in place, new point appended")
        XCTAssertEqual(merged.question, "кто придумал слово?")
        let many = LiveContext(topic: "t", points: (1 ... 12).map { "совершенно разный пункт номер \($0) про уникальное" })
        XCTAssertEqual(LiveContextLogic.enriched(many, with: many).points.count, 12,
                       "overflow stops accepting, old points are never dropped")
    }

    /// Label leaks from the small model: "Тема:" prefix on the topic line and
    /// speaker labels on points get stripped (both showed up on the user's feed).
    func testParseStripsLabels() {
        let ctx = LiveContextLogic.parse("""
        Тема: обучение физики
        - Собеседник: мы будем изучать физику от начала до конца
        - Я: да, именно так.
        """)
        XCTAssertEqual(ctx?.topic, "обучение физики")
        XCTAssertEqual(ctx?.points.first, "мы будем изучать физику от начала до конца")
        XCTAssertEqual(ctx?.points.last, "да, именно так.")
        XCTAssertEqual(LiveContextLogic.parse("Сроки: перенос релиза")?.topic, "Сроки: перенос релиза",
                       "a real topic with a colon is untouched")
    }

    /// Placeholder stubs the model invents for missing facts never reach the
    /// feed: "Учебник Бажинова (сайт: [название])".
    func testParseDropsPlaceholderPoints() {
        XCTAssertTrue(LiveContextLogic.hasPlaceholder("Учебник Бажинова (сайт: [название])"))
        XCTAssertFalse(LiveContextLogic.hasPlaceholder("Задачи номер 1, 3, 4, 5 и 12"))
        let ctx = LiveContextLogic.parse("""
        Учебники по физике
        - Учебник Бажинова (сайт: [название])
        - Задачник Лукашика, номера 1, 3, 4
        """)
        XCTAssertEqual(ctx?.points, ["Задачник Лукашика, номера 1, 3, 4"])
    }

    /// Copy-all export: timecoded blocks in the card's shape, blank line between
    /// entries, Q/A markers in the feed language.
    func testExportText() {
        let items: [(at: TimeInterval, context: LiveContext)] = [
            (9, LiveContext(topic: "Шоу на ютубе", points: ["Шоу вытеснили простое общение"])),
            (95, LiveContext(topic: "Интервью на вписке", points: ["Пять миллионов просмотров"],
                             question: "как это возможно при блокировке?", answer: "смотрят через VPN."))
        ]
        let ru = LiveContextLogic.exportText(items, lang: .ru)
        XCTAssertEqual(ru, """
        [00:09] Шоу на ютубе
        - Шоу вытеснили простое общение

        [01:35] Интервью на вписке
        - Пять миллионов просмотров
        Вопрос: как это возможно при блокировке?
        Ответ: смотрят через VPN.
        """)
        XCTAssertTrue(LiveContextLogic.exportText(items, lang: .en).contains("Q: как это возможно"))
        XCTAssertEqual(LiveContextLogic.exportText([], lang: .ru), "")
    }
}
