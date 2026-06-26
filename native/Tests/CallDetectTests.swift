import CallDetectService
import XCTest

/// Unit tests for the call-detection debounce state machine (`CallDetectService.step`).
/// Covers the headphones scenario: a brief input drop mid-call must NOT end the session.
final class CallDetectTests: XCTestCase {
    /// Drive a sequence of active/inactive ticks through the pure state machine.
    private func run(_ ticks: [Bool], start: Int = 5, stop: Int = 8)
        -> (state: CallDetectState, events: [CallDetectEvent]) {
        var s = CallDetectState()
        var events: [CallDetectEvent] = []
        for a in ticks {
            let (ns, ev) = CallDetectService.step(s, active: a, startDebounce: start, stopDebounce: stop)
            s = ns
            events.append(ev)
        }
        return (s, events)
    }

    func testStartFiresExactlyOnceAfterDebounce() {
        let r = run(Array(repeating: true, count: 5))
        XCTAssertEqual(r.events.filter { $0 == .start }.count, 1)
        XCTAssertEqual(r.events.last, .start)
        XCTAssertTrue(r.state.autoSession)
    }

    func testStartDoesNotFireEarly() {
        let r = run(Array(repeating: true, count: 4))
        XCTAssertFalse(r.events.contains(.start))
        XCTAssertFalse(r.state.autoSession)
    }

    func testStopNeedsSustainedInactivity() {
        let r = run(Array(repeating: true, count: 5) + Array(repeating: false, count: 7))
        XCTAssertTrue(r.state.autoSession)
        XCTAssertFalse(r.events.contains(.end))
    }

    func testStopFiresAfterDebounce() {
        let r = run(Array(repeating: true, count: 5) + Array(repeating: false, count: 8))
        XCTAssertFalse(r.state.autoSession)
        XCTAssertEqual(r.events.filter { $0 == .end }.count, 1)
        XCTAssertEqual(r.events.last, .end)
    }

    /// The headphones scenario: plugging AirPods briefly drops the other app's
    /// input for a tick or two; an active tick must reset the inactivity run so
    /// the session is NOT ended.
    func testBriefInputDropDoesNotEndSession() {
        let seq = Array(repeating: true, count: 5)
            + Array(repeating: false, count: 3) + [true]
            + Array(repeating: false, count: 7)
        let r = run(seq)
        XCTAssertTrue(r.state.autoSession)
        XCTAssertFalse(r.events.contains(.end))
    }
}
