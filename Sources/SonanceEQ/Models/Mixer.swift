import Foundation

/// One app's mixer settings: independent volume, mute, and output-device routing.
struct MixerChannel: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var volume: Float = 1            // 0…1.25 linear (1 = unity, >1 = boost)
    var muted: Bool = false
    var outputDeviceUID: String?     // nil = follow the system default output

    var id: String { bundleID }

    /// Linear gain actually applied to this app's audio (0 when muted).
    var gain: Float { muted ? 0 : max(0, min(volume, MixerChannel.maxVolume)) }

    /// True when this channel changes nothing (unity, unmuted, default output) — no tap needed.
    var isPassthrough: Bool { !muted && abs(volume - 1) < 0.001 && outputDeviceUID == nil }

    static let maxVolume: Float = 1.25
}

/// Observable mixer state: per-app channels, persisted by bundle id. The engine reads `gain`/output for
/// each app it controls. Only apps that differ from passthrough need an actual tap.
@MainActor
@Observable
final class MixerState {
    private(set) var channels: [String: MixerChannel] = [:]

    private let defaults: UserDefaults
    private let storeKey = "mixerChannels.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// The channel for an app, creating a default (unity/unmuted/default-output) one if unseen.
    func channel(_ bundleID: String, name: String) -> MixerChannel {
        channels[bundleID] ?? MixerChannel(bundleID: bundleID, name: name)
    }

    /// Channels that actually do something (need a tap) — what the engine routes.
    var activeChannels: [MixerChannel] {
        channels.values.filter { !$0.isPassthrough }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setVolume(_ volume: Float, for bundleID: String, name: String) {
        var c = channel(bundleID, name: name)
        c.volume = max(0, min(volume, MixerChannel.maxVolume))
        commit(c)
    }

    func setMuted(_ muted: Bool, for bundleID: String, name: String) {
        var c = channel(bundleID, name: name)
        c.muted = muted
        commit(c)
    }

    func setOutput(_ uid: String?, for bundleID: String, name: String) {
        var c = channel(bundleID, name: name)
        c.outputDeviceUID = uid
        commit(c)
    }

    /// Reset a channel to passthrough (and forget it).
    func reset(_ bundleID: String) {
        channels[bundleID] = nil
        save()
    }

    // MARK: - Persistence

    private func commit(_ channel: MixerChannel) {
        if channel.isPassthrough {
            channels[channel.bundleID] = nil   // don't persist no-ops
        } else {
            channels[channel.bundleID] = channel
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Array(channels.values)) {
            defaults.set(data, forKey: storeKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([MixerChannel].self, from: data) else { return }
        channels = Dictionary(uniqueKeysWithValues: list.map { ($0.bundleID, $0) })
    }
}
