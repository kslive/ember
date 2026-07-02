import AVFoundation
import Core
import CoreAudio
import Foundation

/// Captures system audio output (what other call participants say) using the
/// macOS 14.4+ CoreAudio process-tap API: a global tap + a private aggregate
/// device + an IOProc. Buffers are converted to a fixed canonical format and
/// written to one file, so the tap can be rebuilt mid-session (e.g. after the
/// output device changes to headphones) without breaking the file.
final class SystemAudioTap {
    private enum Key {
        static let name = "name"
        static let uid = "uid"
        static let isPrivate = "private"
        static let isStacked = "stacked"
        static let tapAutoStart = "tapautostart"
        static let main = "master"
        static let subDeviceList = "subdevices"
        static let subDeviceUID = "uid"
        static let tapList = "taps"
        static let subTapUID = "uid"
        static let drift = "drift"
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private nonisolated(unsafe) var tapFormat: AVAudioFormat?
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var file: AVAudioFile?
    private nonisolated(unsafe) var liveConverter: AVAudioConverter?

    /// Fixed on-disk format → survives tap rebuilds (mixer resamples later anyway).
    private let canonical = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    /// 16 kHz mono for transcription (fed into the engine's system accumulator).
    private let live16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    var onLevel: ((CGFloat) -> Void)?
    /// Emits 16 kHz mono system-audio samples + the buffer's capture host time (mach
    /// units) on the realtime thread, so the engine positions them on the shared
    /// CoreAudio clock (arrival wall-clock drifts under the tap's bursty delivery).
    nonisolated(unsafe) var onLiveSamples: (([Float], UInt64) -> Void)?
    private(set) var url: URL?
    private var isBuilding = false
    var isRunning: Bool {
        procID != nil
    }

    private let rebuildQueue = DispatchQueue(label: "com.kslff.ember.systemtap")
    private let stateLock = NSLock()
    private var outputAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var rebuildWork: DispatchWorkItem?

    func start(url: URL) throws {
        file = try AVAudioFile(forWriting: url, settings: canonical.settings)
        self.url = url
        stateLock.lock()
        defer { stateLock.unlock() }
        try buildCoreAudio()
        installOutputListener()
    }

    func stop() {
        if let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddr, rebuildQueue, block)
            listenerBlock = nil
        }
        rebuildQueue.sync { rebuildWork?.cancel(); rebuildWork = nil }
        stateLock.lock()
        teardownCoreAudio()
        file = nil
        stateLock.unlock()
    }

    /// Belt-and-suspenders: if this tap is dropped without an explicit stop(),
    /// still destroy the aggregate device / process tap / IOProc so no orphaned
    /// CoreAudio objects linger (which could feed call-detection false positives).
    deinit { stop() }

    private func installOutputListener() {
        guard listenerBlock == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRebuild() }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddr, rebuildQueue, block)
    }

    /// Debounce a burst of output-change notifications into ONE rebuild (on the queue).
    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performRebuild() }
        rebuildWork = work
        rebuildQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Tears down and recreates the tap/aggregate/IOProc (new default-output clock)
    /// while keeping the same output file open. Runs on the serial queue under the lock.
    private func performRebuild() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard file != nil, !isBuilding else { return }
        isBuilding = true
        teardownCoreAudio()
        try? buildCoreAudio()
        isBuilding = false
    }

    private func buildCoreAudio() throws {
        do { try buildCoreAudioBody() } catch { teardownCoreAudio(); throw error }
    }

    private func buildCoreAudioBody() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        desc.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(desc, &tap), "create process tap")
        tapID = tap

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &size, &asbd), "tap format")
        guard let tf = AVAudioFormat(streamDescription: &asbd) else { throw TapError.message("unsupported tap format") }
        tapFormat = tf
        converter = AVAudioConverter(from: tf, to: canonical)
        liveConverter = AVAudioConverter(from: tf, to: live16k)

        let aggUID = UUID().uuidString
        let tapUID = desc.uuid.uuidString
        let aggDict: [String: Any] = [
            Key.name: "Ember System Tap",
            Key.uid: aggUID,
            Key.isPrivate: true,
            Key.isStacked: false,
            Key.tapAutoStart: true,
            Key.tapList: [[Key.subTapUID: tapUID, Key.drift: true]]
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &agg), "create aggregate")
        aggregateID = agg

        let block: AudioDeviceIOBlock = { [weak self] _, inInputData, inInputTime, _, _ in
            guard let self, let tf = tapFormat, let conv = converter,
                  let inBuf = AVAudioPCMBuffer(pcmFormat: tf, bufferListNoCopy: inInputData) else { return }
            let stamp = inInputTime.pointee
            let host = (stamp.mFlags.contains(.hostTimeValid) && stamp.mHostTime != 0) ? stamp.mHostTime : mach_absolute_time()
            let ratio = canonical.sampleRate / tf.sampleRate
            let cap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 32)
            guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: canonical, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return inBuf
            }
            guard err == nil else { return }
            try? file?.write(from: out)
            if let ch = out.floatChannelData?[0] {
                let n = Int(out.frameLength)
                if n > 0 { onLevel?(AudioLevel.meter(AudioLevel.rms(ch, n))) }
            }
            if let lc = liveConverter, let emit = onLiveSamples {
                let r2 = live16k.sampleRate / tf.sampleRate
                let cap2 = AVAudioFrameCount(Double(inBuf.frameLength) * r2 + 16)
                if cap2 > 0, let out16 = AVAudioPCMBuffer(pcmFormat: live16k, frameCapacity: cap2) {
                    var fed2 = false
                    var e2: NSError?
                    lc.convert(to: out16, error: &e2) { _, status in
                        if fed2 { status.pointee = .noDataNow; return nil }
                        fed2 = true; status.pointee = .haveData; return inBuf
                    }
                    if e2 == nil, let ch2 = out16.floatChannelData?[0] {
                        let nn = Int(out16.frameLength)
                        if nn > 0 { emit(Array(UnsafeBufferPointer(start: ch2, count: nn)), host) }
                    }
                }
            }
        }
        var pid: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&pid, aggregateID, nil, block), "create io proc")
        procID = pid
        try check(AudioDeviceStart(aggregateID, pid), "device start")
    }

    private func teardownCoreAudio() {
        if let pid = procID {
            AudioDeviceStop(aggregateID, pid)
            AudioDeviceDestroyIOProcID(aggregateID, pid)
            procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        converter = nil
        liveConverter = nil
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw TapError.os(what, status) }
    }

    enum TapError: Error { case os(String, OSStatus); case message(String) }
}
