import CryptoKit
import Foundation
import IOKit
import Security

/// Stores the app's secrets (API keys) as device-bound encrypted files instead of
/// the login keychain.
///
/// WHY NOT THE KEYCHAIN: Ember is ad-hoc signed, and the file-based keychain guards
/// every item with TWO independent checks. The decrypt ACL can be made permissive
/// ("any application", the `security -A` semantics), but the PARTITION LIST cannot:
/// securityd stamps it with the creating binary's cdhash (`cdhash:<hash>`), it has
/// no public API, and editing it requires the login-keychain password. Every update
/// of an ad-hoc app is a new cdhash, so macOS demands the keychain password after
/// EVERY update, forever — verified empirically on this machine with two distinct
/// ad-hoc binaries (the any-app ACL was applied and still blocked on the partition
/// check). Do not "fix" this back to SecItem storage.
///
/// The scheme here: AES-GCM with a key derived from the Mac's IOPlatformUUID, file
/// mode 0600 under Application Support. Threat-model honesty: any process running
/// as the user can replicate the derivation — same bar as a promptless keychain item
/// would have had. The ciphertext still defeats generic secret-pattern scrapers and
/// plaintext backups, and the key never leaves the machine (a restored/migrated copy
/// on another Mac fails to decrypt → the user just re-enters the key once).
public enum SecretStore {
    private static let service = "com.kslff.ember"
    private static let salt = "com.kslff.ember.secret-store.v1"
    private static let migrationLock = NSLock()
    private nonisolated(unsafe) static var migrationAttempted = Set<String>()

    /// In-memory cache of decrypted values. `get` used to hit IOKit (hardware
    /// UUID) + a file read + AES-GCM on EVERY call — and it's called from view
    /// bodies and the live-overlay tick, which made Settings visibly lag on
    /// every toggle. Invalidated by set/delete; secrets never change externally.
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cache: [String: String?] = [:]
    private nonisolated(unsafe) static var cachedDeviceKey: SymmetricKey?

    /// Persistent per-account tombstone: after an EXPLICIT delete the keychain
    /// migration must never resurrect the value on a later launch (a legacy
    /// keychain item that SecItemDelete failed to remove would otherwise come
    /// back from the dead). Cleared by the next `set`.
    private static func tombstoneKey(_ account: String) -> String {
        "ember.secret.deleted.\(account)"
    }

    public static func get(_ account: String) -> String? {
        cacheLock.lock()
        if let hit = cache[account] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()
        var value: String? = if let data = try? Data(contentsOf: fileURL(account)),
                                let box = try? AES.GCM.SealedBox(combined: data),
                                let plain = try? AES.GCM.open(box, using: deviceKey()) {
            String(data: plain, encoding: .utf8)
        } else {
            migrateFromKeychain(account)
        }
        cacheLock.lock()
        cache[account] = value
        cacheLock.unlock()
        return value
    }

    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: deviceKey()),
              let combined = sealed.combined else { return false }
        let url = fileURL(account)
        do {
            try combined.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            return false
        }
        UserDefaults.standard.removeObject(forKey: tombstoneKey(account))
        keychainDelete(account)
        cacheLock.lock()
        cache[account] = value
        cacheLock.unlock()
        return true
    }

    @discardableResult
    public static func delete(_ account: String) -> Bool {
        UserDefaults.standard.set(true, forKey: tombstoneKey(account))
        keychainDelete(account)
        cacheLock.lock()
        cache.updateValue(nil, forKey: account)
        cacheLock.unlock()
        let url = fileURL(account)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    private static func fileURL(_ account: String) -> URL {
        let dir = ModelPaths.appSupport().appendingPathComponent("Secrets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return dir.appendingPathComponent(account)
    }

    /// SHA-256(IOPlatformUUID + salt) → AES key. The hardware UUID is stable across
    /// app updates and OS reinstalls but unique per machine. Cached — the IOKit
    /// registry lookup is not free.
    private static func deviceKey() -> SymmetricKey {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedDeviceKey { return cachedDeviceKey }
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data((deviceUUID() + salt).utf8))))
        cachedDeviceKey = key
        return key
    }

    private static func deviceUUID() -> String {
        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        guard entry != 0 else { return "ember-no-ioreg" }
        defer { IOObjectRelease(entry) }
        let prop = IORegistryEntryCreateCFProperty(
            entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0
        )
        return prop?.takeRetainedValue() as? String ?? "ember-no-ioreg"
    }

    /// Keys saved by builds ≤1.5.0 live in the login keychain. Reading one from a
    /// new binary may show ONE last confirmation dialog (or none, when the reading
    /// build is the one that saved it) — after a successful read the value moves to
    /// the encrypted file and the keychain item is removed, so that dialog never
    /// returns. One attempt per launch: a denied dialog must not nag every summary.
    private static func migrateFromKeychain(_ account: String) -> String? {
        guard !UserDefaults.standard.bool(forKey: tombstoneKey(account)) else { return nil }
        migrationLock.lock()
        let seen = migrationAttempted.contains(account)
        if !seen { migrationAttempted.insert(account) }
        migrationLock.unlock()
        guard !seen else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        set(value, account: account)
        return value
    }

    private static func keychainDelete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
