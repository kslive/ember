@testable import Core
@testable import DesignSystem
import XCTest

/// Thorough coverage of the onboarding logic so it never regresses again:
/// language picker table, model-card state mapping, gating, catalogs, on-disk
/// paths, and localization key presence.
final class OnboardingTests: XCTestCase {
    func testLanguageOrderIsRuEnZh() {
        XCTAssertEqual(OnboardingLogic.langOrder, [.ru, .en, .zh])
    }

    func testLanguageTitlesAreEndonyms() {
        XCTAssertEqual(OnboardingLogic.title(.ru), "Русский")
        XCTAssertEqual(OnboardingLogic.title(.en), "English")
        XCTAssertEqual(OnboardingLogic.title(.zh), "中文")
    }

    func testLanguageFlags() {
        XCTAssertEqual(OnboardingLogic.flag(.ru), "🇷🇺")
        XCTAssertEqual(OnboardingLogic.flag(.en), "🇬🇧")
        XCTAssertEqual(OnboardingLogic.flag(.zh), "🇨🇳")
    }

    func testLanguageSubtitlesAllNineCombos() {
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .ru, card: .ru), "Russian")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .ru, card: .en), "Английский")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .ru, card: .zh), "Китайский · упрощённый")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .en, card: .ru), "Russian")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .en, card: .en), "English")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .en, card: .zh), "Chinese · Simplified")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .zh, card: .ru), "俄语")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .zh, card: .en), "英语")
        XCTAssertEqual(OnboardingLogic.subtitle(ui: .zh, card: .zh), "简体中文")
    }

    func testCardStateMapping() {
        XCTAssertEqual(ModelCardState.from(.absent, selected: false), .download)
        XCTAssertEqual(ModelCardState.from(.absent, selected: true), .download)
        XCTAssertEqual(ModelCardState.from(.downloading(0.42), selected: false), .downloading(0.42))
        XCTAssertEqual(ModelCardState.from(.ready, selected: false), .ready)
        XCTAssertEqual(ModelCardState.from(.ready, selected: true), .selected)
        XCTAssertEqual(ModelCardState.from(.failed("x"), selected: false), .failed)
        XCTAssertEqual(ModelCardState.from(.failed(""), selected: true), .failed)
    }

    func testNextEnabledOnlyWhenReady() {
        XCTAssertTrue(OnboardingLogic.nextEnabled(.ready))
        XCTAssertFalse(OnboardingLogic.nextEnabled(.absent))
        XCTAssertFalse(OnboardingLogic.nextEnabled(.downloading(0.9)))
        XCTAssertFalse(OnboardingLogic.nextEnabled(.failed("e")))
        XCTAssertFalse(OnboardingLogic.nextEnabled(nil))
    }

    func testSummaryCatalog() {
        XCTAssertEqual(SummaryCatalog.defaultId, "qwen3:4b")
        XCTAssertNotNil(SummaryCatalog.spec(for: SummaryCatalog.defaultId))
        XCTAssertNil(SummaryCatalog.spec(for: "nope"))
        for m in SummaryCatalog.all {
            XCTAssertFalse(m.id.isEmpty)
            XCTAssertTrue(m.repoId.hasPrefix("mlx-community/"))
            XCTAssertGreaterThan(m.sizeMB, 0)
            XCTAssertGreaterThan(m.ramHintGB, 0)
        }
        XCTAssertEqual(SummaryCatalog.all.filter { $0.badge == .recommended }.count, 1)
    }

    func testTranscriptionCatalog() {
        XCTAssertEqual(TranscriptionCatalog.defaultId, "openai_whisper-large-v3_turbo")
        XCTAssertNotNil(TranscriptionCatalog.spec(for: TranscriptionCatalog.defaultId))
        for m in TranscriptionCatalog.all {
            switch m.engine {
            case .whisperKit: XCTAssertTrue(m.id.hasPrefix("openai_whisper-"))
            case .gigaAM: XCTAssertTrue(m.id.hasPrefix("gigaam-"))
            }
            XCTAssertGreaterThan(m.sizeMB, 0)
        }
        XCTAssertEqual(TranscriptionCatalog.all.filter { $0.engine == .gigaAM }.count, 1)
    }

    func testAccentPresets() {
        XCTAssertEqual(AccentPreset.all.count, 6)
        XCTAssertEqual(Set(AccentPreset.all.map(\.id)).count, AccentPreset.all.count)
        XCTAssertEqual(AccentPreset.all.first?.id, "ember")
        XCTAssertEqual(AccentPreset.preset(id: "blue").base, "3B82F6")
        XCTAssertEqual(AccentPreset.preset(id: "nonsense").id, "ember")
        XCTAssertEqual(AccentPreset.ember.base, "F97316")
        XCTAssertEqual(AccentPreset.ember.textDark, "FB923C")
        XCTAssertEqual(AccentPreset.ember.textLight, "C2410C")
    }

    func testModelPaths() {
        let whisper = ModelPaths.whisperModelDir("openai_whisper-small").path
        XCTAssertTrue(whisper.contains("models/argmaxinc/whisperkit-coreml/openai_whisper-small"))
        XCTAssertTrue(ModelPaths.appSupport().path.hasSuffix("/Ember"))
        let mlx = ModelPaths.mlxModelDir("mlx-community/Qwen3-4B-4bit").path
        XCTAssertTrue(mlx.contains("models/mlx-community/Qwen3-4B-4bit"))
    }

    func testOnboardingLocalizationKeysPresent() {
        let keys = [
            "onb.lang.title", "onb.lang.subtitle", "onb.welcome.title", "onb.welcome.cta",
            "onb.welcome.f1", "onb.welcome.f1sub", "onb.summary.title", "onb.whisper.title", "onb.step",
            "model.download", "model.downloading", "model.failed", "model.retry", "model.select",
            "model.ready", "model.selected", "common.continue", "common.back", "common.next", "common.done",
            "meeting.model", "meeting.regenerate", "meeting.generate", "meeting.contextHint"
        ]
        for key in keys {
            XCTAssertNotNil(LocalizedStrings.en[key], "en missing \(key)")
            XCTAssertNotNil(LocalizedStrings.ru[key], "ru missing \(key)")
            XCTAssertNotNil(LocalizedStrings.zh[key], "zh missing \(key)")
        }
    }
}
