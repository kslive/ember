@testable import Core
import XCTest

/// Covers the pure business logic behind the main screen, sidebar and live
/// transcription (everything before Settings).
final class MainFlowTests: XCTestCase {
    private func meeting(_ title: String, _ date: Date) -> Meeting {
        Meeting(title: title, createdAt: date)
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 1; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    func testSearchEmptyReturnsAll() {
        let ms = [meeting("Планёрка", at(10, 0)), meeting("Ретро", at(11, 0))]
        XCTAssertEqual(MeetingSearch.filter(ms, query: "  ", language: .ru).count, 2)
    }

    func testSearchByTitleCaseInsensitive() {
        let ms = [meeting("Планёрка по релизу", at(10, 0)), meeting("Ретро спринта", at(11, 0))]
        XCTAssertEqual(MeetingSearch.filter(ms, query: "РЕЛИЗ", language: .ru).map(\.title), ["Планёрка по релизу"])
    }

    func testSearchByClockTime() {
        let ms = [meeting("Звонок", at(21, 8)), meeting("Синк", at(9, 30))]
        XCTAssertEqual(MeetingSearch.filter(ms, query: "21:08", language: .ru).map(\.title), ["Звонок"])
    }

    func testSearchNoMatch() {
        let ms = [meeting("Планёрка", at(10, 0))]
        XCTAssertTrue(MeetingSearch.filter(ms, query: "zzz", language: .ru).isEmpty)
    }

    func testNavEmptyList() {
        XCTAssertNil(Nav.adjacentIndex(count: 0, current: 0, delta: 1))
    }

    func testNavNilCurrentGoesFirst() {
        XCTAssertEqual(Nav.adjacentIndex(count: 5, current: nil, delta: 1), 0)
    }

    func testNavDownClampsAtEnd() {
        XCTAssertEqual(Nav.adjacentIndex(count: 3, current: 2, delta: 1), 2)
    }

    func testNavUpClampsAtStart() {
        XCTAssertEqual(Nav.adjacentIndex(count: 3, current: 0, delta: -1), 0)
    }

    func testNavMovesDown() {
        XCTAssertEqual(Nav.adjacentIndex(count: 3, current: 0, delta: 1), 1)
    }

    private func seg(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m", text: text, startSeconds: start, endSeconds: end)
    }

    func testLiveMergeEmptyFreshKeepsState() {
        let confirmed = [seg("a", 0, 1)]
        let r = LiveMerge.apply(confirmed: confirmed, fresh: [], confirmedSamples: 16000, totalSamples: 32000)
        XCTAssertEqual(r.confirmed.count, 1)
        XCTAssertEqual(r.live.count, 1)
        XCTAssertEqual(r.confirmedSamples, 16000)
    }

    func testLiveMergeSingleSegmentIsHypothesisOnly() {
        let r = LiveMerge.apply(confirmed: [], fresh: [seg("hi", 0, 2)], confirmedSamples: 0, totalSamples: 48000)
        XCTAssertTrue(r.confirmed.isEmpty)
        XCTAssertEqual(r.live.map(\.text), ["hi"])
        XCTAssertEqual(r.confirmedSamples, 0)
    }

    func testLiveMergeConfirmsAllButLast() {
        let fresh = [seg("one", 0, 2), seg("two", 2, 4), seg("three", 4, 6)]
        let r = LiveMerge.apply(confirmed: [], fresh: fresh, confirmedSamples: 0, totalSamples: 1_000_000)
        XCTAssertEqual(r.confirmed.map(\.text), ["one", "two"])
        XCTAssertEqual(r.live.map(\.text), ["one", "two", "three"])
        XCTAssertEqual(r.confirmedSamples, Int(4.0 * 16000))
    }

    func testLiveMergeConfirmedSamplesCappedAtTotal() {
        let fresh = [seg("one", 0, 100), seg("two", 100, 200)]
        let r = LiveMerge.apply(confirmed: [], fresh: fresh, confirmedSamples: 0, totalSamples: 10000)
        XCTAssertEqual(r.confirmedSamples, 10000)
    }

    func testExtractTitleFromHeading() {
        XCTAssertEqual(SummaryMarkdown.extractTitle("# Планёрка по релизу\n\ntext"), "Планёрка по релизу")
    }

    func testExtractTitleStripsJunk() {
        XCTAssertEqual(SummaryMarkdown.extractTitle("#  *\"Тема\"*  \nbody"), "Тема")
    }

    func testExtractTitleNoHeadingReturnsNil() {
        XCTAssertNil(SummaryMarkdown.extractTitle("no heading here\n## Section"))
    }

    func testExtractTitleTruncatesTo80() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(SummaryMarkdown.extractTitle("# \(long)")?.count, 80)
    }

    func testMergeSortsByTime() {
        let mic = [seg("mic late", 5, 6)]
        let sys = [seg("sys early", 0, 1)]
        XCTAssertEqual(TranscriptMerge.merge(mic: mic, system: sys).map(\.text), ["sys early", "mic late"])
    }

    func testMergeDropsAcousticBleedKeepingSystem() {
        let mic = [TranscriptSegment(meetingId: "m", text: "Если взять Ninja Gaiden 4 который вышел в 2025 году",
                                     startSeconds: 0, endSeconds: 4, source: .mic)]
        let sys = [TranscriptSegment(meetingId: "m", text: "Если взять Ниндзи Гайден 4 который вышел в 2025 году",
                                     startSeconds: 1, endSeconds: 5, source: .system)]
        let merged = TranscriptMerge.merge(mic: mic, system: sys)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .system)
    }

    func testMergeKeepsDistinctSimultaneousSpeech() {
        let mic = [seg("я думаю это плохая идея честно говоря", 2, 5)]
        let sys = [seg("давайте обсудим бюджет на следующий квартал", 2, 5)]
        XCTAssertEqual(TranscriptMerge.merge(mic: mic, system: sys).count, 2)
    }

    func testMergeKeepsShortRepeats() {
        let mic = [seg("раз два", 0, 1)]
        let sys = [seg("раз два", 0, 1)]
        XCTAssertEqual(TranscriptMerge.merge(mic: mic, system: sys).count, 2)
    }

    func testMergeKeepsSamePhraseFarApart() {
        let a = [seg("это все равно максимум где-то сорок кадров приходится привыкать", 0, 4)]
        let b = [seg("это все равно максимум где-то сорок кадров приходится привыкать", 30, 34)]
        XCTAssertEqual(TranscriptMerge.merge(mic: a, system: b).count, 2)
    }

    func testMergeEmptyInputs() {
        XCTAssertTrue(TranscriptMerge.merge(mic: [], system: []).isEmpty)
        XCTAssertEqual(TranscriptMerge.merge(mic: [seg("only mic here now", 0, 2)], system: []).count, 1)
    }

    func testMergePreservesSource() {
        let mic = [TranscriptSegment(meetingId: "m", text: "my own unique words here", startSeconds: 0, endSeconds: 2, source: .mic)]
        let sys = [TranscriptSegment(meetingId: "m", text: "the other participant speaking", startSeconds: 1, endSeconds: 3, source: .system)]
        let merged = TranscriptMerge.merge(mic: mic, system: sys)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.text.contains("unique") }?.source, .mic)
        XCTAssertEqual(merged.first { $0.text.contains("other") }?.source, .system)
    }

    func testTokenize() {
        XCTAssertEqual(TranscriptMerge.tokenize("Привет, мир!"), ["привет", "мир"])
        XCTAssertEqual(TranscriptMerge.tokenize("*звук сцены*"), ["звук", "сцены"])
        XCTAssertEqual(TranscriptMerge.tokenize("Hello HELLO"), ["hello"])
        XCTAssertTrue(TranscriptMerge.tokenize("   ...  ").isEmpty)
    }

    func testJaccard() {
        XCTAssertEqual(TranscriptMerge.jaccard(["a", "b"], ["a", "b"]), 1.0, accuracy: 0.0001)
        XCTAssertEqual(TranscriptMerge.jaccard(["a"], ["b"]), 0, accuracy: 0.0001)
        XCTAssertEqual(TranscriptMerge.jaccard([], ["a"]), 0, accuracy: 0.0001)
        XCTAssertEqual(TranscriptMerge.jaccard(["a", "b"], ["a"]), 0.5, accuracy: 0.0001)
    }

    func testLeadingSilence() {
        let loud: Float = 0.5, quiet: Float = 0.001
        var buf = [Float](repeating: quiet, count: 100)
        buf.append(contentsOf: [loud, loud])
        XCTAssertEqual(AudioLevel.leadingSilence(buf, threshold: 0.02, leadIn: 0), 100)
        XCTAssertEqual(AudioLevel.leadingSilence(buf, threshold: 0.02, leadIn: 30), 70)
        XCTAssertEqual(AudioLevel.leadingSilence([loud, loud, loud], threshold: 0.02, leadIn: 10), 0)
        XCTAssertEqual(AudioLevel.leadingSilence([quiet, quiet, quiet], threshold: 0.02, leadIn: 0), 3)
        XCTAssertEqual(AudioLevel.leadingSilence([], threshold: 0.02), 0)
    }

    func testLeadingSilenceDefaultLeadInKeepsContext() {
        var buf = [Float](repeating: 0.001, count: 20000)
        buf.append(0.5)
        XCTAssertEqual(AudioLevel.leadingSilence(buf, threshold: 0.02), 18400)
    }

    func testMergeBleedSameTimestampKeepsSystem() {
        let mic = [TranscriptSegment(meetingId: "m", text: "с нефтебазой выезжает бензовоз и привозит топливо",
                                     startSeconds: 10, endSeconds: 14, source: .mic)]
        let sys = [TranscriptSegment(meetingId: "m", text: "с нефтебазой выезжает бензовоз и привозит топливо",
                                     startSeconds: 10, endSeconds: 14, source: .system)]
        let merged = TranscriptMerge.merge(mic: mic, system: sys)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .system)
    }

    func testMergeMicOnlySpeechSurvivesLoudSystem() {
        let mic = [TranscriptSegment(meetingId: "m", text: "так проверка микрофона говорю я в тишине",
                                     startSeconds: 2, endSeconds: 6, source: .mic)]
        let sys = [TranscriptSegment(meetingId: "m", text: "вот тогда бы мы почувствовали магию габена",
                                     startSeconds: 3, endSeconds: 7, source: .system),
                   TranscriptSegment(meetingId: "m", text: "ведеокарту амд обсуждаем сегодня подробно",
                                     startSeconds: 8, endSeconds: 11, source: .system)]
        let merged = TranscriptMerge.merge(mic: mic, system: sys)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.filter { $0.source == .mic }.count, 1)
    }

    func testNavLargeDeltaClamps() {
        XCTAssertEqual(Nav.adjacentIndex(count: 3, current: 0, delta: 99), 2)
        XCTAssertEqual(Nav.adjacentIndex(count: 3, current: 2, delta: -99), 0)
    }
}

/// Post-recording pipeline stage plan (drives the "step N of M" indicator).
final class ProcessingStageTests: XCTestCase {
    func testPlanVariants() {
        XCTAssertEqual(ProcessingStage.plan(diarize: true, summarize: true), [.transcribe, .diarize, .summarize])
        XCTAssertEqual(ProcessingStage.plan(diarize: false, summarize: true), [.transcribe, .summarize])
        XCTAssertEqual(ProcessingStage.plan(diarize: true, summarize: false), [.transcribe, .diarize])
        XCTAssertEqual(ProcessingStage.plan(diarize: false, summarize: false), [.transcribe])
    }

    func testTitleKeysExistInAllLanguages() {
        for stage in [ProcessingStage.transcribe, .diarize, .summarize] {
            for lang in AppLanguage.allCases {
                XCTAssertNotNil(LocalizedStrings.table[lang]?[stage.titleKey], "\(lang) \(stage.titleKey)")
            }
        }
    }
}

/// Sage deep-link building (integration button in meeting details).
final class SageIntegrationTests: XCTestCase {
    func testOpenURLEncodesPath() throws {
        let path = "/Users/kslff/Documents/kslff-space/Работа встреча.md"
        let url = try XCTUnwrap(SageIntegration.openURL(forPath: path))
        XCTAssertEqual(url.scheme, "sage")
        XCTAssertEqual(url.host, "open")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.queryItems?.first(where: { $0.name == "path" })?.value, path)
        XCTAssertFalse(url.absoluteString.contains(" "))
    }
}
