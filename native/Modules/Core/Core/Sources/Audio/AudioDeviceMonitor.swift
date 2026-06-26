import Combine
import CoreAudio
import Foundation

/// Low-level CoreAudio watcher: fires `onChange` (on main) whenever the device
/// list or the default input/output device changes. Reusable by the recorder
/// (to rebind capture) and the UI (to refresh device pickers).
public final class AudioDeviceMonitor {
    public var onChange: (() -> Void)?
    private var entries: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init() {}

    public func start() {
        guard entries.isEmpty else { return }
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice
        ]
        for sel in selectors {
            var addr = AudioObjectPropertyAddress(mSelector: sel,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.onChange?() }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr,
                                                   DispatchQueue.main, block) == noErr {
                entries.append((addr, block))
            }
        }
    }

    public func stop() {
        for (addr, block) in entries {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, block)
        }
        entries.removeAll()
    }

    deinit { stop() }
}

/// Observable device list for SwiftUI — auto-refreshes on hardware changes (no
/// manual refresh button needed).
@MainActor
public final class AudioDevicesModel: ObservableObject {
    @Published public private(set) var inputs: [AudioDeviceInfo] = []
    @Published public private(set) var outputs: [AudioDeviceInfo] = []
    private let monitor = AudioDeviceMonitor()

    public init() {
        reload()
        monitor.onChange = { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        monitor.start()
    }

    public func reload() {
        inputs = AudioDevices.inputs()
        outputs = AudioDevices.outputs()
    }
}
