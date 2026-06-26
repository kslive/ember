@testable import Core
import Foundation
import XCTest

/// Pure updater logic: version compare, release selection, SHA parsing, GitHub
/// decode, throttle. (Ported from Sage's UpdateLogicTests.)
final class UpdateLogicTests: XCTestCase {
    func testCompareVersions() {
        XCTAssertEqual(UpdateLogic.compareVersions("1.0.0", "1.5.0"), -1)
        XCTAssertEqual(UpdateLogic.compareVersions("1.5.0", "1.5.0"), 0)
        XCTAssertEqual(UpdateLogic.compareVersions("v2.0", "1.9.9"), 1)
        XCTAssertEqual(UpdateLogic.compareVersions("1.10.0", "1.9.0"), 1)
        XCTAssertEqual(UpdateLogic.compareVersions("1.5.0-beta.1", "1.5.0"), 0)
        XCTAssertTrue(UpdateLogic.isNewer("1.3.0", than: "1.2.1"))
        XCTAssertFalse(UpdateLogic.isNewer("1.0.0", than: "1.0.0"))
    }

    private func release(_ v: String, prerelease: Bool = false) -> UpdateRelease {
        UpdateRelease(version: v, notes: "", downloadURL: URL(string: "https://x/\(v).zip")!,
                      sha256: nil, sha256AssetURL: nil, sizeBytes: 1, publishedAt: nil, isPrerelease: prerelease)
    }

    func testPickUpdateStableChannel() {
        let releases = [release("1.0.0"), release("1.2.0"), release("1.3.0-rc", prerelease: true)]
        XCTAssertEqual(UpdateLogic.pickUpdate(from: releases, current: "1.0.0", channel: .stable)?.version, "1.2.0")
        XCTAssertNil(UpdateLogic.pickUpdate(from: releases, current: "1.2.0", channel: .stable))
    }

    func testPickUpdateBetaChannel() {
        let releases = [release("1.2.0"), release("1.3.0-rc", prerelease: true)]
        XCTAssertEqual(UpdateLogic.pickUpdate(from: releases, current: "1.2.0", channel: .beta)?.version, "1.3.0-rc")
    }

    func testSha256FromNotes() {
        let hash = String(repeating: "a", count: 64)
        XCTAssertEqual(UpdateLogic.sha256(fromNotes: "Release\nSHA256: \(hash)\nbye"), hash)
        XCTAssertNil(UpdateLogic.sha256(fromNotes: "no hash here"))
    }

    func testSha256RejectsLongerHexRun() {
        XCTAssertNil(UpdateLogic.sha256(fromNotes: String(repeating: "c", count: 65)))
    }

    func testSha256ReadsBareSidecarToken() {
        let hash = String(repeating: "d", count: 64)
        XCTAssertEqual(UpdateLogic.sha256(fromNotes: "\(hash)\n"), hash)
    }

    func testIsParseableVersion() {
        XCTAssertTrue(UpdateLogic.isParseableVersion("1.3.0"))
        XCTAssertTrue(UpdateLogic.isParseableVersion("v2"))
        XCTAssertFalse(UpdateLogic.isParseableVersion("latest"))
        XCTAssertFalse(UpdateLogic.isParseableVersion(""))
    }

    func testPickUpdateIgnoresGarbageTag() {
        let releases = [release("1.2.0"), release("latest")]
        XCTAssertEqual(UpdateLogic.pickUpdate(from: releases, current: "1.0.0", channel: .stable)?.version, "1.2.0")
    }

    func testDecodeSkipsReleasesWithoutChecksum() throws {
        let json = Data("""
        [{"tag_name":"v1.3.0","body":"just notes, no hash","prerelease":false,"published_at":null,
          "assets":[{"name":"Ember-1.3.0.zip","browser_download_url":"https://x/Ember-1.3.0.zip","size":1}]}]
        """.utf8)
        XCTAssertEqual(try UpdateLogic.decodeGitHubReleases(json).count, 0)
    }

    func testDecodeGitHubReleases() throws {
        let json = Data("""
        [{"tag_name":"v1.3.0","body":"notes SHA256: \(String(repeating: "b", count: 64))","prerelease":false,
          "published_at":"2026-06-25T10:30:00Z",
          "assets":[{"name":"Ember-1.3.0.zip","browser_download_url":"https://x/Ember-1.3.0.zip","size":50331648},
                    {"name":"Ember-1.3.0.zip.sha256","browser_download_url":"https://x/Ember-1.3.0.zip.sha256","size":65}]}]
        """.utf8)
        let releases = try UpdateLogic.decodeGitHubReleases(json)
        XCTAssertEqual(releases.count, 1)
        let r = releases[0]
        XCTAssertEqual(r.version, "1.3.0")
        XCTAssertEqual(r.sizeBytes, 50_331_648)
        XCTAssertEqual(r.sha256, String(repeating: "b", count: 64))
        XCTAssertNotNil(r.sha256AssetURL)
        XCTAssertFalse(r.isPrerelease)
        XCTAssertNotNil(r.publishedAt)
    }

    func testDecodeSkipsReleasesWithoutZip() throws {
        let json = Data("""
        [{"tag_name":"v1.3.0","body":"","prerelease":false,"published_at":null,
          "assets":[{"name":"Ember_1.3.0_aarch64.dmg","browser_download_url":"https://x/E.dmg","size":1}]}]
        """.utf8)
        XCTAssertEqual(try UpdateLogic.decodeGitHubReleases(json).count, 0)
    }

    func testShouldCheckThrottle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdateLogic.shouldCheck(last: nil, interval: 3600, now: now))
        XCTAssertFalse(UpdateLogic.shouldCheck(last: now.addingTimeInterval(-1800), interval: 3600, now: now))
        XCTAssertTrue(UpdateLogic.shouldCheck(last: now.addingTimeInterval(-7200), interval: 3600, now: now))
    }

    func testShouldCheckClockSkewAndZeroInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(UpdateLogic.shouldCheck(last: now.addingTimeInterval(3600), interval: 3600, now: now))
        XCTAssertTrue(UpdateLogic.shouldCheck(last: now, interval: 0, now: now))
    }

    func testCompareVersionsEdgeCases() {
        XCTAssertEqual(UpdateLogic.compareVersions("1.0", "1.0.0"), 0)
        XCTAssertEqual(UpdateLogic.compareVersions("2", "1.9.9"), 1)
        XCTAssertEqual(UpdateLogic.compareVersions("V1.5", "1.5"), 0)
        XCTAssertEqual(UpdateLogic.compareVersions("", ""), 0)
        XCTAssertEqual(UpdateLogic.compareVersions("1.a.0", "1.0.0"), 0)
    }

    func testDecodeThrowsOnInvalidJSON() {
        XCTAssertThrowsError(try UpdateLogic.decodeGitHubReleases(Data("not json at all".utf8)))
    }

    func testDecodeAcceptsSidecarOnlyChecksum() throws {
        let json = Data("""
        [{"tag_name":"v1.3.0","body":"no hash in the body","prerelease":false,"published_at":null,
          "assets":[{"name":"Ember.zip","browser_download_url":"https://x/Ember.zip","size":10},
                    {"name":"Ember.zip.sha256","browser_download_url":"https://x/Ember.zip.sha256","size":65}]}]
        """.utf8)
        let releases = try UpdateLogic.decodeGitHubReleases(json)
        XCTAssertEqual(releases.count, 1)
        XCTAssertNil(releases[0].sha256)
        XCTAssertNotNil(releases[0].sha256AssetURL)
    }
}
