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
    public static let diarizationKey = "ember.diarization"
    public static let deepseekModelKey = "ember.deepseekModel"
    private static let deepseekAccount = "deepseek-api-key"

    @Published public var summaryModelId: String {
        didSet { UserDefaults.standard.set(summaryModelId, forKey: Self.summaryKey) }
    }

    @Published public var whisperModelId: String {
        didSet { UserDefaults.standard.set(whisperModelId, forKey: Self.whisperKey) }
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

    /// Distinguish different remote voices ("Собеседник 1/2/3") via on-device diarization.
    @Published public var diarizationEnabled: Bool {
        didSet { UserDefaults.standard.set(diarizationEnabled, forKey: Self.diarizationKey) }
    }

    /// DeepSeek model id chosen from the key's GET /models list ("" = none picked).
    @Published public var deepseekModel: String {
        didSet { UserDefaults.standard.set(deepseekModel, forKey: Self.deepseekModelKey) }
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
        diarizationEnabled = (UserDefaults.standard.object(forKey: Self.diarizationKey) as? Bool) ?? true
        deepseekModel = UserDefaults.standard.string(forKey: Self.deepseekModelKey) ?? ""
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

    public static func diarizationOn() -> Bool {
        (UserDefaults.standard.object(forKey: diarizationKey) as? Bool) ?? true
    }

    /// Preferred microphone device UID, or nil for the system default.
    public static func preferredMicUID() -> String? {
        let v = UserDefaults.standard.string(forKey: micDeviceKey) ?? ""
        return v.isEmpty ? nil : v
    }

    public static func defaultExportFolder() -> String {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).path
    }

    /// Chosen export folder (falls back to Documents).
    public static func exportFolder() -> String {
        let v = UserDefaults.standard.string(forKey: exportFolderKey) ?? ""
        return v.isEmpty ? defaultExportFolder() : v
    }
}
