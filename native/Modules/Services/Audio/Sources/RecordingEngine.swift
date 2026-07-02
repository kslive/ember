import AVFoundation
import Combine
import Core
import CoreAudio
import Foundation
import OSLog

/// Recording engine: captures the microphone (a raw AUHAL input unit — `MicCapture`)
/// AND system audio (CoreAudio process tap) to separate files, publishing combined
/// live levels. On stop the two files are mixed into one for transcription.
///
/// The mic uses `MicCapture` (not `AVAudioEngine`) because AVAudioEngine couples
/// input+output and STOPS when the default OUTPUT changes (AirPods) — Apple-confirmed.
/// `MicCapture` is bound only to the INPUT device, so it survives AirPods mid-session.
@MainActor
public final class RecordingEngine: ObservableObject {
    @Published public private(set) var status: RecordingStatus = .idle
    @Published public private(set) var levels: [CGFloat] = Array(repeating: 0, count: 15)
    @Published public private(set) var elapsed: TimeInterval = 0

    private let micCapture = MicCapture()
    private let systemTap = SystemAudioTap()
    private var startDate: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var ticker: Timer?
    private var lastSystemLevel: CGFloat = 0
    private var pinnedInputID: AudioDeviceID?
    private var micRetryWork: DispatchWorkItem?
    private static let log = Logger(subsystem: "com.kslff.ember", category: "audio")

    private nonisolated(unsafe) let liveFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var liveAccumulator: [Float] = []
    private nonisolated(unsafe) var systemAccumulator: [Float] = []
    private nonisolated(unsafe) let liveLock = NSLock()
    private nonisolated(unsafe) var converterFormatKey: String = ""
    /// Shared zero-anchor on the CoreAudio host clock (mach units), set by the FIRST
    /// buffer of either channel (under `liveLock`). Both accumulators position samples by
    /// (bufferHostTime − anchorHost) → mic (continuous) and system (bursty, gaps during
    /// mac silence) share ONE timeline on the audio-capture clock, immune to delivery
    /// latency (arrival wall-clock drifted the system channel by tens of seconds). 0 = not
    /// yet anchored.
    private nonisolated(unsafe) var anchorHost: UInt64 = 0
    /// One-shot logging of each channel's first-real-sample offset (timeline debugging).
    private nonisolated(unsafe) var loggedMicStart = false
    private nonisolated(unsafe) var loggedSysStart = false

    private nonisolated(unsafe) let micFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    private nonisolated(unsafe) var fileConverter: AVAudioConverter?
    private nonisolated(unsafe) var micFile: AVAudioFile?
    private nonisolated(unsafe) let micFileLock = NSLock()

    public private(set) var micURL: URL?
    public private(set) var systemURL: URL?

    public init() {}

    public static func micAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined:
            await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        default: false
        }
    }

    public func start(meetingId: String) throws {
        guard status == .idle || status == .completed else { return }
        status = .starting
        do {
            try startThrowing(meetingId: meetingId)
        } catch {
            micRetryWork?.cancel(); micRetryWork = nil
            micCapture.stop()
            systemTap.stop()
            micFileLock.lock(); micFile = nil; micFileLock.unlock()
            ticker?.invalidate(); ticker = nil
            startDate = nil
            status = .idle
            throw error
        }
    }

    private func startThrowing(meetingId: String) throws {
        let dir = Self.recordingsDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let mic = dir.appendingPathComponent("\(meetingId)-mic.caf")
        micURL = mic
        micFile = try AVAudioFile(forWriting: mic, settings: micFormat.settings)
        liveLock.lock()
        liveAccumulator = []; systemAccumulator = []
        liveAccumulator.reserveCapacity(16000 * 60 * 30)
        systemAccumulator.reserveCapacity(16000 * 60 * 30)
        anchorHost = 0
        liveLock.unlock()
        converterFormatKey = ""
        loggedMicStart = false
        loggedSysStart = false

        pinnedInputID = AudioDevices.hardwareInputID(preferUID: SettingsStore.preferredMicUID())
        micCapture.onBuffer = { [weak self] buffer, host in
            guard let self else { return }
            ensureConverters(for: buffer.format)
            writeMic(buffer)
            accumulateLive(buffer, host: host)
            let micLevel = RecordingEngine.rms(buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                push(level: max(micLevel, lastSystemLevel))
            }
        }
        micCapture.onDeviceLost = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.status == .recording else { return }
                self.pinnedInputID = AudioDevices.hardwareInputID(preferUID: SettingsStore.preferredMicUID())
                self.micCapture.stop()
                self.startMic(retry: 8)
            }
        }
        let pinned = pinnedInputID ?? 0
        Self.log.info("mic pin → device id \(pinned, privacy: .public)")
        startMic(retry: 8)

        let sys = dir.appendingPathComponent("\(meetingId)-sys.caf")
        systemTap.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in self?.lastSystemLevel = level }
        }
        systemTap.onLiveSamples = { [weak self] samples, host in self?.appendSystemLive(samples, host: host) }
        do {
            try systemTap.start(url: sys)
            systemURL = sys
        } catch {
            systemURL = nil
        }

        startDate = Date()
        pausedAccumulated = 0
        elapsed = 0
        status = .recording
        startTicker()
    }

    /// Starts the AUHAL mic unit on the pinned device; gentle retry if it fails to
    /// start (e.g. device mid-transition) — NO engine restart, just retry the unit.
    private func startMic(retry: Int) {
        let pinned = pinnedInputID ?? 0
        do {
            try micCapture.start(deviceID: pinnedInputID)
            Self.log.info("mic started on device \(pinned, privacy: .public)")
        } catch {
            Self.log.error("mic start failed (retry \(retry, privacy: .public)): \(String(describing: error), privacy: .public)")
            guard retry > 0, status == .starting || status == .recording else { return }
            micRetryWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.startMic(retry: retry - 1) }
            }
            micRetryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    /// Builds the live/file converters for the current input format (realtime thread).
    private nonisolated func ensureConverters(for format: AVAudioFormat) {
        let key = "\(format.sampleRate)-\(format.channelCount)"
        if key == converterFormatKey, converter != nil { return }
        converterFormatKey = key
        converter = AVAudioConverter(from: format, to: liveFormat)
        micFileLock.lock()
        fileConverter = AVAudioConverter(from: format, to: micFormat)
        micFileLock.unlock()
    }

    public func pause() {
        guard status == .recording else { return }
        micCapture.stop()
        pausedAccumulated = elapsed
        startDate = nil
        ticker?.invalidate(); ticker = nil
        status = .paused
    }

    public func resume() {
        guard status == .paused else { return }
        status = .recording
        startMic(retry: 8)
        startDate = Date()
        startTicker()
    }

    /// Stops capture and returns the recorded mic/system file URLs.
    @discardableResult
    public func stop() -> (mic: URL?, system: URL?) {
        guard status == .recording || status == .paused else { return (micURL, systemURL) }
        micRetryWork?.cancel(); micRetryWork = nil
        micCapture.stop()
        systemTap.stop()
        micFileLock.lock(); micFile = nil; micFileLock.unlock()
        ticker?.invalidate(); ticker = nil
        startDate = nil
        lastSystemLevel = 0
        levels = Array(repeating: 0, count: 15)
        status = .completed
        return (micURL, systemURL)
    }

    public func reset() {
        status = .idle
        elapsed = 0
        micURL = nil
        systemURL = nil
        levels = Array(repeating: 0, count: 15)
        converter = nil
        converterFormatKey = ""
        micFileLock.lock(); fileConverter = nil; micFile = nil; micFileLock.unlock()
        liveLock.lock(); liveAccumulator = []; systemAccumulator = []; anchorHost = 0; liveLock.unlock()
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard let startDate else { return }
        elapsed = pausedAccumulated + Date().timeIntervalSince(startDate)
    }

    private func push(level: CGFloat) {
        var l = levels
        l.removeFirst()
        l.append(level)
        levels = l
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        return AudioLevel.meter(AudioLevel.rms(ch, Int(buffer.frameLength)))
    }

    /// Convert a mic buffer into the canonical mic format and write it to the file.
    private nonisolated func writeMic(_ buffer: AVAudioPCMBuffer) {
        micFileLock.lock()
        defer { micFileLock.unlock() }
        guard let conv = fileConverter, let file = micFile else { return }
        let ratio = micFormat.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        if err == nil { try? file.write(from: out) }
    }

    /// Resample a mic buffer to 16 kHz mono and append to the live accumulator, positioned
    /// by the buffer's capture host time on the shared clock.
    private nonisolated func accumulateLive(_ buffer: AVAudioPCMBuffer, host: UInt64) {
        guard let converter else { return }
        let ratio = liveFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: liveFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let ch = out.floatChannelData?[0] else { return }
        let n = Int(out.frameLength)
        guard n > 0 else { return }
        liveLock.lock()
        let offset = offsetSamples(forHost: host)
        padSilence(&liveAccumulator, toOffset: offset)
        liveAccumulator.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
        liveLock.unlock()
        if !loggedMicStart {
            loggedMicStart = true
            Self.log.info("mic first samples @ \(Double(offset) / 16000, format: .fixed(precision: 2), privacy: .public)s")
        }
    }

    /// Sample offset of a buffer on the SHARED CoreAudio host clock. The first buffer of
    /// either channel sets the zero anchor; later buffers map their capture host time to a
    /// sample index so mic + system stay matched regardless of delivery latency. MUST be
    /// called under `liveLock`.
    private nonisolated func offsetSamples(forHost host: UInt64) -> Int {
        if anchorHost == 0 { anchorHost = host; return 0 }
        let sec = AVAudioTime.seconds(forHostTime: host) - AVAudioTime.seconds(forHostTime: anchorHost)
        return Int(max(0, sec * 16000))
    }

    /// Zero-fills an accumulator up to `offset` so its index maps to real recording
    /// time (closing gaps where a channel — usually system audio during mac silence —
    /// produced nothing). Call under `liveLock`.
    private nonisolated func padSilence(_ acc: inout [Float], toOffset offset: Int) {
        let gap = offset - acc.count
        if gap > 0, gap < 16000 * 3600 { acc.append(contentsOf: repeatElement(0, count: gap)) }
    }

    /// Snapshot of accumulated 16 kHz mono MIC samples (full recording).
    public func liveSamples() -> [Float] {
        liveLock.lock(); defer { liveLock.unlock() }
        return liveAccumulator
    }

    /// Snapshot of accumulated 16 kHz mono SYSTEM-audio samples (full recording).
    /// Transcribed separately from the mic so the mic is never lost in a mono mix.
    public func systemSamples() -> [Float] {
        liveLock.lock(); defer { liveLock.unlock() }
        return systemAccumulator
    }

    /// Appends 16 kHz system-audio samples (realtime thread, from SystemAudioTap).
    private nonisolated func appendSystemLive(_ s: [Float], host: UInt64) {
        liveLock.lock()
        let offset = offsetSamples(forHost: host)
        padSilence(&systemAccumulator, toOffset: offset)
        systemAccumulator.append(contentsOf: s)
        liveLock.unlock()
        if !loggedSysStart {
            loggedSysStart = true
            Self.log.info("system first samples @ \(Double(offset) / 16000, format: .fixed(precision: 2), privacy: .public)s")
        }
    }

    public func liveMicCount() -> Int {
        liveLock.lock(); defer { liveLock.unlock() }
        return liveAccumulator.count
    }

    public func liveMicSlice(from index: Int) -> [Float] {
        liveLock.lock(); defer { liveLock.unlock() }
        guard index >= 0, index < liveAccumulator.count else { return [] }
        return Array(liveAccumulator[index...])
    }

    public func liveSystemCount() -> Int {
        liveLock.lock(); defer { liveLock.unlock() }
        return systemAccumulator.count
    }

    public func liveSystemSlice(from index: Int) -> [Float] {
        liveLock.lock(); defer { liveLock.unlock() }
        guard index >= 0, index < systemAccumulator.count else { return [] }
        return Array(systemAccumulator[index...])
    }

    /// Transient scratch for audio — Caches, NOT the user-facing data folder. Audio
    /// only lives here during a session/processing and is deleted afterwards.
    public static func recordingsDir() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Ember/rec", isDirectory: true)
    }

    /// Deletes ALL transient audio (current cache dir + legacy Application Support
    /// dir) so audio never accumulates — even after a crash/force-quit. Call on
    /// launch and on terminate.
    public static func purgeRecordings() {
        let fm = FileManager.default
        var dirs = [recordingsDir()]
        if let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirs.append(appSup.appendingPathComponent("Ember/recordings", isDirectory: true))
        }
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in items {
                try? fm.removeItem(at: u)
            }
        }
    }
}
