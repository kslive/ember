import Foundation

/// A release available on GitHub (parsed from the Releases API).
public struct UpdateRelease: Sendable, Equatable {
    public let version: String
    public let notes: String
    public let downloadURL: URL
    public let sha256: String?
    public let sha256AssetURL: URL?
    public let sizeBytes: Int64
    public let publishedAt: Date?
    public let isPrerelease: Bool

    public init(version: String, notes: String, downloadURL: URL, sha256: String?,
                sha256AssetURL: URL?, sizeBytes: Int64, publishedAt: Date?, isPrerelease: Bool) {
        self.version = version
        self.notes = notes
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.sha256AssetURL = sha256AssetURL
        self.sizeBytes = sizeBytes
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
    }
}

/// Download progress.
public struct UpdateProgress: Sendable, Equatable {
    public let received: Int64
    public let total: Int64
    public init(received: Int64, total: Int64) {
        self.received = received; self.total = total
    }

    public var fraction: Double {
        total > 0 ? min(1, max(0, Double(received) / Double(total))) : 0
    }
}

/// Event from the download stream.
public enum UpdateDownloadEvent: Sendable {
    case progress(UpdateProgress)
    case finished(URL)
}

/// Updater UI phase (Settings → Updates).
public enum UpdaterPhase: Sendable, Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(UpdateRelease)
    case downloading(Double)
    case readyToInstall(UpdateRelease)
    case installing
    case failed(String)
}

/// Update channel.
public enum UpdateChannel: String, Sendable, CaseIterable { case stable, beta }

/// Typed updater errors (localized in the UI layer).
public enum UpdateError: Error, Sendable {
    case badResponse
    case checksumMismatch
    case missingChecksum
    case noAppInArchive
    case installFailed(String)
}
