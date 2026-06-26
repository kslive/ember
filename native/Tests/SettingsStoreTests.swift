@testable import Core
import XCTest

/// SettingsStore static getters (UserDefaults-backed): defaults, stored reads, and
/// catalog validation of the persisted model ids.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private let touchedKeys = [
        SettingsStore.notificationsKey, SettingsStore.notifyOnStartKey,
        SettingsStore.micDeviceKey, SettingsStore.exportFolderKey,
        SettingsStore.summaryKey, SettingsStore.whisperKey
    ]

    override func tearDown() {
        for key in touchedKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testNotificationsDefaultsOn() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.notificationsKey)
        XCTAssertTrue(SettingsStore.notificationsOn())
    }

    func testNotificationsReadsStored() {
        UserDefaults.standard.set(false, forKey: SettingsStore.notificationsKey)
        XCTAssertFalse(SettingsStore.notificationsOn())
    }

    func testNotifyOnStartDefaultsOn() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.notifyOnStartKey)
        XCTAssertTrue(SettingsStore.notifyOnStartOn())
    }

    func testNotifyOnStartReadsStored() {
        UserDefaults.standard.set(false, forKey: SettingsStore.notifyOnStartKey)
        XCTAssertFalse(SettingsStore.notifyOnStartOn())
    }

    func testPreferredMicUIDNilWhenUnset() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.micDeviceKey)
        XCTAssertNil(SettingsStore.preferredMicUID())
    }

    func testPreferredMicUIDNilWhenEmpty() {
        UserDefaults.standard.set("", forKey: SettingsStore.micDeviceKey)
        XCTAssertNil(SettingsStore.preferredMicUID())
    }

    func testPreferredMicUIDReadsValue() {
        UserDefaults.standard.set("BuiltInMicrophoneDevice", forKey: SettingsStore.micDeviceKey)
        XCTAssertEqual(SettingsStore.preferredMicUID(), "BuiltInMicrophoneDevice")
    }

    func testExportFolderDefaultsToDocuments() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.exportFolderKey)
        XCTAssertEqual(SettingsStore.exportFolder(), SettingsStore.defaultExportFolder())
    }

    func testExportFolderReadsStored() {
        UserDefaults.standard.set("/tmp/ember-export", forKey: SettingsStore.exportFolderKey)
        XCTAssertEqual(SettingsStore.exportFolder(), "/tmp/ember-export")
    }

    func testCurrentSummaryModelIdValid() {
        UserDefaults.standard.set(SummaryCatalog.defaultId, forKey: SettingsStore.summaryKey)
        XCTAssertEqual(SettingsStore.currentSummaryModelId(), SummaryCatalog.defaultId)
    }

    func testCurrentSummaryModelIdGarbageFallsBackToDefault() {
        UserDefaults.standard.set("nonsense-model-id", forKey: SettingsStore.summaryKey)
        XCTAssertEqual(SettingsStore.currentSummaryModelId(), SummaryCatalog.defaultId)
    }

    func testCurrentSummaryModelIdUnsetIsDefault() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.summaryKey)
        XCTAssertEqual(SettingsStore.currentSummaryModelId(), SummaryCatalog.defaultId)
    }

    func testCurrentWhisperModelIdGarbageFallsBackToDefault() {
        UserDefaults.standard.set("nonsense", forKey: SettingsStore.whisperKey)
        XCTAssertEqual(SettingsStore.currentWhisperModelId(), TranscriptionCatalog.defaultId)
    }
}
