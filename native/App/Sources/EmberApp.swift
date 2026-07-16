import AppKit
import AudioService
import Core
import DesignSystem
import OnboardingFeature
import SwiftUI
import UpdaterService
import UserNotifications

/// Sets the notification-center delegate so notifications also appear while the
/// app is frontmost (otherwise macOS suppresses them).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Wired by AppModel.init — quit must drain in-flight ONNX/MLX work first.
    weak static var model: AppModel?

    func applicationDidFinishLaunching(_: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Quit during post-processing crashed the app: exit() runs C++ static
    /// destructors (ONNX's schema registry) while a sherpa-onnx decode is still
    /// inside Ort::Session::Run on another thread — ORT throws into the dying
    /// runtime and the process SIGABRTs. Abort the pipeline, let the last decode
    /// drain (bounded), then finish quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.beginQuitDrain() else { return .terminateNow }
        Task { @MainActor in
            await model.awaitQuitDrain()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        RecordingEngine.purgeRecordings()
        UpdaterService.applyPendingOnQuit()
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct EmberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var locale = LocaleManager()
    @StateObject private var theme = ThemeManager()
    @StateObject private var settings = SettingsStore()
    @StateObject private var updater = UpdaterService()
    @StateObject private var templates = TemplateStore()
    @StateObject private var model = AppModel()
    @AppStorage("ember.onboarded") private var onboarded = false

    init() {
        setenv("CI_DISABLE_NETWORK_MONITOR", "1", 1)
        EmberFonts.register()
    }

    var body: some Scene {
        Window("Ember", id: "main") {
            Group {
                if onboarded {
                    AppShell(model: model)
                } else {
                    OnboardingView(transcription: model.transcription, summary: model.summary,
                                   onComplete: { onboarded = true })
                }
            }
            .environmentObject(locale)
            .environmentObject(theme)
            .environmentObject(settings)
            .environmentObject(updater)
            .environmentObject(templates)
            .preferredColorScheme(theme.theme.colorScheme)
            .id(theme.accentId)
            .frame(minWidth: 920, minHeight: 600)
            .task { if onboarded { updater.checkInBackground() } }
            .onChange(of: locale.language) { _, _ in templates.reload() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent(model: model, locale: locale, onboarded: onboarded)
        } label: {
            Image(systemName: model.isRecordingActive ? "waveform.circle.fill" : "waveform")
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var locale: LocaleManager
    var onboarded: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if onboarded {
            fullMenu
        } else {
            Button(locale.t("menubar.quit")) { NSApplication.shared.terminate(nil) }
        }
    }

    @ViewBuilder private var fullMenu: some View {
        if model.isRecordingActive {
            if model.engine.status == .paused {
                Button(locale.t("menubar.resume")) { model.engine.resume() }
            } else {
                Button(locale.t("menubar.pause")) { model.engine.pause() }
            }
            Button(locale.t("menubar.stop")) {
                model.stopRecording(language: locale.language)
                activateApp()
            }
        } else {
            Button(locale.t("menubar.start")) {
                activateApp()
                model.startRecording()
            }
        }
        Divider()
        Button(locale.t("menubar.settings")) { model.route = .settings; activateApp() }
        Button(locale.t("menubar.show")) { activateApp() }
        Divider()
        Button(locale.t("menubar.quit")) { NSApplication.shared.terminate(nil) }
    }

    /// The red-X close DEALLOCATES the SwiftUI window — `NSApp.windows` then has
    /// no main window, so makeKeyAndOrderFront alone showed nothing. openWindow on
    /// the single Window scene recreates it (or brings the live one to front).
    private func activateApp() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
