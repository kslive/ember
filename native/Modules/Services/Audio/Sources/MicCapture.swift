import AudioToolbox
import AVFoundation
import Core
import CoreAudio
import OSLog

/// Output-INDEPENDENT microphone capture via a raw AUHAL input AudioUnit
/// (`kAudioUnitSubType_HALOutput`, input enabled / output disabled, bound to a
/// specific input device) — exactly what cpal does under the hood. Unlike
/// `AVAudioEngine` (which couples input+output into one IO graph and STOPS when the
/// default OUTPUT changes — Apple-confirmed), this is bound only to the INPUT device,
/// so it keeps delivering audio when AirPods connect mid-recording. Apple TN2091.
///
/// PASSIVE / NON-HIJACKING (invariant — do NOT break): a HALOutput unit is SHARED,
/// so Zoom/Meet keep using the same mic and the other party still hears the user.
/// The old "mic hijacked / other party can't hear me" bug came from VoiceProcessingIO
/// (via webview getUserMedia), NOT this. To stay passive: use HALOutput (never
/// VoiceProcessingIO); NEVER set hog mode (`kAudioDevicePropertyHogMode`); NEVER change
/// the device's `kAudioDevicePropertyNominalSampleRate`; set the client format ONLY on
/// the unit's OUTPUT scope (bus 1), NEVER on the hardware INPUT scope; keep the output
/// bus disabled. Opening a HAL input does NOT force Bluetooth HFP (only the call app does).
final class MicCapture {
    private static let log = Logger(subsystem: "com.kslff.ember", category: "mic")
    private var unit: AudioUnit?
    /// Format of the buffers delivered to `onBuffer` (float32, non-interleaved).
    private(set) nonisolated(unsafe) var format: AVAudioFormat?
    /// Called on the realtime audio thread with each captured buffer + its capture
    /// host time (mach units) so callers can position samples on the shared CoreAudio
    /// clock instead of arrival wall-clock (which drifts under buffering latency).
    nonisolated(unsafe) var onBuffer: ((AVAudioPCMBuffer, UInt64) -> Void)?
    /// Called on the MAIN thread if the bound input device dies/unplugs mid-session
    /// (AUHAL does NOT auto-migrate a device-bound unit) → caller should rebuild.
    nonisolated(unsafe) var onDeviceLost: (() -> Void)?

    private var boundDeviceID: AudioDeviceID = 0
    private nonisolated(unsafe) var didLogFirstBuffer = false
    private var aliveBlock: AudioObjectPropertyListenerBlock?
    private var aliveAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var isRunning: Bool {
        unit != nil
    }

    /// Start capturing from `deviceID` (or the current default input if nil).
    func start(deviceID: AudioDeviceID?) throws {
        if unit != nil { stop() }
        didLogFirstBuffer = false
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw Err.noComponent }
        var au: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &au), "new")
        guard let au else { throw Err.noComponent }
        unit = au
        do {
            var one: UInt32 = 1
            var zero: UInt32 = 0
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                                           &one, UInt32(MemoryLayout<UInt32>.size)), "enableInput")
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                                           &zero, UInt32(MemoryLayout<UInt32>.size)), "disableOutput")

            var dev = deviceID ?? AudioDevices.defaultInputID() ?? AudioDeviceID(0)
            if dev != 0 {
                try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                               &dev, UInt32(MemoryLayout<AudioDeviceID>.size)), "setDevice")
            }
            Self.log.info("start on device id \(dev, privacy: .public)")

            var hw = AudioStreamBasicDescription()
            var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitGetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hw, &sz), "getHWFormat")
            let rate = hw.mSampleRate > 0 ? hw.mSampleRate : 48000
            let ch = max(1, hw.mChannelsPerFrame)
            guard let clientFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: ch, interleaved: false) else {
                throw Err.format
            }
            format = clientFormat
            var client = clientFormat.streamDescription.pointee
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                           &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "setClientFormat")

            var cb = AURenderCallbackStruct(inputProc: micRenderCallback,
                                            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                           &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "setInputCallback")

            try check(AudioUnitInitialize(au), "initialize")
            try check(AudioOutputUnitStart(au), "start")
            installAliveListener(for: dev)
        } catch {
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            unit = nil
            format = nil
            throw error
        }
    }

    func stop() {
        removeAliveListener()
        guard let au = unit else { return }
        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        AudioComponentInstanceDispose(au)
        unit = nil
    }

    private func installAliveListener(for dev: AudioDeviceID) {
        guard dev != 0, aliveBlock == nil else { return }
        boundDeviceID = dev
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            var alive: UInt32 = 1
            var sz = UInt32(MemoryLayout<UInt32>.size)
            var addr = aliveAddr
            let ok = AudioObjectGetPropertyData(dev, &addr, 0, nil, &sz, &alive)
            if ok != noErr || alive == 0 { onDeviceLost?() }
        }
        aliveBlock = block
        AudioObjectAddPropertyListenerBlock(dev, &aliveAddr, DispatchQueue.main, block)
    }

    private func removeAliveListener() {
        if let block = aliveBlock, boundDeviceID != 0 {
            AudioObjectRemovePropertyListenerBlock(boundDeviceID, &aliveAddr, DispatchQueue.main, block)
        }
        aliveBlock = nil
        boundDeviceID = 0
    }

    /// Pulls the rendered input into a fresh buffer and forwards it. Realtime thread.
    fileprivate func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            _ ts: UnsafePointer<AudioTimeStamp>, _ frames: UInt32) {
        guard let au = unit, let format, frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let status = AudioUnitRender(au, flags, ts, 1, frames, buf.mutableAudioBufferList)
        if status == noErr {
            if !didLogFirstBuffer { didLogFirstBuffer = true; Self.log.info("first mic buffer frames=\(frames, privacy: .public)") }
            let stamp = ts.pointee
            let host = (stamp.mFlags.contains(.hostTimeValid) && stamp.mHostTime != 0) ? stamp.mHostTime : mach_absolute_time()
            onBuffer?(buf, host)
        }
    }

    private func check(_ s: OSStatus, _ what: String) throws {
        if s != noErr { throw Err.os(what, s) }
    }

    enum Err: Error { case noComponent, format, os(String, OSStatus) }
}

private func micRenderCallback(_ refCon: UnsafeMutableRawPointer,
                               _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                               _ ts: UnsafePointer<AudioTimeStamp>,
                               _: UInt32, _ frames: UInt32,
                               _: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let mic = Unmanaged<MicCapture>.fromOpaque(refCon).takeUnretainedValue()
    mic.render(flags, ts, frames)
    return noErr
}
