import AppKit
import Combine
import Core
import CryptoKit
import Foundation
import UserNotifications

/// Custom GitHub-Releases auto-updater (NO Sparkle). Sparkle requires Developer-ID
/// signing + notarization, which we don't do (ad-hoc only) — so we mirror the Sage
/// app's approach: check the GitHub Releases API, download a .zip, verify SHA-256,
/// stage it, and replace /Applications/Ember.app from a detached helper at quit.
/// Ad-hoc friendly (quarantine is stripped → no Gatekeeper block on relaunch).
@MainActor
public final class UpdaterService: ObservableObject {
    /// "What's new" announcement payload: the GitHub release body of the version the
    /// user just updated INTO. Shown once per version, then dismissed for good.
    public struct WhatsNew: Equatable {
        public let version: String
        public let body: String
    }

    @Published public private(set) var phase: UpdaterPhase = .idle
    @Published public private(set) var whatsNew: WhatsNew?
    @Published public var autoUpdate: Bool {
        didSet { UserDefaults.standard.set(autoUpdate, forKey: Keys.autoUpdate) }
    }

    private let engine = UpdateEngine()
    private var task: Task<Void, Never>?
    private var stagedApp: URL?
    private var bgTimer: Timer?
    /// Background-check throttle AND timer period. 30 min (was 6h): one anonymous
    /// GitHub request per half-hour is nothing rate-limit-wise, and the old 6h window
    /// meant the Home update pill stayed hidden for hours after a release.
    private let backgroundInterval: TimeInterval = 30 * 60

    public init() {
        autoUpdate = (UserDefaults.standard.object(forKey: Keys.autoUpdate) as? Bool) ?? true
        if let last = lastCheck { phase = .upToDate(last) }
        if UserDefaults.standard.string(forKey: Keys.pendingVersion) == currentVersion {
            UserDefaults.standard.removeObject(forKey: Keys.pendingVersion)
            UserDefaults.standard.removeObject(forKey: Keys.pendingPath)
        }
        Self.selfHeal()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInBackground() }
        }
        let timer = Timer(timeInterval: backgroundInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkInBackground() }
        }
        RunLoop.main.add(timer, forMode: .common)
        bgTimer = timer
        // Cold launch: ALWAYS check (past the throttle) — a fresh launch must surface
        // an available update on the Home banner right away; the throttle previously
        // hid it until the next background window.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { self?.check(silent: true) }
        }
        Task { [weak self] in await self?.maybeLoadWhatsNew() }
    }

    /// Loads the "What's new" announcement once per version. A FRESH install (not yet
    /// onboarded) never announces its own starting version — only real updates do.
    /// Offline → not marked, so it shows on the next online launch instead.
    private func maybeLoadWhatsNew() async {
        guard UserDefaults.standard.bool(forKey: "ember.onboarded") else {
            UserDefaults.standard.set(currentVersion, forKey: Keys.lastAnnounced)
            return
        }
        guard UserDefaults.standard.string(forKey: Keys.lastAnnounced) != currentVersion else { return }
        do {
            guard let body = try await engine.notes(forVersion: currentVersion),
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                UserDefaults.standard.set(currentVersion, forKey: Keys.lastAnnounced)
                return
            }
            whatsNew = WhatsNew(version: currentVersion, body: body)
        } catch {
            // network hiccup — retry silently on a future launch
        }
    }

    public func dismissWhatsNew() {
        UserDefaults.standard.set(currentVersion, forKey: Keys.lastAnnounced)
        whatsNew = nil
    }

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }

    public var lastCheck: Date? {
        UserDefaults.standard.object(forKey: Keys.lastCheck) as? Date
    }

    /// Background check (focus/timer) — throttled to once per `backgroundInterval`;
    /// in auto mode it downloads + stages silently → `.readyToInstall`.
    public func checkInBackground() {
        guard UpdateLogic.shouldCheck(last: lastCheck, interval: backgroundInterval, now: Date()) else { return }
        check(silent: true)
    }

    /// Explicit "Check for updates" button (no throttle).
    public func checkNow() {
        check(silent: false)
    }

    /// Banner "Update" button.
    public func update() {
        if case let .available(r) = phase { downloadAndInstall(r) }
    }

    /// "Restart" — apply the staged update after quit and relaunch.
    public func restart() {
        guard prepareForRestart() else { return }
        NSApplication.shared.terminate(nil)
    }

    private func check(silent: Bool) {
        switch phase {
        case .downloading, .installing: return
        default: break
        }
        task?.cancel()
        if !silent { phase = .checking }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await engine.checkForUpdate(current: currentVersion, channel: .stable)
                UserDefaults.standard.set(Date(), forKey: Keys.lastCheck)
                guard let release else { phase = .upToDate(Date()); return }
                if UserDefaults.standard.string(forKey: Keys.pendingVersion) == release.version,
                   let path = UserDefaults.standard.string(forKey: Keys.pendingPath),
                   FileManager.default.fileExists(atPath: path) {
                    stagedApp = URL(fileURLWithPath: path)
                    phase = .readyToInstall(release)
                } else if silent, autoUpdate {
                    downloadAndInstall(release)
                } else {
                    phase = .available(release)
                    if silent { Self.notifyAvailable(release.version) }
                }
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                if !silent { phase = .failed(Self.message(error)) }
            }
        }
    }

    private func downloadAndInstall(_ release: UpdateRelease) {
        task?.cancel()
        phase = .downloading(0)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var zip: URL?
                for try await event in engine.downloadAndVerify(release) {
                    switch event {
                    case let .progress(p): phase = .downloading(p.fraction)
                    case let .finished(url): zip = url
                    }
                }
                guard let zip else { phase = .failed(Self.message(UpdateError.installFailed("download"))); return }
                phase = .installing
                let staged = try await engine.stage(zipURL: zip)
                stagedApp = staged
                UserDefaults.standard.set(release.version, forKey: Keys.pendingVersion)
                UserDefaults.standard.set(staged.path, forKey: Keys.pendingPath)
                phase = .readyToInstall(release)
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                phase = .failed(Self.message(error))
            }
        }
    }

    @discardableResult
    private func prepareForRestart() -> Bool {
        let path = stagedApp?.path ?? UserDefaults.standard.string(forKey: Keys.pendingPath)
        guard let path else { return false }
        guard let dest = Self.installDestination() else {
            phase = .failed(LocalizedStrings.current("update.err.translocated"))
            return false
        }
        UserDefaults.standard.removeObject(forKey: Keys.pendingVersion)
        UserDefaults.standard.removeObject(forKey: Keys.pendingPath)
        UpdateEngine.applyOnQuit(stagedAppPath: path, destPath: dest, relaunch: true)
        return true
    }

    /// Call from `applicationWillTerminate`: if an update is staged, apply it on quit
    /// (relaunch:false → takes effect next launch). Installs into the REAL running bundle
    /// (not a hardcoded /Applications path); skips if the app is translocated.
    public static func applyPendingOnQuit() {
        guard let path = UserDefaults.standard.string(forKey: Keys.pendingPath),
              FileManager.default.fileExists(atPath: path),
              let dest = installDestination() else { return }
        UpdateEngine.applyOnQuit(stagedAppPath: path, destPath: dest, relaunch: false)
        UserDefaults.standard.removeObject(forKey: Keys.pendingPath)
        UserDefaults.standard.removeObject(forKey: Keys.pendingVersion)
    }

    /// Real on-disk path of the running bundle, or nil if App Translocation is active
    /// (the app runs from a read-only random `/private/var/folders/…` path) — writing
    /// there would create a ghost copy instead of updating the real app.
    static func installDestination() -> String? {
        let url = Bundle.main.bundleURL.resolvingSymlinksInPath()
        if url.path.hasPrefix("/private/var/folders/") || url.path.contains("/AppTranslocation/") { return nil }
        return url.path
    }

    /// Repairs leftovers from an interrupted quit-swap: if the running bundle is present,
    /// remove stale `*.app.bak`/`*.app.new` siblings; if it's somehow missing but a
    /// `.bak` exists, restore it.
    private static func selfHeal() {
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let bak = URL(fileURLWithPath: app.path + ".bak")
        let new = URL(fileURLWithPath: app.path + ".new")
        if fm.fileExists(atPath: app.path) {
            try? fm.removeItem(at: bak); try? fm.removeItem(at: new)
        } else if fm.fileExists(atPath: bak.path) {
            try? fm.moveItem(at: bak, to: app); try? fm.removeItem(at: new)
        }
    }

    /// One notification per version when an update is found in manual (non-auto) mode.
    private static func notifyAvailable(_ version: String) {
        let key = "ember.update.notified"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)
        let c = UNMutableNotificationContent()
        c.title = "Ember"
        c.body = LocalizedStrings.current("update.notify").replacingOccurrences(of: "{v}", with: version)
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private static func message(_ error: Error) -> String {
        let key = switch error as? UpdateError {
        case .checksumMismatch: "update.err.checksum"
        case .missingChecksum: "update.err.missingChecksum"
        case .noAppInArchive: "update.err.noApp"
        case .installFailed: "update.err.install"
        default: "update.err.network"
        }
        return LocalizedStrings.current(key)
    }

    enum Keys {
        static let autoUpdate = "ember.update.autoUpdate"
        static let lastCheck = "ember.update.lastCheck"
        static let pendingVersion = "ember.update.pending.version"
        static let pendingPath = "ember.update.pending.path"
        static let lastAnnounced = "ember.update.lastAnnounced"
    }
}
