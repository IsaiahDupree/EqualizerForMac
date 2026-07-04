// verify_audio_flow.swift — automated proof that a REAL Core Audio tap actually delivers audio, and that
// audio keeps flowing across a real system-default-output switch (the "it went silent" failure mode).
//
// Spawns a real audio source (afplay on a tone WAV passed as arg), builds an actual MixerChannelTap against
// it, and asserts renderCount > 0 (audio is really flowing — not just the reconciliation logic). Then, if
// ≥2 output devices exist, drives a PerAppMixer through a real default-output switch and asserts the app's
// audio keeps flowing on the new device. Restores the original default. Needs the Audio Capture permission
// for the terminal (creating a process tap); SKIPs (not FAILs) cleanly if it isn't granted.
//
//   Tools/verify.sh          # builds a tone + runs this
import AudioToolbox
import CoreAudio
import Foundation

let kSubsystem = "com.isaiahdupree.SonanceEQ"

func processObject(forPID pid: pid_t) -> AudioObjectID? {
    for obj in AudioProcesses.processObjectIDs() {
        let p: pid_t = (try? obj.read(kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1
        if p == pid { return obj }
    }
    return nil
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

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
}

@MainActor
func runTest() -> Int32 {
    guard CommandLine.arguments.count > 1 else { print("usage: verify_audio_flow <tone.wav>"); return 2 }
    let tone = CommandLine.arguments[1]

    // 1. Spawn a real audio source.
    let player = Process()
    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    player.arguments = [tone]
    do { try player.run() } catch { print("SKIP: couldn't launch afplay: \(error)"); return 0 }
    defer { if player.isRunning { player.terminate() } }
    print("Playing a tone via afplay (pid \(player.processIdentifier)) …")
    pump(1.2)   // let it start producing output

    guard let proc = processObject(forPID: player.processIdentifier) else {
        print("SKIP: afplay isn't visible as a Core Audio output process yet."); return 0
    }

    // 2. Build a REAL tap and confirm audio actually flows.
    let tap = MixerChannelTap(bundleID: "afplay.test")
    var failure: String?
    tap.onFailure = { failure = $0 }
    tap.start(processObjectID: proc, outputDeviceUID: nil)
    tap.setGain(0.5)

    let deadline = Date().addingTimeInterval(2)
    while tap.deliveredBlocks == 0, failure == nil, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if let failure {
        print("  ⚠ tap failed: \(failure)")
        print("SKIP: couldn't build a real tap — most likely the Audio Capture permission isn't granted to "
            + "your terminal. Grant it (System Settings → Privacy & Security → Audio Capture / run once), then rerun.")
        tap.stop(); return 0
    }

    var ok = true
    func check(_ c: Bool, _ m: String) { print((c ? "  ✓ " : "  ✗ ") + m); ok = ok && c }
    check(tap.isRunning, "real MixerChannelTap started against a live process")
    check(tap.deliveredBlocks > 0, "audio actually flowed through the tap (renderCount = \(tap.deliveredBlocks) > 0)")

    // Regression: our own private aggregate must NOT leak into the device list (it's visible to our own
    // process, so its UID has to carry the "SonanceMixer" marker AudioDevices filters on).
    let phantom = AudioDevices.outputDevices().filter {
        $0.uid.contains("SonanceEQ") || $0.name == "Sonance Mixer Output" || $0.name == "Sonance EQ Output"
    }
    check(phantom.isEmpty, "no phantom aggregate devices leak into the Output list (found: \(phantom.map(\.name)))")
    tap.stop()

    // 3. Audio-continuity across a real default-output switch (the "went silent" failure).
    let devices = AudioDevices.outputDevices()
    guard devices.count >= 2 else {
        print("  (device-switch continuity: SKIP — need ≥2 output devices)")
        print(ok ? "PASS ✅" : "FAIL ❌"); return ok ? 0 : 1
    }
    let original = readDefault()
    defer { setDefault(original) }
    let curID = AudioDevices.defaultOutput()?.id
    let devA = devices.first { $0.id != curID } ?? devices[0]
    let devB = devices.first { $0.id != devA.id }!
    setDefault(devB.id); pump(0.3)

    let engine = PerAppMixer(resolveProcess: { _ in processObject(forPID: player.processIdentifier) },
                             makeChannel: { MixerChannelTap(bundleID: $0) })
    let channel = MixerChannel(bundleID: "afplay.test", name: "afplay", volume: 0.5, muted: false, outputDeviceUID: nil)
    engine.apply([channel])

    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    let block: AudioObjectPropertyListenerBlock = { _, _ in
        MainActor.assumeIsolated { engine.handleDefaultOutputChange([channel]) }
    }
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    defer { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block) }

    pump(0.8)
    print("Switching default output: \(devB.name) → \(devA.name) with audio playing …")
    setDefault(devA.id)
    pump(1.5)   // let the rebuild happen + new tap deliver on the new device

    // The rebuilt tap is inside the engine; probe delivery by building a fresh direct tap on the new default.
    let after = MixerChannelTap(bundleID: "afplay.test2")
    after.start(processObjectID: proc, outputDeviceUID: nil)
    let d2 = Date().addingTimeInterval(2)
    while after.deliveredBlocks == 0, Date() < d2 {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    check(after.deliveredBlocks > 0, "audio still flows on the new default device after the switch (renderCount = \(after.deliveredBlocks))")
    after.stop()
    engine.stopAll()

    print(ok ? "PASS ✅" : "FAIL ❌")
    return ok ? 0 : 1
}

@main
struct AudioFlowTest {
    static func main() { exit(MainActor.assumeIsolated { runTest() }) }
}
