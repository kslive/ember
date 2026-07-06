@testable import Core
@testable import SummaryService
import XCTest

/// Summary business logic: prompt structure, language selection (the Ukrainian
/// regression), think-stripping and language naming.
final class SummaryLogicTests: XCTestCase {
    func testSummaryLanguageFollowsSelected() {
        XCTAssertEqual(SummaryService.summaryLanguageCode(selected: .ru), "ru")
        XCTAssertEqual(SummaryService.summaryLanguageCode(selected: .en), "en")
        XCTAssertEqual(SummaryService.summaryLanguageCode(selected: .zh), "zh")
    }

    /// RAM gate is on PHYSICAL (installed) memory, not momentary free memory: a 16 GB
    /// Mac must clear the 8B (16 GB) requirement; only genuinely small machines block.
    func testHasEnoughRAMGate() {
        XCTAssertTrue(SummaryService.hasEnoughRAM(minGB: 16, physicalGB: 16)) // 16GB Mac runs 8B
        XCTAssertTrue(SummaryService.hasEnoughRAM(minGB: 16, physicalGB: 32))
        XCTAssertFalse(SummaryService.hasEnoughRAM(minGB: 16, physicalGB: 8)) // 8GB Mac blocks 8B
        XCTAssertTrue(SummaryService.hasEnoughRAM(minGB: 8, physicalGB: 8)) // 8GB runs 4B/1.7B
        XCTAssertFalse(SummaryService.hasEnoughRAM(minGB: 8, physicalGB: 6))
    }

    /// A short Russian transcript is frequently mis-detected as Ukrainian — the
    /// reason we use the selected language instead of `detectLanguage` in the pipeline.
    func testUkrainianPromptDiffersFromRussian() {
        XCTAssertNotEqual(SummaryPrompts.system(language: "uk"), SummaryPrompts.system(language: "ru"))
        XCTAssertTrue(SummaryPrompts.system(language: "uk").contains("Ukrainian"))
    }

    private func assertStructure(_ p: String, _ markers: [String], file: StaticString = #filePath, line: UInt = #line) {
        for marker in markers {
            XCTAssertTrue(p.contains(marker), "missing \(marker)", file: file, line: line)
        }
    }

    func testRussianPromptStructure() {
        let p = SummaryPrompts.system(language: "ru")
        assertStructure(p, ["# ", "> [!tip]", "## Главное", "## Обсуждение",
                            "## Решения", "## Задачи", "> [!warning]", "## Цитаты"])
        XCTAssertFalse(p.contains("## Участники"))
        XCTAssertTrue(p.contains("Встреча прошла успешно"))
    }

    func testEnglishPromptStructure() {
        let p = SummaryPrompts.system(language: "en")
        assertStructure(p, ["# ", "> [!tip]", "## Key points", "## Discussion",
                            "## Decisions", "## Action items", "> [!warning]", "## Quotes"])
        XCTAssertFalse(p.contains("## Participants"))
        XCTAssertTrue(p.contains("Meeting"))
    }

    func testChinesePromptStructure() {
        let p = SummaryPrompts.system(language: "zh")
        assertStructure(p, ["# ", "> [!tip]", "## 重点", "## 讨论",
                            "## 决定", "## 行动项", "> [!warning]", "## 引用"])
        XCTAssertFalse(p.contains("## 参会者"))
    }

    func testTitleUsesSpecificH1() {
        let md = "# Релиз 1.3: перенос на 15 октября\n\n> [!tip] Обсудили сроки.\n"
        XCTAssertEqual(SummaryMarkdown.title(from: md), "Релиз 1.3: перенос на 15 октября")
    }

    func testGenericH1FallsBackToTLDR() throws {
        let md = "# Анализ встречи\n\n> [!tip] Договорились перенести релиз на октябрь.\n"
        let t = SummaryMarkdown.title(from: md)
        XCTAssertNotNil(t)
        XCTAssertNotEqual(t, "Анализ встречи")
        XCTAssertTrue(try XCTUnwrap(t?.localizedCaseInsensitiveContains("релиз")))
    }

    func testMissingH1UsesTLDR() {
        let md = "> [!tip] Запустили новый сайт и обсудили метрики.\n## Решения\n- x\n"
        XCTAssertEqual(SummaryMarkdown.title(from: md), "Запустили новый сайт и обсудили метрики")
    }

    func testEmptyMarkdownNoTitle() {
        XCTAssertNil(SummaryMarkdown.title(from: "\n\n## Решения\n- x\n"))
    }

    func testFillerH1FallsBackToTLDR() throws {
        let md = "# Встреча прошла успешно\n\n> [!tip] Договорились перенести релиз на октябрь.\n"
        let t = SummaryMarkdown.title(from: md)
        XCTAssertNotEqual(t, "Встреча прошла успешно")
        XCTAssertTrue(try XCTUnwrap(t?.localizedCaseInsensitiveContains("релиз")))
    }

    func testSanitizeDropsDuplicateBulletsAcrossSections() {
        let md = """
        # Тема
        ## Решения
        - Проверить связь и работу устройств.
        ## Задачи
        - Проверить связь и работу устройств.
        - Реальная отдельная задача.
        """
        let out = SummarySanitize.dedupeSections(md)
        let occurrences = out.components(separatedBy: "Проверить связь и работу устройств").count - 1
        XCTAssertEqual(occurrences, 1)
        XCTAssertTrue(out.contains("Реальная отдельная задача"))
    }

    func testCleanDropsTranscriptEchoBullets() {
        let transcript = "Я: раз два три четыре пять шесть\nСобеседник: добро пожаловать на наше шоу сегодня"
        let md = """
        # Тема
        ## Главное
        - Раз два три четыре пять шесть.
        - Участники обсудили формат будущих выпусков канала.
        """
        let out = SummarySanitize.clean(md, transcript: transcript)
        XCTAssertFalse(out.contains("Раз два три четыре пять шесть"))
        XCTAssertTrue(out.contains("формат будущих выпусков"))
    }

    func testCleanRemovesSectionEmptiedByEchoes() {
        let transcript = "Я: проверка связи раз два три\nСобеседник: меня хорошо слышно отлично"
        let md = """
        # Тема
        ## Главное
        - Проверка связи раз два три.
        - Меня хорошо слышно отлично.
        """
        let out = SummarySanitize.clean(md, transcript: transcript)
        XCTAssertFalse(out.contains("## Главное"))
    }

    func testSanitizeRemovesEmptiedSectionHeading() {
        let md = """
        # Тема
        ## Решения
        - Одно решение.
        ## Задачи
        - Одно решение.
        """
        let out = SummarySanitize.dedupeSections(md)
        XCTAssertFalse(out.contains("## Задачи"))
        XCTAssertTrue(out.contains("## Решения"))
    }

    func testUserPromptEmbedsTranscript() {
        let u = SummaryPrompts.user(transcript: "ALPHA-TOKEN", language: "ru")
        XCTAssertTrue(u.contains("ALPHA-TOKEN"))
        XCTAssertTrue(u.contains("Транскрипт"))
    }

    func testLanguageName() {
        XCTAssertEqual(SummaryPrompts.languageName("ru"), "Russian")
        XCTAssertEqual(SummaryPrompts.languageName("en"), "English")
        XCTAssertEqual(SummaryPrompts.languageName("zh"), "Chinese")
    }

    @MainActor
    func testAutoSummaryDefaultsOn() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.autoSummaryKey)
        XCTAssertTrue(SettingsStore.autoSummaryOn(), "auto-summary must default to ON")
    }

    @MainActor
    func testAutoSummaryReadsStoredValue() {
        UserDefaults.standard.set(false, forKey: SettingsStore.autoSummaryKey)
        XCTAssertFalse(SettingsStore.autoSummaryOn())
        UserDefaults.standard.set(true, forKey: SettingsStore.autoSummaryKey)
        XCTAssertTrue(SettingsStore.autoSummaryOn())
        UserDefaults.standard.removeObject(forKey: SettingsStore.autoSummaryKey)
    }

    /// The single-pass prompt budget is capped at 12k tokens for EVERY model — an
    /// uncapped ~33.6k-token pass built a multi-GB KV cache and pinned the GPU for
    /// minutes on long meetings (whole-Mac lag); long transcripts must map-reduce.
    func testPromptBudgetTokensCappedAt12k() {
        XCTAssertEqual(SummaryService.promptBudgetTokens(context: 40960, maxGen: 6144), 12000)
        XCTAssertEqual(SummaryService.promptBudgetTokens(context: 20000, maxGen: 6144), 12000)
        XCTAssertEqual(SummaryService.promptBudgetTokens(context: 16000, maxGen: 6144), 8656)
        XCTAssertEqual(SummaryService.promptBudgetTokens(context: 8192, maxGen: 6144), 2000)
    }

    func testThinkStripperRemovesReasoning() {
        XCTAssertEqual(ThinkStripper.strip("<think>reasoning…</think>\nИтог"), "Итог")
    }

    func testThinkStripperRemovesNoThinkAndTrims() {
        XCTAssertEqual(ThinkStripper.strip("  Привет /no_think  "), "Привет")
    }

    func testTldrTitleFirstSentenceOnly() throws {
        let md = "# X\n\n> [!tip] Договорились перенести релиз на октябрь. Второе предложение тут.\n"
        let title = SummaryMarkdown.tldrTitle(md)
        XCTAssertNotNil(title)
        XCTAssertTrue(try XCTUnwrap(title?.localizedCaseInsensitiveContains("договорились")))
        XCTAssertFalse(try XCTUnwrap(title?.contains("Второе")))
    }

    func testTldrTitleNilWithoutTip() {
        XCTAssertNil(SummaryMarkdown.tldrTitle("# X\n## Решения\n- a\n"))
    }

    func testGenericH1FallsBackToTldr() {
        let md = "# Совещание\n\n> [!tip] Запустили оплату по подписке.\n"
        XCTAssertNotEqual(SummaryMarkdown.title(from: md), "Совещание")
        let md2 = "# Meeting\n\n> [!tip] Shipped the new billing flow.\n"
        XCTAssertNotEqual(SummaryMarkdown.title(from: md2), "Meeting")
    }

    func testUserPromptPerLanguage() {
        XCTAssertTrue(SummaryPrompts.user(transcript: "T", language: "ru").contains("Транскрипт встречи"))
        XCTAssertTrue(SummaryPrompts.user(transcript: "T", language: "zh").contains("会议记录"))
        XCTAssertTrue(SummaryPrompts.user(transcript: "T", language: "en").contains("Meeting transcript"))
        XCTAssertTrue(SummaryPrompts.user(transcript: "ALPHA-TOKEN", language: "fr").contains("ALPHA-TOKEN"))
    }

    func testLanguageNameFallbacks() {
        XCTAssertEqual(SummaryPrompts.languageName("es"), "Spanish")
        XCTAssertEqual(SummaryPrompts.languageName("de"), "German")
        XCTAssertEqual(SummaryPrompts.languageName("fr"), "French")
    }
}
