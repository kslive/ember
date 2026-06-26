import Core
import CryptoKit
import Foundation

/// Networking + staging + install engine for the custom updater (ported from Sage).
/// An actor → serializes filesystem operations. The live /Applications bundle is
/// NEVER modified; replacement happens from a detached helper after the app quits.
actor UpdateEngine {
    private static let appName = "Ember"
    private static let repo = "kslive/ember"

    func checkForUpdate(current: String, channel: UpdateChannel) async throws -> UpdateRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases?per_page=20") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Ember-Updater", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw UpdateError.badResponse
        }
        let releases = try UpdateLogic.decodeGitHubReleases(data)
        return UpdateLogic.pickUpdate(from: releases, current: current, channel: channel)
    }

    nonisolated func downloadAndVerify(_ release: UpdateRelease) -> AsyncThrowingStream<UpdateDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var expected: String?
                    if let shaURL = release.sha256AssetURL {
                        var req = URLRequest(url: shaURL)
                        req.setValue("Ember-Updater", forHTTPHeaderField: "User-Agent")
                        let (d, resp) = try await URLSession.shared.data(for: req)
                        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                            throw UpdateError.badResponse
                        }
                        expected = UpdateLogic.sha256(fromNotes: String(bytes: d, encoding: .utf8) ?? "")
                    }
                    if expected == nil { expected = release.sha256 }
                    guard let expected else { throw UpdateError.missingChecksum }

                    let localZip = try await Self.downloadFile(from: release.downloadURL) { rec, tot in
                        continuation.yield(.progress(UpdateProgress(received: rec, total: tot)))
                    }
                    let actual = try Self.sha256Hex(ofFile: localZip)
                    guard actual == expected.lowercased() else { throw UpdateError.checksumMismatch }
                    continuation.yield(.finished(localZip))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Unzip the verified zip into a stable staging dir, strip quarantine, return the
    /// `.app`. The /Applications bundle is NOT touched (replacement happens at quit).
    func stage(zipURL: URL) async throws -> URL {
        let fm = FileManager.default
        let staging = try Self.stagingDir()
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let unzip = Self.run(["/usr/bin/ditto", "-x", "-k", zipURL.path, staging.path])
        guard unzip.code == 0 else { throw UpdateError.installFailed("unzip: \(unzip.err)") }

        let items = (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noAppInArchive }
        _ = Self.run(["/usr/bin/xattr", "-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Arm a detached helper that waits for this process to exit, then replaces
    /// /Applications/Ember.app from staging, strips quarantine, optionally relaunches.
    static func applyOnQuit(stagedAppPath src: String, destPath dst: String, relaunch: Bool) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let stagingParent = (src as NSString).deletingLastPathComponent
        let openLine = relaunch ? "/usr/bin/open \"\(dst)\"" : ""
        let script = """
        DST="\(dst)"; NEW="$DST.new"; BAK="$DST.bak"
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        rm -rf "$NEW" "$BAK"
        if /usr/bin/ditto "\(src)" "$NEW"; then
            /usr/bin/xattr -dr com.apple.quarantine "$NEW" 2>/dev/null
            trap 'if [ ! -d "$DST" ] && [ -d "$BAK" ]; then mv "$BAK" "$DST"; fi' EXIT INT TERM HUP
            if [ -d "$DST" ]; then mv "$DST" "$BAK" || exit 1; fi
            if mv "$NEW" "$DST"; then
                trap - EXIT INT TERM HUP
                rm -rf "$BAK"
                \(openLine)
            else
                rm -rf "$DST"; [ -d "$BAK" ] && mv "$BAK" "$DST"
                trap - EXIT INT TERM HUP
            fi
        else
            rm -rf "$NEW"
        fi
        rm -rf "\(stagingParent)"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
    }

    static func stagingDir() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("\(appName)/PendingUpdate", isDirectory: true)
    }

    private static func run(_ argv: [String]) -> (code: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run(); p.waitUntilExit() } catch { return (-1, "", "\(error)") }
        let o = String(bytes: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(bytes: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, o, e)
    }

    private static func sha256Hex(ofFile url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func downloadFile(from url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        let canceller = Canceller()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                let delegate = DownloadDelegate(progress: progress, completion: cont)
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                delegate.session = session
                let task = session.downloadTask(with: url)
                canceller.set { task.cancel(); session.invalidateAndCancel() }
                task.resume()
            }
        } onCancel: {
            canceller.run()
        }
    }
}

/// Thread-safe one-shot holder so the task-cancellation handler can reach the
/// URLSession/task created inside the continuation body.
private final class Canceller: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?
    func set(_ a: @escaping () -> Void) {
        lock.lock(); action = a; lock.unlock()
    }

    func run() {
        lock.lock(); let a = action; action = nil; lock.unlock(); a?()
    }
}

/// Bridges `URLSessionDownloadTask` → progress + a single-resume continuation.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64) -> Void
    private let completion: CheckedContinuation<URL, Error>
    var session: URLSession?
    private var resumed = false

    init(progress: @escaping @Sendable (Int64, Int64) -> Void, completion: CheckedContinuation<URL, Error>) {
        self.progress = progress
        self.completion = completion
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ember-update-\(UUID().uuidString).zip")
        do { try FileManager.default.moveItem(at: location, to: dest); finish(.success(dest)) } catch { finish(.failure(error)) }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !resumed else { return }
        resumed = true
        session?.finishTasksAndInvalidate()
        switch result {
        case let .success(u): completion.resume(returning: u)
        case let .failure(e): completion.resume(throwing: e)
        }
    }
}
