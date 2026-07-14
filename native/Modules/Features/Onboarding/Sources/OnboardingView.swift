import Core
import DesignSystem
import SummaryService
import SwiftUI
import TranscriptionService

public struct OnboardingView: View {
    @EnvironmentObject private var locale: LocaleManager
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var transcription: TranscriptionService
    @ObservedObject private var summary: SummaryService
    private let onComplete: () -> Void

    @State private var step: Step = .language
    @State private var goingBack = false

    /// Fixed language order from the mockup: Russian, English, Chinese.
    private let langOrder = OnboardingLogic.langOrder

    enum Step { case language, welcome, summary, whisper }

    public init(transcription: TranscriptionService, summary: SummaryService, onComplete: @escaping () -> Void) {
        self.transcription = transcription
        self.summary = summary
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            EmberColor.bg.ignoresSafeArea()

            Group {
                switch step {
                case .language: centered(maxWidth: 440) { languageStep }
                case .welcome: centered(maxWidth: 440) { welcomeStep }
                case .summary:
                    modelStep(badge: stepLabel(2), title: locale.t("onb.summary.title"), subtitle: locale.t("onb.summary.subtitle"),
                              cards: summaryCards, stateFor: summaryCardState, action: summaryAction, errorFor: summaryError,
                              back: { goBack(to: .welcome) { summary.cancelAllDownloads() } },
                              nextTitle: locale.t("common.next"), finish: false,
                              nextEnabled: summary.states[settings.summaryModelId] == .ready,
                              next: { advance(to: .whisper) })
                case .whisper:
                    modelStep(badge: stepLabel(3), title: locale.t("onb.whisper.title"), subtitle: locale.t("onb.whisper.subtitle"),
                              cards: whisperCards, stateFor: whisperCardState, action: whisperAction, errorFor: whisperError,
                              back: { goBack(to: .summary) { transcription.cancelAllDownloads() } },
                              nextTitle: locale.t("common.done"), finish: true,
                              nextEnabled: transcription.states[settings.whisperModelId] == .ready,
                              next: finishOnboarding)
                }
            }
            .id(step)
            .transition(stepTransition)

            if step != .language {
                OnboardingDots(active: activeIndex)
                    .padding(.bottom, 36)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.32), value: step)
    }

    private var activeIndex: Int {
        switch step {
        case .language, .welcome: 0
        case .summary: 1
        case .whisper: 2
        }
    }

    private var stepTransition: AnyTransition {
        let dx: CGFloat = 30
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: goingBack ? -dx : dx)),
            removal: .opacity.combined(with: .offset(x: goingBack ? dx : -dx))
        )
    }

    private func advance(to s: Step) {
        goingBack = false; step = s
    }

    private func goBack(to s: Step, cancel: () -> Void) {
        cancel(); goingBack = true; step = s
    }

    private func stepLabel(_ n: Int) -> String {
        locale.t("onb.step", ["n": "\(n)", "t": "3"])
    }

    private func centered(maxWidth: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        VStack { content() }
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 60)
    }

    private var languageStep: some View {
        VStack(spacing: 14) {
            iconBox(.globe)
            Text(locale.t("onb.lang.title")).font(EmberType.semibold(30)).tracking(-0.75).foregroundStyle(EmberColor.text)
            Text(locale.t("onb.lang.subtitle")).font(EmberType.regular(15)).lineSpacing(3)
                .foregroundStyle(EmberColor.text2).multilineTextAlignment(.center).padding(.bottom, 2)

            VStack(spacing: 10) {
                ForEach(langOrder) { languageCard($0) }
            }
            .padding(.bottom, 8)

            OnboardingCTA(locale.t("common.continue")) {
                locale.setLanguage(locale.language)
                advance(to: .welcome)
            }
        }
    }

    private func languageCard(_ lang: AppLanguage) -> some View {
        let sel = locale.language == lang
        return Button { withAnimation(.easeInOut(duration: 0.25)) { locale.setLanguage(lang) } } label: {
            HStack(spacing: 14) {
                Text(flag(lang)).font(.system(size: 22)).frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(langTitle(lang)).font(EmberType.semibold(15)).foregroundStyle(EmberColor.text)
                    Text(langSubtitle(lang)).font(EmberType.regular(12.5)).foregroundStyle(EmberColor.text2)
                }
                Spacer()
                if sel {
                    Circle().fill(EmberColor.accent).frame(width: 24, height: 24)
                        .overlay(EmberIcon(.check, size: 13, lineWidth: 2.6, color: .white))
                } else {
                    Circle().strokeBorder(EmberColor.borderStrong, lineWidth: 1.5).frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .background(sel ? EmberColor.accentWeak : EmberColor.surface2)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(sel ? EmberColor.accent : EmberColor.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .emberHover(cornerRadius: 14)
        .animation(.easeInOut(duration: 0.2), value: sel)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18)
                .fill(RadialGradient(colors: [Color(hex: "FDBA74"), Color(hex: "F97316"), Color(hex: "EA580C")],
                                     center: .init(x: 0.36, y: 0.30), startRadius: 1, endRadius: 64))
                .frame(width: 60, height: 60)
                .shadow(color: EmberColor.accent.opacity(0.4), radius: 18, x: 0, y: 12)
                .overlay(EmberIcon(.mic, size: 30, lineWidth: 2, color: .white))

            Text(locale.t("onb.welcome.title")).font(EmberType.semibold(32)).tracking(-0.8).foregroundStyle(EmberColor.text)
            Text(locale.t("onb.welcome.subtitle")).font(EmberType.regular(15)).lineSpacing(3)
                .foregroundStyle(EmberColor.text2).multilineTextAlignment(.center)

            VStack(spacing: 14) {
                featureRow(.lock, locale.t("onb.welcome.f1"), locale.t("onb.welcome.f1sub"))
                featureRow(.bolt, locale.t("onb.welcome.f2"), locale.t("onb.welcome.f2sub"))
                featureRow(.file, locale.t("onb.welcome.f3"), locale.t("onb.welcome.f3sub"))
            }
            .padding(.vertical, 8)

            OnboardingCTA(locale.t("onb.welcome.cta")) { advance(to: .summary) }
        }
        .padding(.bottom, 24)
    }

    private func featureRow(_ glyph: EmberIcon.Glyph, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 13) {
            EmberIcon(glyph, size: 17, lineWidth: 1.8, color: EmberColor.accentText)
                .frame(width: 38, height: 38)
                .background(EmberColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EmberType.medium(14)).foregroundStyle(EmberColor.text)
                Text(sub).font(EmberType.regular(12.5)).foregroundStyle(EmberColor.text3)
            }
            Spacer()
        }
    }

    struct CardVM: Identifiable { let id: String; let name: String; let desc: String; let meta: String; let badge: String?; let sizeMB: Int }

    private func modelStep(badge: String, title: String, subtitle: String,
                           cards: [CardVM], stateFor: @escaping (String) -> ModelCardState, action: @escaping (CardVM) -> Void,
                           errorFor: @escaping (String) -> String?,
                           back: @escaping () -> Void, nextTitle: String, finish: Bool, nextEnabled: Bool, next: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(badge).font(EmberType.mono(11)).tracking(1.1).textCase(.uppercase).foregroundStyle(EmberColor.accentText)
                Text(title).font(EmberType.semibold(28)).tracking(-0.56).foregroundStyle(EmberColor.text).padding(.top, 12)
                Text(subtitle).font(EmberType.regular(14.5)).lineSpacing(3).foregroundStyle(EmberColor.text2).padding(.top, 8).padding(.bottom, 28)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(cards) { c in
                            EmberModelCard(name: c.name, desc: c.desc, meta: c.meta, badge: c.badge,
                                           state: stateFor(c.id), totalMB: c.sizeMB, errorText: errorFor(c.id),
                                           onAction: { action(c) })
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 54)
            .padding(.horizontal, 80)

            OnboardingFooter(backTitle: locale.t("common.back"), onBack: back,
                             dotsActive: 0, nextTitle: nextTitle, nextIsFinish: finish, nextEnabled: nextEnabled,
                             showDots: false, onNext: next)
        }
    }

    private func summaryError(_ id: String) -> String? {
        if case let .failed(m) = (summary.states[id] ?? .absent) { return m.isEmpty ? nil : m }
        return nil
    }

    private func whisperError(_ id: String) -> String? {
        if case let .failed(m) = (transcription.states[id] ?? .absent) { return m.isEmpty ? nil : m }
        return nil
    }

    private func summaryCardState(_ id: String) -> ModelCardState {
        ModelCardState.from(summary.states[id] ?? .absent, selected: id == settings.summaryModelId)
    }

    private func summaryAction(_ c: CardVM) {
        switch summary.states[c.id] ?? .absent {
        case .ready:
            settings.summaryModelId = c.id
        case .absent, .failed:
            settings.summaryModelId = c.id
            if let repo = SummaryCatalog.spec(for: c.id)?.repoId {
                summary.startDownload(id: c.id, repoId: repo)
            }
        case .downloading:
            if let repo = SummaryCatalog.spec(for: c.id)?.repoId { summary.cancelDownload(id: c.id, repoId: repo) }
        }
    }

    private func whisperCardState(_ id: String) -> ModelCardState {
        ModelCardState.from(transcription.states[id] ?? .absent, selected: id == settings.whisperModelId)
    }

    private func whisperAction(_ c: CardVM) {
        switch transcription.states[c.id] ?? .absent {
        case .ready:
            settings.whisperModelId = c.id
        case .absent, .failed:
            settings.whisperModelId = c.id
            transcription.startDownload(c.id)
        case .downloading:
            transcription.cancelDownload(c.id)
        }
    }

    /// Finishes onboarding. The selected Whisper model is required to be ready
    /// (the footer gates this); the summary model downloads in the background.
    private func finishOnboarding() {
        let s = settings.summaryModelId
        if summary.states[s] != .ready, let repo = SummaryCatalog.spec(for: s)?.repoId {
            summary.startDownload(id: s, repoId: repo)
        }
        onComplete()
    }

    private var summaryCards: [CardVM] {
        SummaryCatalog.all.map { m in
            CardVM(id: m.id, name: m.displayName,
                   desc: (m.noteKey.map { locale.t($0) + " · " } ?? "")
                       + locale.t("model.ramHint", ["g": "\(m.ramHintGB)"]),
                   meta: "\(m.sizeMB) \(sizeUnit) · \(m.contextTokens) \(locale.t("model.tokens"))", badge: badgeText(m.badge), sizeMB: m.sizeMB)
        }
    }

    private var whisperCards: [CardVM] {
        TranscriptionCatalog.all.map { m in
            CardVM(id: m.id, name: m.displayName,
                   desc: m.engine == .gigaAM
                       ? locale.t("model.gigaam.desc") + " · " + locale.t("model.ramHint", ["g": "\(m.ramHintGB)"])
                       : locale.t("model.ramHint", ["g": "\(m.ramHintGB)"]),
                   meta: "\(m.sizeMB) \(sizeUnit)", badge: badgeText(m.badge), sizeMB: m.sizeMB)
        }
    }

    private func iconBox(_ glyph: EmberIcon.Glyph) -> some View {
        EmberIcon(glyph, size: 26, lineWidth: 1.7, color: EmberColor.accentText)
            .frame(width: 54, height: 54)
            .background(EmberColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 6)
    }

    private var sizeUnit: String {
        locale.language == .ru ? "МБ" : "MB"
    }

    private func badgeText(_ b: ModelBadge?) -> String? {
        guard let b else { return nil }
        return locale.t(b == .recommended ? "model.badge.recommended" : "model.badge.balanced")
    }

    private func flag(_ l: AppLanguage) -> String {
        OnboardingLogic.flag(l)
    }

    private func langTitle(_ l: AppLanguage) -> String {
        OnboardingLogic.title(l)
    }

    private func langSubtitle(_ card: AppLanguage) -> String {
        OnboardingLogic.subtitle(ui: locale.language, card: card)
    }
}
