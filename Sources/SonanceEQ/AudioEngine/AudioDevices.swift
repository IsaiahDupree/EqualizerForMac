import AudioToolbox
import CoreAudio
import Foundation

/// An audio output device the mixer can route an app to.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Enumerates real output devices (for per-app routing) — the device half of the mixer, mirroring
/// `AudioProcesses` (the app half).
enum AudioDevices {
    /// All output-capable hardware devices (excludes our own private aggregates), sorted by name.
    static func outputDevices() -> [AudioDevice] {
        let ids = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices) as [AudioDeviceID]) ?? []
        return ids.compactMap { id -> AudioDevice? in
            guard hasOutputStreams(id) else { return nil }
            let uid = (try? id.readDeviceUID()) ?? ""
            guard !uid.isEmpty, !uid.contains("SonanceEQ"), !uid.contains("Sonance EQ") else { return nil }
            let name = (try? id.readDeviceName()) ?? uid
            return AudioDevice(id: id, uid: uid, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The current system default output device, if resolvable.
    static func defaultOutput() -> AudioDevice? {
        guard let id = try? AudioObjectID.system.readDefaultOutputDevice(), id.isValid else { return nil }
        let uid = (try? id.readDeviceUID()) ?? ""
        let name = (try? id.readDeviceName()) ?? uid
        return uid.isEmpty ? nil : AudioDevice(id: id, uid: uid, name: name)
    }

    /// Resolve a saved device UID back to its current AudioDeviceID (ids aren't stable across reboots).
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        outputDevices().first { $0.uid == uid }?.id
    }

    /// Whether a device exposes any output streams.
    static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        return status == noErr && size > 0
    }
}
