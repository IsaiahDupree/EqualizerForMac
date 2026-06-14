import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// Manages one `MixerChannelTap` per app that needs non-passthrough treatment (volume / mute / routing).
/// Apps at unity/unmuted/default-output are left alone (no tap). Resolves bundle ids to live process
/// objects and reconciles the running taps to the desired channel set.
@MainActor
final class PerAppMixer {
    private var taps: [String: MixerChannelTap] = [:]
    private var routing: [String: String?] = [:]   // bundleID → outputDeviceUID it was built with
    private let log = Logger(subsystem: kSubsystem, category: "PerAppMixer")

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

        for (bundleID, channel) in wanted {
            // The app must be producing audio right now to be tapped.
            guard let process = AudioProcesses.processObjectIDs(forBundleIDs: [bundleID]).first else {
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

    /// Tear down every channel (e.g. when the mixer is turned off).
    func stopAll() {
        taps.values.forEach { $0.stop() }
        taps.removeAll()
        routing.removeAll()
    }

    /// Re-scan: apps may have started/stopped producing audio. Call periodically while the mixer is on.
    func refresh(_ channels: [MixerChannel]) { apply(channels) }

    private func startChannel(_ channel: MixerChannel, process: AudioObjectID) {
        let tap = MixerChannelTap(bundleID: channel.bundleID)
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
