import CoreAudio
import Foundation

/// A CoreAudio input/output device.
public struct AudioDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let hasInput: Bool
    public let hasOutput: Bool
    public init(id: AudioDeviceID, uid: String, name: String, hasInput: Bool, hasOutput: Bool) {
        self.id = id; self.uid = uid; self.name = name; self.hasInput = hasInput; self.hasOutput = hasOutput
    }
}

/// Enumerates system audio devices via CoreAudio (no extra dependencies).
public enum AudioDevices {
    public static func all() -> [AudioDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(info(for:))
    }

    public static func inputs() -> [AudioDeviceInfo] {
        all().filter(\.hasInput)
    }

    public static func outputs() -> [AudioDeviceInfo] {
        all().filter(\.hasOutput)
    }

    public static func deviceID(forUID uid: String) -> AudioDeviceID? {
        all().first { $0.uid == uid }?.id
    }

    /// Transport type (e.g. built-in, USB, Bluetooth, **aggregate**, virtual).
    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t) == noErr else { return 0 }
        return t
    }

    /// A real hardware input — excludes the private process-tap AGGREGATE we create for
    /// system audio (whose transport type is `aggregate`). Pinning the mic to that
    /// aggregate would capture silence, so the mic must always pick a real input.
    public static func isRealHardwareInput(_ id: AudioDeviceID) -> Bool {
        transportType(id) != kAudioDeviceTransportTypeAggregate
    }

    /// Resolves the microphone device to PIN: the preferred UID if it's a real input,
    /// else the system default input if real, else the first real hardware input.
    public static func hardwareInputID(preferUID: String?) -> AudioDeviceID? {
        let real = inputs().filter { isRealHardwareInput($0.id) }
        if let uid = preferUID, !uid.isEmpty, let d = real.first(where: { $0.uid == uid }) { return d.id }
        if let def = defaultInputID(), real.contains(where: { $0.id == def }) { return def }
        return real.first?.id
    }

    /// The current default device id for a selector (input/output), or nil.
    private static func defaultDeviceID(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
              dev != kAudioObjectUnknown else { return nil }
        return dev
    }

    /// The current default INPUT device id (to pin the mic at recording start).
    public static func defaultInputID() -> AudioDeviceID? {
        defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// UID of the current default INPUT device.
    public static func defaultInputUID() -> String? {
        defaultInputID().flatMap { stringProp($0, kAudioDevicePropertyDeviceUID) }
    }

    /// The current default OUTPUT device id.
    public static func defaultOutputID() -> AudioDeviceID? {
        defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// UID of the current default OUTPUT device — used as the process-tap aggregate's
    /// main sub-device (clock); without it the tap is silent on Bluetooth output (AirPods).
    public static func defaultOutputUID() -> String? {
        defaultOutputID().flatMap { stringProp($0, kAudioDevicePropertyDeviceUID) }
    }

    private static func info(for id: AudioDeviceID) -> AudioDeviceInfo? {
        guard let name = stringProp(id, kAudioObjectPropertyName),
              let uid = stringProp(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let inCh = channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let outCh = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        guard inCh > 0 || outCh > 0 else { return nil }
        return AudioDeviceInfo(id: id, uid: uid, name: name, hasInput: inCh > 0, hasOutput: outCh > 0)
    }

    private static func stringProp(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var out: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &out)
        guard status == noErr, let cf = out else { return nil }
        return cf.takeRetainedValue() as String
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr) == noErr else { return 0 }
        let abl = UnsafeMutableAudioBufferListPointer(ptr.assumingMemoryBound(to: AudioBufferList.self))
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
