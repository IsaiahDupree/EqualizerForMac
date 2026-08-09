import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// One controllable per-app audio channel. Abstracted so `PerAppMixer`'s reconciliation state machine can
/// be exercised without Core Audio hardware; `MixerChannelTap` is the real implementation.
protocol MixerChannelControlling: AnyObject {
    var isRunning: Bool { get }
    var onFailure: ((String) -> Void)? { get set }
    func start(processObjectID: AudioObjectID, outputDeviceUID: String?)
    func setGain(_ value: Float)
    func stop()
}

extension MixerChannelTap: MixerChannelControlling {}

/// Manages one channel per app that needs non-passthrough treatment (volume / mute / routing).
/// Apps at unity/unmuted/default-output are left alone (no tap). Resolves bundle ids to live process
/// objects and reconciles the running channels to the desired set. (Shared lineage with Sonance Mixer.)
///
/// The process resolver and channel factory are injectable so the reconciliation logic (drop-stale,
/// rebuild-on-route-change, live-gain, teardown) is unit-testable with fakes.
@MainActor
final class PerAppMixer {
    private var taps: [String: MixerChannelControlling] = [:]
    private var routing: [String: String?] = [:]   // bundleID → outputDeviceUID it was built with
    private let log = Logger(subsystem: kSubsystem, category: "PerAppMixer")

    /// Resolve a set of bundle ids to their live process object ids (one shared enumeration for the whole
    /// set — NOT one Core Audio scan per bundle id) — bundle ids absent from the result aren't producing
    /// audio right now.
    private let resolveProcesses: (Set<String>) -> [String: AudioObjectID]
    /// Build a fresh channel controller for a bundle id.
    private let makeChannel: (String) -> MixerChannelControlling

    init(resolveProcesses: @escaping (Set<String>) -> [String: AudioObjectID] =
             { AudioProcesses.processObjectIDMap(forBundleIDs: $0) },
         makeChannel: @escaping (String) -> MixerChannelControlling =
             { MixerChannelTap(bundleID: $0) }) {
        self.resolveProcesses = resolveProcesses
        self.makeChannel = makeChannel
    }

    /// Reported (bundleID, message) when a channel can't be routed (so the UI can flag it).
    var onChannelFailure: ((String, String) -> Void)?

    /// Reconcile running taps to `channels`. Idempotent — safe to call on every change.
    func apply(_ channels: [MixerChannel]) {
        let wanted = Dictionary(uniqueKeysWithValues: channels.map { ($0.bundleID, $0) })

        // Drop taps no longer wanted.
        for (bundleID, tap) in taps where wanted[bundleID] == nil {
            tap.stop()
            taps[bundleID] = nil
            routing[bundleID] = nil
        }

        // Resolve every wanted bundle id against ONE shared Core Audio process enumeration, instead of
        // re-scanning the whole system once per channel (the N+1 this fixes).
        let processes = resolveProcesses(Set(wanted.keys))

        for (bundleID, channel) in wanted {
            // The app must be producing audio right now to be tapped.
            guard let process = processes[bundleID] else {
                taps[bundleID]?.stop(); taps[bundleID] = nil; routing[bundleID] = nil
                continue
            }
            if let existing = taps[bundleID] {
                // Output-device changes need a rebuild; volume/mute are live.
                if routing[bundleID] ?? nil != channel.outputDeviceUID {
                    existing.stop()
                    startChannel(channel, process: process)
                } else {
                    existing.setGain(channel.gain)
                }
            } else {
                startChannel(channel, process: process)
            }
        }
    }

    /// The system default output device changed. Rebuild every channel that *follows* the default (nil
    /// output UID) so it moves to the new device — a `MixerChannelTap` resolves nil → current default only
    /// at build time, so without this a default-routed app keeps playing to the OLD device. Channels pinned
    /// to a specific device are left playing untouched.
    func handleDefaultOutputChange(_ channels: [MixerChannel]) {
        for (bundleID, uid) in routing where uid == nil {
            taps[bundleID]?.stop()
            taps[bundleID] = nil
            routing[bundleID] = nil
        }
        apply(channels)   // rebuilds the dropped default-routed channels against the new default
    }

    /// Tear down every channel (e.g. when the mixer is turned off).
    func stopAll() {
        taps.values.forEach { $0.stop() }
        taps.removeAll()
        routing.removeAll()
    }

    /// Re-scan: apps may have started/stopped producing audio. Call periodically while the mixer is on.
    func refresh(_ channels: [MixerChannel]) { apply(channels) }

    private func startChannel(_ channel: MixerChannel, process: AudioObjectID) {
        let tap = makeChannel(channel.bundleID)
        tap.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.taps[channel.bundleID] = nil
                self?.routing[channel.bundleID] = nil
                self?.onChannelFailure?(channel.bundleID, message)
            }
        }
        tap.start(processObjectID: process, outputDeviceUID: channel.outputDeviceUID)
        tap.setGain(channel.gain)
        taps[channel.bundleID] = tap
        routing[channel.bundleID] = channel.outputDeviceUID
    }
}
