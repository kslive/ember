import AudioService
import XCTest

/// Covers the mic+system sample mixer (ducking + clipping + padding) used for the
/// live transcript.
final class AudioMixerTests: XCTestCase {
    func testEmptyInputs() {
        XCTAssertTrue(AudioMixer.mixSamples([], []).isEmpty)
    }

    func testMicOnlyPassthrough() {
        let out = AudioMixer.mixSamples([0.5, 0.5, 0.5], [])
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0], 0.5, accuracy: 0.0001)
    }

    func testPadsShorterStreamToMax() {
        let out = AudioMixer.mixSamples([Float](repeating: 0.1, count: 10),
                                        [Float](repeating: 0.1, count: 25))
        XCTAssertEqual(out.count, 25)
    }

    func testClippingClamps() {
        let out = AudioMixer.mixSamples([0.9], [0.9])
        XCTAssertEqual(out[0], 1.0, accuracy: 0.0001)
    }

    func testNoDuckWhenMicSilent() {
        let out = AudioMixer.mixSamples([0.0, 0.0], [0.5, 0.5])
        XCTAssertEqual(out[0], 0.5, accuracy: 0.0001)
    }

    func testDucksSystemWhenMicLoud() {
        let out = AudioMixer.mixSamples([0.2, 0.2], [0.5, 0.5])
        XCTAssertEqual(out[0], 0.2 + 0.5 * 0.6, accuracy: 0.0001)
    }

    /// Deferred-queue spill: samples written to a 16k CAF must decode back intact
    /// (same length, ~same values) — the aligned timeline survives the disk trip.
    func testWriteSamples16kRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ember-spill-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        var samples = [Float](repeating: 0, count: 16000)
        for i in 0 ..< samples.count {
            samples[i] = sinf(Float(i) * 0.01) * 0.5
        }
        XCTAssertNotNil(AudioMixer.writeSamples16k(samples, to: url))
        let back = try XCTUnwrap(AudioMixer.decode16kMono(url))
        XCTAssertEqual(back.count, samples.count)
        for i in stride(from: 0, to: min(back.count, samples.count), by: 997) {
            XCTAssertEqual(back[i], samples[i], accuracy: 0.001)
        }
    }

    func testWriteSamples16kEmptyReturnsNil() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ember-spill-empty.caf")
        XCTAssertNil(AudioMixer.writeSamples16k([], to: url))
    }
}
