// Probe: does the Core Audio process-tap loop work under the App Sandbox (Mac App Store requirement)?
// Runs the same tap → private aggregate → IOProc → start sequence as SystemAudioTap.build(), printing
// the OSStatus of each load-bearing call. Run it unsandboxed and again ad-hoc-signed WITH the app-sandbox
// entitlement; if a step that succeeds unsandboxed fails sandboxed, MAS can't ship the self-contained tap.
//
// Build:  xcrun swiftc -O -target arm64-apple-macos14.4 Tools/sandbox_tap_probe.swift -o /tmp/tapprobe \
//             -framework CoreAudio -framework AudioToolbox
// Run:    PROBE_LABEL=unsandboxed /tmp/tapprobe
//         codesign --force --sign - --entitlements /tmp/probe.entitlements /tmp/tapprobe
//         PROBE_LABEL=sandboxed   /tmp/tapprobe
import AudioToolbox
import CoreAudio
import Foundation

@discardableResult
func report(_ name: String, _ status: OSStatus) -> Bool {
    let ok = status == noErr
    let bytes = [UInt8((status >> 24) & 0xff), UInt8((status >> 16) & 0xff),
                 UInt8((status >> 8) & 0xff), UInt8(status & 0xff)]
    let fourcc = bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? " '" + String(bytes: bytes, encoding: .ascii)! + "'" : ""
    print("  \(ok ? "✓" : "✗") \(name): \(status)\(fourcc)")
    return ok
}

let label = ProcessInfo.processInfo.environment["PROBE_LABEL"] ?? "?"
print("=== process-tap probe [\(label)] ===")

// 1. Create a global tap (unmuted so we don't disturb audio during the probe).
let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
desc.name = "Sonance Probe Tap"
desc.uuid = UUID()
desc.muteBehavior = .unmuted
desc.isPrivate = true

var tapID = AudioObjectID(kAudioObjectUnknown)
guard report("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(desc, &tapID)), tapID != 0 else {
    print("RESULT: tap creation blocked"); exit(1)
}

// 2. Read the tap's stream format.
var fmtAddr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                         mScope: kAudioObjectPropertyScopeGlobal,
                                         mElement: kAudioObjectPropertyElementMain)
var asbd = AudioStreamBasicDescription()
var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
report("read kAudioTapPropertyFormat", AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &asbdSize, &asbd))
print("    format: \(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) ch")

// 3. Resolve the default output device + UID.
var devAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                         mScope: kAudioObjectPropertyScopeGlobal,
                                         mElement: kAudioObjectPropertyElementMain)
var outDev = AudioObjectID(kAudioObjectUnknown)
var devSize = UInt32(MemoryLayout<AudioObjectID>.size)
report("read DefaultOutputDevice", AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devAddr, 0, nil, &devSize, &outDev))

var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                         mScope: kAudioObjectPropertyScopeGlobal,
                                         mElement: kAudioObjectPropertyElementMain)
var uidCF = "" as CFString
var uidSize = UInt32(MemoryLayout<CFString?>.size)
let uidStatus = withUnsafeMutablePointer(to: &uidCF) {
    AudioObjectGetPropertyData(outDev, &uidAddr, 0, nil, &uidSize, $0)
}
report("read output device UID", uidStatus)
let outUID = uidCF as String

// 4. Build a private aggregate device (real output as clock master + the tap).
let aggregate: [String: Any] = [
    kAudioAggregateDeviceNameKey: "Sonance Probe Aggregate",
    kAudioAggregateDeviceUIDKey: UUID().uuidString,
    kAudioAggregateDeviceMainSubDeviceKey: outUID,
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
    kAudioAggregateDeviceTapListKey: [[
        kAudioSubTapDriftCompensationKey: true,
        kAudioSubTapUIDKey: desc.uuid.uuidString,
    ]],
]
var aggID = AudioObjectID(kAudioObjectUnknown)
guard report("AudioHardwareCreateAggregateDevice", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggID)), aggID != 0 else {
    AudioHardwareDestroyProcessTap(tapID); print("RESULT: aggregate creation blocked"); exit(2)
}

// 5. Install an IOProc and start it; count render callbacks for 1.5 s.
let renderCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
renderCount.initialize(to: 0)
var procID: AudioDeviceIOProcID?
let createStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, DispatchQueue(label: "probe.io")) { _, _, _, _, _ in
    renderCount.pointee += 1
}
guard report("AudioDeviceCreateIOProcIDWithBlock", createStatus), let proc = procID else {
    AudioHardwareDestroyAggregateDevice(aggID); AudioHardwareDestroyProcessTap(tapID); exit(3)
}
let startOK = report("AudioDeviceStart", AudioDeviceStart(aggID, proc))
Thread.sleep(forTimeInterval: 1.5)
print("    render callbacks in 1.5s: \(renderCount.pointee)")

// 6. Teardown.
AudioDeviceStop(aggID, proc)
AudioDeviceDestroyIOProcID(aggID, proc)
AudioHardwareDestroyAggregateDevice(aggID)
AudioHardwareDestroyProcessTap(tapID)

print(startOK ? "RESULT: full tap loop ran [\(label)]" : "RESULT: start failed [\(label)]")
exit(startOK ? 0 : 4)
