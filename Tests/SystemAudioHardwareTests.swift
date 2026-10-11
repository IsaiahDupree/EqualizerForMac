import AppKit
import AudioToolbox
import CoreAudio
import CryptoKit
import Foundation
import Testing
@testable import SonanceEQ

private final class SystemAudioHardwareBundleMarker {}

/// Opt-in integration over the shipping global tap and actual attached output devices.
/// No provider, audio device or callback is replaced. Counts prove routing callbacks,
/// not audible output; the receipt keeps that acceptance gap explicit.
@MainActor
@Suite(.serialized,
       .enabled(if: ProcessInfo.processInfo.environment["SONANCE_AUDIO_HARDWARE_TESTS"] == "1"),
       .timeLimit(.minutes(1)))
struct SystemAudioHardwareTests {
    private struct ProbeFailure: Error { let reason: String }

    private func pause() async throws {
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    /// Stop now returns cancelled intent immediately; inspect OS ownership only
    /// after its serial operation slot has actually drained. The supervisor still
    /// bounds an OS call that cannot be interrupted.
    private func waitForCleanup(_ tap: SystemAudioTap) async -> Bool {
        let until = ContinuousClock.now.advanced(by: .seconds(5))
        while tap.isFinishingOperation && ContinuousClock.now < until {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return !tap.isFinishingOperation
    }

    private func defaultUID() throws -> String {
        try AudioObjectID.system.readDefaultOutputDevice().readDeviceUID()
    }

    private func setDefault(_ device: AudioDevice) throws {
        var id = device.id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(AudioObjectID.system, &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard status == noErr else { throw CoreAudioError.create("Set probe output", status) }
        guard try defaultUID() == device.uid else { throw ProbeFailure(reason: "default_output_not_verified") }
    }

    private func aggregates() throws -> Set<String> {
        let ids: [AudioObjectID] = try AudioObjectID.system.readArray(kAudioHardwarePropertyDevices)
        return Set(ids.compactMap { try? $0.readDeviceUID() }.filter { $0.hasPrefix("SonanceEQ-Output-") })
    }

    private func binaryEvidence() throws -> [[String: String]] {
        let bundles = [Bundle.main, Bundle(for: SystemAudioHardwareBundleMarker.self)]
        guard let appURL = bundles[0].executableURL, let testURL = bundles[1].executableURL else {
            throw ProbeFailure(reason: "tested_binary_identity_unavailable")
        }
        var urls = [appURL, testURL]
        if let directory = Bundle.main.executableURL?.deletingLastPathComponent() {
            urls += try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".debug.dylib") }
        }
        return try urls.map { url in
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            return ["path": url.path, "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
        }
    }

    @Test func currentRouteRebuildAndRestartUseRealOutputs() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SonanceEQ/RouteProofs", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let lockPath = root.appendingPathComponent("audio-route.lock").path
        let lockFD = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw ProbeFailure(reason: "audio_resource_lock_unavailable") }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            throw ProbeFailure(reason: "another_audio_route_probe_is_running")
        }
        defer { flock(lockFD, LOCK_UN) }

        let receiptURL = root.appendingPathComponent(UUID().uuidString + ".json")
        var receipt: [String: Any] = [
            "contract": "sonance_system_audio_hardware_observation_v1",
            "started_at": ISO8601DateFormatter().string(from: Date()),
            "process_id": Int(getpid()),
            "supervisor_run_id": ProcessInfo.processInfo.environment["SONANCE_AUDIO_PROBE_RUN_ID"] ?? NSNull(),
            "source_revision": ProcessInfo.processInfo.environment["SONANCE_AUDIO_PROBE_SOURCE_REVISION"] ?? NSNull(),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown",
            "audibility_verified": false, "audio_samples_saved": false,
            "app_store_release_verified": false, "status": "running",
            "original_output_restored": NSNull(), "owned_aggregates_released": NSNull(),
            "scope": "development_host_global_tap_callbacks_cleanup_and_attached_output_switches"
        ]
        var observations: [[String: Any]] = []
        let tap = SystemAudioTap(eq: EQEngine())
        var original: AudioDevice?
        var lastOwnedUID: String?
        var baselineAggregates = Set<String>()
        var failure: String?
        var cleanupErrors: [String] = []
        func checkpoint(_ stage: String) throws {
            receipt["stage"] = stage
            receipt["updated_at"] = ISO8601DateFormatter().string(from: Date())
            receipt["observations"] = observations
            let bytes = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted])
            try bytes.write(to: receiptURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptURL.path)
        }
        tap.onLifecycleStage = { stage in try? checkpoint("core_audio:" + stage) }
        try checkpoint("locked")
        do {
            try checkpoint("binary_evidence")
            receipt["build_artifacts"] = try binaryEvidence()
            try checkpoint("checking_running_apps")
            // A second real Sonance instance must not be globally tapped/muted by this probe.
            let otherApps = AudioProcesses.siblingBundleIDs.flatMap {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0)
            }.filter { $0.processIdentifier != getpid() }
            guard otherApps.isEmpty else { throw ProbeFailure(reason: "another_sonance_audio_app_is_running") }
            // Debug's shipping preflight only observes an existing grant. Never request a new
            // permission in an unattended hardware run: a code-signature change can invalidate it.
            try checkpoint("observing_permission")
            let permission = AudioRecordingPermission()
            receipt["permission_preflight_available"] = permission.supportsPreflight
            receipt["audio_capture_permission"] = String(describing: permission.status)
            try checkpoint("permission_preflight")
            guard permission.supportsPreflight, permission.status == .authorized else {
                throw ProbeFailure(reason: "audio_capture_permission_required_for_this_signed_build")
            }
            guard let current = AudioDevices.defaultOutput() else { throw ProbeFailure(reason: "no_default_output") }
            original = current
            lastOwnedUID = current.uid
            baselineAggregates = try aggregates()
            let devices = AudioDevices.outputDevices()
            receipt["devices"] = devices.map { device -> [String: Any] in
                let transport: UInt32? = try? device.id.read(kAudioDevicePropertyTransportType, default: UInt32(0))
                let alive: UInt32? = try? device.id.read(kAudioDevicePropertyDeviceIsAlive, default: UInt32(0))
                return ["name": device.name, "uid": device.uid,
                        "transport": transport.map { $0.fourCC } ?? "unknown", "alive": alive == 1]
            }
            let eligible = devices.filter { device in
                let transport: UInt32? = try? device.id.read(kAudioDevicePropertyTransportType, default: UInt32(0))
                let alive: UInt32? = try? device.id.read(kAudioDevicePropertyDeviceIsAlive, default: UInt32(0))
                return alive == 1 && [kAudioDeviceTransportTypeBuiltIn, kAudioDeviceTransportTypeUSB,
                    kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE,
                    kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort].contains(transport ?? 0)
            }
            receipt["switchable_attached_device_count"] = eligible.count
            receipt["original_output_uid"] = current.uid
            try checkpoint("starting_tap")
            try tap.start()
            try checkpoint("waiting_for_initial_callbacks")
            try await pause()
            guard tap.isAudioFlowing else { throw ProbeFailure(reason: "initial_route_callbacks_unavailable") }
            observations.append(["stage": "start", "output": tap.outputDeviceName,
                "callback_flow_verified": tap.isAudioFlowing,
                "sample_rate": tap.tapFormat?.mSampleRate ?? 0])
            try checkpoint("initial_callbacks_verified")

            var rebuildCount = 0
            var rebuildFailure: String?
            tap.onRebuild = { result in
                rebuildCount += 1
                if case let .failure(error) = result { rebuildFailure = error.localizedDescription }
            }
            // At most three switches, bounded to the actual physically attached device inventory.
            for device in eligible.filter({ $0.uid != current.uid }).prefix(3) {
                guard try defaultUID() == lastOwnedUID else { throw ProbeFailure(reason: "output_changed_outside_probe") }
                let beforeCount = rebuildCount
                receipt["requested_output_uid"] = device.uid
                try checkpoint("switching_output")
                try setDefault(device)
                lastOwnedUID = device.uid
                try checkpoint("waiting_for_replacement_callbacks")
                try await pause()
                let flowing = tap.isAudioFlowing && rebuildCount > beforeCount && tap.outputDeviceName == device.name
                observations.append(["stage": "switch", "output": device.name, "uid": device.uid,
                    "callback_flow_verified": flowing, "running": tap.isRunning,
                    "rebuild_count": rebuildCount, "failure": rebuildFailure ?? NSNull()])
                guard flowing else { throw ProbeFailure(reason: rebuildFailure ?? "replacement_route_callbacks_unavailable") }
                try checkpoint("replacement_callbacks_verified")
            }
            try checkpoint("stopping_tap")
            tap.stop()
            guard await waitForCleanup(tap) else { throw ProbeFailure(reason: "stop_cleanup_still_pending") }
            guard !(tap.isRunning || tap.isAudioFlowing), try aggregates() == baselineAggregates else {
                throw ProbeFailure(reason: "stop_did_not_release_owned_route")
            }
            if try defaultUID() != current.uid {
                guard try defaultUID() == lastOwnedUID else { throw ProbeFailure(reason: "output_changed_outside_probe") }
                try setDefault(current)
                lastOwnedUID = current.uid
            }
            try checkpoint("restarting_tap")
            try tap.start()
            try await pause()
            guard tap.isAudioFlowing else { throw ProbeFailure(reason: "restart_route_callbacks_unavailable") }
            observations.append(["stage": "restart", "output": tap.outputDeviceName,
                                 "callback_flow_verified": tap.isAudioFlowing])
        } catch { failure = String(describing: error) }

        // Cleanup and its verification run before an assertion can end the test.
        // Evidence storage failure must never prevent audio/output cleanup.
        try? checkpoint("cleanup")
        tap.stop()
        let cleanupFinished = await waitForCleanup(tap)
        receipt["route_operation_finished"] = cleanupFinished
        if !cleanupFinished { cleanupErrors.append("route_operation_cleanup_still_pending") }
        if let original, cleanupFinished {
            do {
                let current = try defaultUID()
                if current != original.uid {
                    guard current == lastOwnedUID else { throw ProbeFailure(reason: "restore_skipped_for_external_output_change") }
                    try setDefault(original)
                }
                receipt["original_output_restored"] = try defaultUID() == original.uid
                receipt["owned_aggregates_released"] = try aggregates() == baselineAggregates
                if receipt["owned_aggregates_released"] as? Bool != true { cleanupErrors.append("aggregate_cleanup_not_verified") }
            } catch { cleanupErrors.append(String(describing: error)) }
        }
        receipt["observations"] = observations
        receipt["cleanup_errors"] = cleanupErrors
        receipt["failure"] = failure ?? NSNull()
        receipt["completed_at"] = ISO8601DateFormatter().string(from: Date())
        receipt["status"] = failure == nil && cleanupErrors.isEmpty ? "succeeded" : "failed"
        try checkpoint("completed")
        print("System audio hardware receipt: \(receiptURL.path)")
        #expect(failure == nil, "Real global tap probe failed: \(failure ?? "")")
        #expect(cleanupErrors.isEmpty, "Audio cleanup failed: \(cleanupErrors)")
    }
}
