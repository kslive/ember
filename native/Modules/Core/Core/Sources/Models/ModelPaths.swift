import Foundation

/// On-disk locations of the app data and the downloaded models. These paths are
/// what existing installs already hold multi-GB models in — never move them.
public enum ModelPaths {
    /// `~/Library/Application Support/Ember`, created on first access.
    public static func appSupport() -> URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Ember", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// WhisperKit's `downloadBase`: it appends `models/argmaxinc/whisperkit-coreml/<variant>`
    /// itself, which is exactly `whisperModelDir(_:)`.
    public static var whisperDownloadBase: URL {
        appSupport()
    }

    public static func whisperModelDir(_ variant: String) -> URL {
        appSupport()
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(variant, isDirectory: true)
    }

    public static func gigaAMModelDir(_ variant: String) -> URL {
        appSupport()
            .appendingPathComponent("models/gigaam", isDirectory: true)
            .appendingPathComponent(variant, isDirectory: true)
    }

    /// `~/Library/Caches/models/<repoId>` — the layout of the MLX hub client Ember
    /// used before `HubFetch` (Caches download base + `models/<repo>`), kept so
    /// LLMs downloaded by earlier versions are still found.
    public static func mlxModelDir(_ repoId: String) -> URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("models/" + repoId, isDirectory: true)
    }

    /// Recursive byte size of everything under `url` (download progress).
    public static func dirSize(_ url: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
