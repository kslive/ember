import Combine
import Foundation

/// User preferences persisted in UserDefaults. The chosen model ids are also
/// read directly (by key) from the recording pipeline.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let summaryKey = "ember.summaryModel"
    public static let whisperKey = "ember.whisperModel"
    public static let autoSummaryKey = "ember.autoSummary"
    public static let notificationsKey = "ember.notifications"
    public static let notifyOnStartKey = "ember.notifyOnStart"
    public static let exportFolderKey = "ember.exportFolder"
    public static let micDeviceKey = "ember.micDevice"
    public static let systemDeviceKey = "ember.systemDevice"
    public static let deferredProcessingKey = "ember.deferredProcessing"
    public static let summaryTemplateKey = "ember.summaryTemplate"
    public static let calendarTitlesKey = "ember.calendarTitles"
    public static let deepseekModelKey = "ember.deepseekModel"
    public static let liveOverlayKey = "ember.liveOverlay"
    public static let liveOverlayModelKey = "ember.liveOverlayModel"
    public static let liveOverlayLocalModelKey = "ember.liveOverlayLocalModel"
    private static let deepseekAccount = "deepseek-api-key"

    @Published public var summaryModelId: String {
        didSet { UserDefaults.standard.set(summaryModelId, forKey: Self.summaryKey) }
    }

    @Published public var whisperModelId: String {
        didSet { UserDefaults.standard.set(whisperModelId, forKey: Self.whisperKey) }
    }

    @Published public var calendarTitlesEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarTitlesEnabled, forKey: Self.calendarTitlesKey) }
    }

    @Published public var autoSummary: Bool {
        didSet { UserDefaults.standard.set(autoSummary, forKey: Self.autoSummaryKey) }
    }

    @Published public var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Self.notificationsKey) }
    }

    /// "Remind participants that recording started" prompt before each recording.
    @Published public var notifyOnStart: Bool {
        didSet { UserDefaults.standard.set(notifyOnStart, forKey: Self.notifyOnStartKey) }
    }

    /// Folder where exported meeting `.md` summaries are written.
    @Published public var exportFolderPath: String {
        didSet { UserDefaults.standard.set(exportFolderPath, forKey: Self.exportFolderKey) }
    }

    /// Preferred device UIDs ("" = system default).
    @Published public var preferredMicUID: String {
        didSet { UserDefaults.standard.set(preferredMicUID, forKey: Self.micDeviceKey) }
    }

    @Published public var preferredSystemUID: String {
        didSet { UserDefaults.standard.set(preferredSystemUID, forKey: Self.systemDeviceKey) }
    }

    /// Queue heavy post-processing (re-pass + summary) until no
    /// recording is active — back-to-back calls stay smooth. Default OFF.
    @Published public var deferredProcessing: Bool {
        didSet { UserDefaults.standard.set(deferredProcessing, forKey: Self.deferredProcessingKey) }
    }

    /// Default summary template id ("standard" = built-in). Per-meeting choices
    /// override this; new meetings inherit it.
    @Published public var summaryTemplateId: String {
        didSet { UserDefaults.standard.set(summaryTemplateId, forKey: Self.summaryTemplateKey) }
    }

    /// DeepSeek model id chosen from the key's GET /models list ("" = none picked).
    @Published public var deepseekModel: String {
        didSet { UserDefaults.standard.set(deepseekModel, forKey: Self.deepseekModelKey) }
    }

    /// Live-context overlay over all windows during recording. Default OFF.
    @Published public var liveOverlay: Bool {
        didSet { UserDefaults.standard.set(liveOverlay, forKey: Self.liveOverlayKey) }
    }

    /// Overlay model route: "auto" (cloud → local), "cloud" (DeepSeek only) or
    /// "local" (a downloaded local model).
    @Published public var liveOverlayModel: String {
        didSet { UserDefaults.standard.set(liveOverlayModel, forKey: Self.liveOverlayModelKey) }
    }

    /// Which LOCAL model the overlay uses (its own pick, independent from the
    /// summary model — the overlay wants small & fast).
    @Published public var liveOverlayLocalModel: String {
        didSet { UserDefaults.standard.set(liveOverlayLocalModel, forKey: Self.liveOverlayLocalModelKey) }
    }

    public init() {
        summaryModelId = UserDefaults.standard.string(forKey: Self.summaryKey) ?? SummaryCatalog.defaultId
        whisperModelId = UserDefaults.standard.string(forKey: Self.whisperKey) ?? TranscriptionCatalog.defaultId
        autoSummary = (UserDefaults.standard.object(forKey: Self.autoSummaryKey) as? Bool) ?? true
        notificationsEnabled = (UserDefaults.standard.object(forKey: Self.notificationsKey) as? Bool) ?? true
        notifyOnStart = (UserDefaults.standard.object(forKey: Self.notifyOnStartKey) as? Bool) ?? true
        exportFolderPath = UserDefaults.standard.string(forKey: Self.exportFolderKey) ?? Self.defaultExportFolder()
        preferredMicUID = UserDefaults.standard.string(forKey: Self.micDeviceKey) ?? ""
        preferredSystemUID = UserDefaults.standard.string(forKey: Self.systemDeviceKey) ?? ""
        deferredProcessing = (UserDefaults.standard.object(forKey: Self.deferredProcessingKey) as? Bool) ?? false
        summaryTemplateId = UserDefaults.standard.string(forKey: Self.summaryTemplateKey) ?? SummaryTemplates.standardId
        calendarTitlesEnabled = (UserDefaults.standard.object(forKey: Self.calendarTitlesKey) as? Bool) ?? false
        deepseekModel = UserDefaults.standard.string(forKey: Self.deepseekModelKey) ?? ""
        liveOverlay = (UserDefaults.standard.object(forKey: Self.liveOverlayKey) as? Bool) ?? false
        liveOverlayModel = UserDefaults.standard.string(forKey: Self.liveOverlayModelKey) ?? "auto"
        liveOverlayLocalModel = UserDefaults.standard.string(forKey: Self.liveOverlayLocalModelKey)
            ?? LiveContextLogic.localModelId
    }

    /// Meeting titles from Apple Calendar (opt-in; default off).
    public static func calendarTitlesOn() -> Bool {
        (UserDefaults.standard.object(forKey: calendarTitlesKey) as? Bool) ?? false
    }

    /// DeepSeek API key (device-bound encrypted file — see SecretStore). nil = cloud path disabled.
    public static func deepseekKey() -> String? {
        let v = SecretStore.get(deepseekAccount) ?? ""
        return v.isEmpty ? nil : v
    }

    public static func setDeepseekKey(_ key: String) {
        SecretStore.set(key, account: deepseekAccount)
    }

    public static func deleteDeepseekKey() {
        SecretStore.delete(deepseekAccount)
        UserDefaults.standard.removeObject(forKey: deepseekModelKey)
    }

    /// Chosen DeepSeek model id, or nil when none stored.
    public static func deepseekModelId() -> String? {
        let v = UserDefaults.standard.string(forKey: deepseekModelKey) ?? ""
        return v.isEmpty ? nil : v
    }

    public static func currentSummaryModelId() -> String {
        let stored = UserDefaults.standard.string(forKey: summaryKey) ?? SummaryCatalog.defaultId
        return SummaryCatalog.spec(for: stored) != nil ? stored : SummaryCatalog.defaultId
    }

    public static func currentWhisperModelId() -> String {
        let stored = UserDefaults.standard.string(forKey: whisperKey) ?? TranscriptionCatalog.defaultId
        return TranscriptionCatalog.spec(for: stored) != nil ? stored : TranscriptionCatalog.defaultId
    }

    public static func notificationsOn() -> Bool {
        (UserDefaults.standard.object(forKey: notificationsKey) as? Bool) ?? true
    }

    public static func notifyOnStartOn() -> Bool {
        (UserDefaults.standard.object(forKey: notifyOnStartKey) as? Bool) ?? true
    }

    public static func autoSummaryOn() -> Bool {
        (UserDefaults.standard.object(forKey: autoSummaryKey) as? Bool) ?? true
    }

    public static func deferredProcessingOn() -> Bool {
        (UserDefaults.standard.object(forKey: deferredProcessingKey) as? Bool) ?? false
    }

    public static func liveOverlayOn() -> Bool {
        (UserDefaults.standard.object(forKey: liveOverlayKey) as? Bool) ?? false
    }

    /// Overlay model route ("auto" / "cloud" / "local"); unknown values → "auto".
    public static func liveOverlayModelRoute() -> String {
        let v = UserDefaults.standard.string(forKey: liveOverlayModelKey) ?? "auto"
        return ["auto", "cloud", "local"].contains(v) ? v : "auto"
    }

    /// The overlay's local model pick (validated against the ALLOWED 1.7B pair —
    /// larger models are post-summary-only, too slow for live).
    public static func liveOverlayLocalModelId() -> String {
        let v = UserDefaults.standard.string(forKey: liveOverlayLocalModelKey) ?? LiveContextLogic.localModelId
        return LiveContextLogic.allowedLocalIds.contains(v) ? v : LiveContextLogic.localModelId
    }

    public static func currentSummaryTemplateId() -> String {
        let v = UserDefaults.standard.string(forKey: summaryTemplateKey) ?? ""
        return v.isEmpty ? SummaryTemplates.standardId : v
    }

    /// Preferred microphone device UID, or nil for the system default.
    public static func preferredMicUID() -> String? {
        let v = UserDefaults.standard.string(forKey: micDeviceKey) ?? ""
        return v.isEmpty ? nil : v
    }

    /// `~/Documents/Ember` — a dedicated subfolder, NOT bare Documents: exports
    /// are laid out in per-day date folders, and sprawling `15.07.2026/` dirs
    /// directly in the user's Documents root would read as clutter. Only applies
    /// while the user has never picked a folder; an explicit choice always wins.
    public static func defaultExportFolder() -> String {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Ember").path
    }

    /// Chosen export folder (falls back to ~/Documents/Ember).
    public static func exportFolder() -> String {
        let v = UserDefaults.standard.string(forKey: exportFolderKey) ?? ""
        return v.isEmpty ? defaultExportFolder() : v
    }
}
