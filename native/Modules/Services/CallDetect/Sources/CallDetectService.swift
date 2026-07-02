import AppKit
import Combine
import CoreAudio
import Foundation

/// Debounce counters for call detection (value type → unit-testable).
public struct CallDetectState: Equatable, Sendable {
    public var activeSeconds = 0
    public var inactiveSeconds = 0
    public var autoSession = false
    /// Becomes true after the first observed INACTIVE tick. Until then we never
    /// auto-start — so input that is "already active" when monitoring begins (e.g.
    /// residual capture from a just-quit Ember instance right after launch) can't
    /// trigger a false recording. Only a genuine inactive→active rising edge starts.
    public var armed = false
    public init() {}
}

/// What a debounce tick decided.
public enum CallDetectEvent: Equatable, Sendable { case none, start, end }

/// Detects when another app starts/stops using the microphone (a call) by
/// polling the CoreAudio process list — mirrors the Rust `mic_watcher`.
/// Our own capture runs in-process (self pid), so it is excluded → no self-trigger.
@MainActor
public final class CallDetectService: ObservableObject {
    @Published public private(set) var callActive = false

    public var onCallStart: (() -> Void)?
    public var onCallEnd: (() -> Void)?

    private var timer: Timer?
    private var state = CallDetectState()
    private let debounceSeconds = 5
    /// Grace before ending a session: a brief input drop (plugging headphones
    /// mid-call re-opens the other app's input; participant mute) must NOT stop
    /// the recording. Only sustained silence ends it.
    private let stopDebounceSeconds = 8

    public init() {}

    public func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        // .common: a .default-mode timer pauses while a menu is open or a scroll is
        // tracking — the tick-based debounce counters would silently freeze with it.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let active = Self.externalInputActive()
        callActive = active
        let (next, event) = CallDetectService.step(state, active: active,
                                                   startDebounce: debounceSeconds,
                                                   stopDebounce: stopDebounceSeconds)
        state = next
        switch event {
        case .start: onCallStart?()
        case .end: onCallEnd?()
        case .none: break
        }
    }

    /// Pure debounce state machine (extracted for testing). A sustained `active`
    /// run of `startDebounce` ticks starts a session; ending needs `stopDebounce`
    /// ticks of sustained inactivity (any active tick resets the inactive run).
    public nonisolated static func step(_ s: CallDetectState, active: Bool,
                                        startDebounce: Int, stopDebounce: Int) -> (CallDetectState, CallDetectEvent) {
        var st = s
        var event: CallDetectEvent = .none
        if active {
            st.activeSeconds += 1
            st.inactiveSeconds = 0
            if st.armed, st.activeSeconds >= startDebounce, !st.autoSession {
                st.autoSession = true
                event = .start
            }
        } else {
            st.armed = true
            st.activeSeconds = 0
            st.inactiveSeconds += 1
            if st.autoSession, st.inactiveSeconds >= stopDebounce {
                st.autoSession = false
                event = .end
            }
        }
        return (st, event)
    }

    /// True if any *other* process is currently capturing audio input.
    static func externalInputActive() -> Bool {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let selfBundle = Bundle.main.bundleIdentifier
        let system = AudioObjectID(kAudioObjectSystemObject)

        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddr, 0, nil, &size) == noErr, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &listAddr, 0, nil, &size, &ids) == noErr else { return false }

        for proc in ids {
            var running: UInt32 = 0
            var rSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(proc, &runAddr, 0, nil, &rSize, &running) == noErr, running != 0 else { continue }

            var pid: pid_t = 0
            var pSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(proc, &pidAddr, 0, nil, &pSize, &pid) == noErr else { continue }

            if pid == selfPid { continue }
            // A bogus HAL entry with pid ≤ 0 must not count as a call: kill(0, 0)
            // signals our own process GROUP and returns 0, which would read as "alive".
            if pid <= 0 { continue }
            // Skip only genuinely DEAD/stale pids (a leftover CoreAudio object). A LIVE
            // process using input is a real call EVEN IF it has no NSRunningApplication —
            // browser audio helpers (Google Meet, Zoom-web) and other non-GUI audio
            // clients have no GUI app, and the old `guard let app = NSRunningApplication`
            // wrongly skipped them, breaking auto-start for browser calls.
            if !Self.isProcessAlive(pid) { continue }
            if let selfBundle, NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == selfBundle { continue }
            if isHelper(pid) { continue }
            return true
        }
        return false
    }

    /// A pid is alive if `kill(pid, 0)` succeeds (exists, same user) or fails with
    /// EPERM (exists, different user). ESRCH means the process is gone → stale audio
    /// object we should ignore. Cheaper and correct where NSRunningApplication (GUI
    /// apps only) is wrong.
    public nonisolated static func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Excludes background helper processes. The native app runs MLX + WhisperKit
    /// IN-PROCESS (no ffmpeg/llama/mlx helper processes), and `selfPid` already
    /// excludes us — so there's nothing left to filter. A brand substring like
    /// "ember" must NOT be here: it would suppress auto-start for any unrelated
    /// app whose name contains it. Empty by design (kept for future helpers).
    private static let helperFragments: [String] = []
    private static func isHelper(_ pid: pid_t) -> Bool {
        guard !helperFragments.isEmpty,
              let app = NSRunningApplication(processIdentifier: pid) else { return false }
        let name = (app.bundleIdentifier ?? app.localizedName ?? "").lowercased()
        return helperFragments.contains { name.contains($0) }
    }
}
