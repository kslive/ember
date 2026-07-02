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
        let r = run([false] + Array(repeating: true, count: 5))
        XCTAssertEqual(r.events.filter { $0 == .start }.count, 1)
        XCTAssertEqual(r.events.last, .start)
        XCTAssertTrue(r.state.autoSession)
    }

    func testStartDoesNotFireEarly() {
        let r = run([false] + Array(repeating: true, count: 4))
        XCTAssertFalse(r.events.contains(.start))
        XCTAssertFalse(r.state.autoSession)
    }

    /// Rising-edge guard: input that is ALREADY active when monitoring begins
    /// (e.g. residual capture from a just-quit instance right after launch) must
    /// NEVER auto-start — only a genuine inactive→active transition does.
    func testNoStartWhenActiveFromLaunch() {
        let r = run(Array(repeating: true, count: 10))
        XCTAssertFalse(r.events.contains(.start))
        XCTAssertFalse(r.state.autoSession)
        XCTAssertFalse(r.state.armed)
    }

    func testStartsOnlyAfterRisingEdge() {
        let r = run([true, true, false] + Array(repeating: true, count: 5))
        XCTAssertEqual(r.events.filter { $0 == .start }.count, 1)
        XCTAssertTrue(r.state.autoSession)
        XCTAssertTrue(r.state.armed)
    }

    func testSingleInactiveBlipArmsThenStarts() {
        let r = run([false] + Array(repeating: true, count: 5))
        XCTAssertTrue(r.state.armed)
        XCTAssertEqual(r.events.filter { $0 == .start }.count, 1)
    }

    /// Detection counts LIVE processes (incl. non-GUI browser audio helpers) and skips
    /// only genuinely dead pids — the fix for browser-call auto-start.
    func testIsProcessAlive() {
        XCTAssertTrue(CallDetectService.isProcessAlive(getpid()))
        XCTAssertFalse(CallDetectService.isProcessAlive(999_999))
    }

    func testStopNeedsSustainedInactivity() {
        let r = run([false] + Array(repeating: true, count: 5) + Array(repeating: false, count: 7))
        XCTAssertTrue(r.state.autoSession)
        XCTAssertFalse(r.events.contains(.end))
    }

    func testStopFiresAfterDebounce() {
        let r = run([false] + Array(repeating: true, count: 5) + Array(repeating: false, count: 8))
        XCTAssertFalse(r.state.autoSession)
        XCTAssertEqual(r.events.filter { $0 == .end }.count, 1)
        XCTAssertEqual(r.events.last, .end)
    }

    /// The headphones scenario: plugging AirPods briefly drops the other app's
    /// input for a tick or two; an active tick must reset the inactivity run so
    /// the session is NOT ended.
    func testBriefInputDropDoesNotEndSession() {
        let seq = [false] + Array(repeating: true, count: 5)
            + Array(repeating: false, count: 3) + [true]
            + Array(repeating: false, count: 7)
        let r = run(seq)
        XCTAssertTrue(r.state.autoSession)
        XCTAssertFalse(r.events.contains(.end))
    }

    /// Back-to-back calls: after a session ends, a new sustained-active run must
    /// start a NEW session (the state machine fully re-arms).
    func testEndThenNewCallStartsAgain() {
        let seq = [false] + Array(repeating: true, count: 5)
            + Array(repeating: false, count: 8)
            + Array(repeating: true, count: 5)
        let r = run(seq)
        XCTAssertEqual(r.events.filter { $0 == .start }.count, 2)
        XCTAssertEqual(r.events.filter { $0 == .end }.count, 1)
        XCTAssertTrue(r.state.autoSession)
    }

    /// Flapping input (never `startDebounce` consecutive active ticks) must never
    /// start a session — the debounce requires a SUSTAINED run.
    func testFlappingNeverStarts() {
        let seq = (0 ..< 20).map { $0 % 2 == 0 }
        let r = run(seq)
        XCTAssertFalse(r.events.contains(.start))
        XCTAssertFalse(r.state.autoSession)
    }
}
