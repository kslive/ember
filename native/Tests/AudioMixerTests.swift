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
}
