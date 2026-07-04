// verify_device_switch.swift — automated integration test for the default-output-change handling.
//
// Programmatically flips the REAL system default output device (Core Audio) and asserts that our listener
// fires and the engine rebuilds *default-routed* channels while leaving *pinned* channels untouched. No
// headphones, no ears: it exercises the exact OS notification path the app relies on, then restores your
// original default output. Uses fake channels so it needs neither the audio-capture permission nor a
// playing app — it isolates the "did the OS tell us + did we react" integration gap.
//
// Run against the shipping engine sources:
//   swiftc -O Tools/verify_device_switch.swift \
//     Sources/SonanceEQ/AudioEngine/CoreAudioProperties.swift \
//     Sources/SonanceEQ/AudioEngine/AudioProcesses.swift \
//     Sources/SonanceEQ/AudioEngine/AudioDevices.swift \
//     Sources/SonanceEQ/AudioEngine/MixerChannelTap.swift \
//     Sources/SonanceEQ/AudioEngine/PerAppMixer.swift \
//     Sources/SonanceEQ/Models/Mixer.swift \
//     -o /tmp/vds && /tmp/vds
import AudioToolbox
import CoreAudio
import Foundation

// Normally defined in SonanceMixerApp.swift (excluded here — it carries @main).
let kSubsystem = "com.isaiahdupree.SonanceEQ"

/// A fake channel: lets us assert the rebuild path without Core Audio taps / permission / audio.
final class FakeChannel: MixerChannelControlling {
    let bundleID: String
    var isRunning = false
    var onFailure: ((String) -> Void)?
    var startCount = 0
    var stopCount = 0
    init(_ b: String) { bundleID = b }
    func start(processObjectID: AudioObjectID, outputDeviceUID: String?) { startCount += 1; isRunning = true }
    func setGain(_ v: Float) {}
    func stop() { stopCount += 1; isRunning = false }
}

final class Factory {
    var created: [FakeChannel] = []
    func make(_ b: String) -> MixerChannelControlling { let c = FakeChannel(b); created.append(c); return c }
    func all(_ b: String) -> [FakeChannel] { created.filter { $0.bundleID == b } }
}

func readDefault() -> AudioDeviceID { (try? AudioObjectID.system.readDefaultOutputDevice()) ?? 0 }

@discardableResult
func setDefault(_ id: AudioDeviceID) -> OSStatus {
    var d = id
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                      UInt32(MemoryLayout<AudioDeviceID>.size), &d)
}

@MainActor
func runTest() -> Int32 {
    let devices = AudioDevices.outputDevices()
    print("Output devices: \(devices.map(\.name))")
    guard devices.count >= 2 else {
        print("SKIP: need ≥2 output devices to test a switch (found \(devices.count)). "
            + "Connect headphones/AirPods/an external display and rerun.")
        return 0
    }

    let original = readDefault()
    defer { setDefault(original) }   // never leave the user on a different output

    // Start on one device, so switching to the other is a genuine change.
    let currentID = AudioDevices.defaultOutput()?.id
    let deviceA = devices.first { $0.id != currentID } ?? devices[0]
    let deviceB = devices.first { $0.id != deviceA.id }!
    setDefault(deviceB.id)
    usleep(300_000)

    // Engine with fakes: one channel that follows the default, one pinned to a specific device.
    let factory = Factory()
    let playing: Set<String> = ["default.app", "pinned.app"]
    let engine = PerAppMixer(resolveProcess: { playing.contains($0) ? AudioObjectID(1) : nil },
                             makeChannel: { factory.make($0) })
    let channels = [
        MixerChannel(bundleID: "default.app", name: "Default", volume: 0.5, muted: false, outputDeviceUID: nil),
        MixerChannel(bundleID: "pinned.app", name: "Pinned", volume: 0.5, muted: false, outputDeviceUID: deviceB.uid),
    ]
    engine.apply(channels)
    let defaultBuilds0 = factory.all("default.app").count
    let pinnedBuilds0 = factory.all("pinned.app").count

    // The real listener, wired to the engine exactly as MixerAppState does.
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var fired = false
    let block: AudioObjectPropertyListenerBlock = { _, _ in
        MainActor.assumeIsolated {
            fired = true
            engine.handleDefaultOutputChange(channels)
        }
    }
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    defer { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block) }

    print("Switching default output: \(deviceB.name) → \(deviceA.name) …")
    setDefault(deviceA.id)

    // Pump the main runloop until the notification arrives (or 2s).
    let deadline = Date().addingTimeInterval(2)
    while !fired, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    let defaultBuilds1 = factory.all("default.app").count
    let pinnedBuilds1 = factory.all("pinned.app").count

    var ok = true
    func check(_ cond: Bool, _ msg: String) { print((cond ? "  ✓ " : "  ✗ ") + msg); ok = ok && cond }
    check(fired, "OS fired our default-output listener on a real device switch")
    check(defaultBuilds1 == defaultBuilds0 + 1, "default-routed channel rebuilt (\(defaultBuilds0) → \(defaultBuilds1) builds)")
    check(factory.all("default.app").first?.stopCount == 1, "the old default-routed tap was torn down")
    check(pinnedBuilds1 == pinnedBuilds0, "pinned channel left untouched (\(pinnedBuilds0) → \(pinnedBuilds1) builds)")

    print(ok ? "PASS ✅" : "FAIL ❌")
    return ok ? 0 : 1
}

@main
struct DeviceSwitchTest {
    static func main() {
        exit(MainActor.assumeIsolated { runTest() })
    }
}
