import Foundation

/// Keeps route-change evidence for the diagnostic banner without touching audio APIs.
struct ETRouteChangeHistory {
    private struct Entry: Codable {
        let uptime: TimeInterval
        let text: String
        let fromRoute: String
        let toRoute: String
        let fromIsCarAudio: Bool
        let toIsCarAudio: Bool
        let fromIsEQRoute: Bool
        let toIsEQRoute: Bool
        let carAudioSpeakerSwap: Bool
        let carAudioEQSwap: Bool

        private enum CodingKeys: String, CodingKey {
            case uptime, text, fromRoute, toRoute, fromIsCarAudio, toIsCarAudio
            case fromIsEQRoute, toIsEQRoute, carAudioSpeakerSwap, carAudioEQSwap
        }

        init(uptime: TimeInterval, text: String, fromRoute: String, toRoute: String,
             fromIsCarAudio: Bool, toIsCarAudio: Bool, fromIsEQRoute: Bool, toIsEQRoute: Bool,
             carAudioSpeakerSwap: Bool, carAudioEQSwap: Bool) {
            self.uptime = uptime
            self.text = text
            self.fromRoute = fromRoute
            self.toRoute = toRoute
            self.fromIsCarAudio = fromIsCarAudio
            self.toIsCarAudio = toIsCarAudio
            self.fromIsEQRoute = fromIsEQRoute
            self.toIsEQRoute = toIsEQRoute
            self.carAudioSpeakerSwap = carAudioSpeakerSwap
            self.carAudioEQSwap = carAudioEQSwap
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            uptime = try values.decode(TimeInterval.self, forKey: .uptime)
            text = try values.decode(String.self, forKey: .text)
            // Keep route history written by earlier builds readable.
            fromRoute = try values.decodeIfPresent(String.self, forKey: .fromRoute) ?? ""
            toRoute = try values.decodeIfPresent(String.self, forKey: .toRoute) ?? ""
            fromIsCarAudio = try values.decodeIfPresent(Bool.self, forKey: .fromIsCarAudio) ?? false
            toIsCarAudio = try values.decodeIfPresent(Bool.self, forKey: .toIsCarAudio) ?? false
            fromIsEQRoute = try values.decodeIfPresent(Bool.self, forKey: .fromIsEQRoute) ?? false
            toIsEQRoute = try values.decodeIfPresent(Bool.self, forKey: .toIsEQRoute) ?? false
            carAudioSpeakerSwap = try values.decodeIfPresent(Bool.self, forKey: .carAudioSpeakerSwap) ?? false
            carAudioEQSwap = try values.decodeIfPresent(Bool.self, forKey: .carAudioEQSwap) ?? false
        }
    }

    static let storageKey = "sonanceEQ.audioRouteHistory"
    static let window: TimeInterval = 30
    static let displayLimit = 4

    private var entries: [Entry] = []

    init() {}

    /// Restore only route evidence from the current system-uptime epoch. A reboot
    /// resets uptime, so old entries naturally expire instead of appearing fresh.
    init(restoring data: Data?, at uptime: TimeInterval) {
        guard let data, data.count <= 16_384,
              let restored = try? JSONDecoder().decode([Entry].self, from: data) else {
            entries = []
            return
        }
        entries = restored
        expire(at: uptime)
    }

    var isBurst: Bool { entries.count >= 3 }
    var isCarAudioSpeakerBounce: Bool {
        entries.count >= 3 && entries.suffix(3).allSatisfy(\.carAudioSpeakerSwap)
    }
    var isCarAudioEQBounce: Bool {
        // Route handoffs can pass through the built-in speaker before reaching
        // CarPlay or the EQ endpoint. Detect a connected 3-change chain that
        // touches both endpoints rather than requiring every change to be a
        // direct CarPlay ↔ EQ swap.
        guard entries.count >= 3 else { return false }
        let recent = Array(entries.suffix(3))
        guard zip(recent, recent.dropFirst()).allSatisfy({ $0.toRoute == $1.fromRoute }) else {
            return false
        }
        let includesCarAudio = recent.contains { $0.fromIsCarAudio || $0.toIsCarAudio }
        let includesEQ = recent.contains { $0.fromIsEQRoute || $0.toIsEQRoute }
        return includesCarAudio && includesEQ
    }

    var summary: String {
        entries.suffix(Self.displayLimit).map(\.text).joined(separator: "\n")
    }

    var encoded: Data? {
        try? JSONEncoder().encode(entries)
    }

    mutating func record(from: String, to: String, reason: String, at uptime: TimeInterval,
                         fromIsCarAudio: Bool = false, toIsCarAudio: Bool = false,
                         fromIsBuiltInSpeaker: Bool = false, toIsBuiltInSpeaker: Bool = false,
                         fromIsEQRoute: Bool = false, toIsEQRoute: Bool = false) {
        guard uptime.isFinite else { return }
        expire(at: uptime)
        let isCarAudioSpeakerSwap = (fromIsCarAudio && toIsBuiltInSpeaker) ||
            (fromIsBuiltInSpeaker && toIsCarAudio)
        let isCarAudioEQSwap = (fromIsCarAudio && toIsEQRoute) ||
            (fromIsEQRoute && toIsCarAudio)
        entries.append(Entry(uptime: uptime, text: "\(from) → \(to) (\(reason))",
                             fromRoute: from, toRoute: to,
                             fromIsCarAudio: fromIsCarAudio, toIsCarAudio: toIsCarAudio,
                             fromIsEQRoute: fromIsEQRoute, toIsEQRoute: toIsEQRoute,
                             carAudioSpeakerSwap: isCarAudioSpeakerSwap,
                             carAudioEQSwap: isCarAudioEQSwap))
    }

    mutating func expire(at uptime: TimeInterval) {
        guard uptime.isFinite else { return }
        entries.removeAll { entry in
            uptime < entry.uptime || uptime - entry.uptime > Self.window
        }
    }
}

/// Pure presentation logic for the route-state banner, kept outside SwiftUI so
/// route-flap diagnosis and the recovery instructions can be tested directly.
struct ETRouteStatusPresentation {
    let title: String
    let instruction: String

    static func shouldDisplayBanner(hasPeer: Bool,
                                    routeFallback: Bool,
                                    routeReturnedFromSonanceEQ: Bool,
                                    carAudioActive: Bool,
                                    routeChangeBurst: Bool,
                                    carAudioSpeakerBounce: Bool = false,
                                    carAudioEQBounce: Bool = false) -> Bool {
        !hasPeer || routeFallback || routeReturnedFromSonanceEQ || carAudioActive || routeChangeBurst || carAudioSpeakerBounce || carAudioEQBounce
    }

    static func shouldOfferLocalPlayerRecovery(restartNeeded: Bool,
                                               noAudioAvailable: Bool = false,
                                               routeFallback: Bool,
                                               routeReturnedFromSonanceEQ: Bool,
                                               carAudioActive: Bool,
                                               routeChangeBurst: Bool,
                                               carAudioSpeakerBounce: Bool = false,
                                               carAudioEQBounce: Bool = false) -> Bool {
        !restartNeeded && (noAudioAvailable || routeFallback || routeReturnedFromSonanceEQ || carAudioActive ||
                           routeChangeBurst || carAudioSpeakerBounce || carAudioEQBounce)
    }

    static func make(restartNeeded: Bool,
                     deviceName: String,
                     currentRoute: String,
                     routeFallback: Bool,
                     routeReturnedFromSonanceEQ: Bool,
                     carAudioActive: Bool,
                     routeChangeBurst: Bool,
                     lastRouteChange: String,
                     carAudioSpeakerBounce: Bool = false,
                     carAudioEQBounce: Bool = false) -> Self {
        if restartNeeded {
            return Self(
                title: "\(deviceName) Restart Required",
                instruction: "Restart once after this update, then pick Sonance EQ in Control Center. Install Sonance EQ Route if it is not listed.")
        }
        if carAudioSpeakerBounce {
            return Self(
                title: "CarPlay and iPhone output keep switching",
                instruction: "iOS detected repeated switches between CarPlay and the iPhone speaker. If the player says it does not support EffectDeck Audio or Sonance EQ Audio, that source cannot send audio through Sonance EQ. Leave CarPlay selected for car playback (EQ is bypassed), or use a compatible source or local file for EQ. Sonance EQ cannot force an unsupported route.")
        }
        if carAudioEQBounce {
            return Self(
                title: "CarPlay and Sonance EQ keep switching",
                instruction: "iOS detected repeated handoffs between CarPlay and Sonance EQ. If the player says it does not support EffectDeck Audio or Sonance EQ Audio, that source rejects the EQ route. Keep CarPlay selected for car playback, or use a compatible source or local file for EQ. Sonance EQ cannot force an unsupported route.")
        }
        if routeChangeBurst {
            return Self(
                title: "Audio route keeps changing",
                instruction: "iOS changed the audio route several times in 30 seconds. Recent changes: \(lastRouteChange). Stop toggling between routes. For car audio, leave CarPlay selected (EQ is bypassed); for EQ, use a compatible player or local file.")
        }
        if routeReturnedFromSonanceEQ {
            return Self(
                title: "Audio left the EQ route for \(currentRoute)",
                instruction: "iOS moved playback from Sonance EQ to this output; that handoff alone does not mean the EQ is faulty. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, stop retrying that route. Keep CarPlay selected for car audio (EQ is bypassed), or use a compatible player / local file for EQ. Sonance EQ cannot override iOS route selection.")
        }
        if routeFallback {
            return Self(
                title: "Output is on \(currentRoute)",
                instruction: "No source audio has reached Sonance EQ. Current output: \(currentRoute). If the player rejected Sonance EQ Audio, stop retrying that route; use CarPlay directly or play a local file. Otherwise select Sonance EQ once in Control Center and resume.")
        }
        if carAudioActive {
            return Self(
                title: "Output is routed to car audio",
                instruction: "The current output is \(currentRoute). Playback on this route bypasses Sonance EQ unless the source supports and selects the Sonance EQ route. If SoundCloud rejects it, keep CarPlay selected or use a compatible source.")
        }
        return Self(
            title: "No audio reached Sonance EQ",
            instruction: "The current source has not sent audio to Sonance EQ. iOS and the source app decide whether this route is supported; Sonance EQ can report the route but cannot force it or read another app’s rejection alert. If SoundCloud says EffectDeck Audio is unsupported, stop retrying that route: keep CarPlay selected for car audio (EQ is bypassed), or play a local file in Sonance EQ. For a source that supports system routing, select Sonance EQ once in Control Center.")
    }
}

/// User-controlled support report. Keep it limited to route diagnostics; never
/// include track names, audio samples, or automatically transmit the report.
enum ETRouteDiagnosticReport {
    static func make(appVersion: String,
                     build: String,
                     osVersion: String,
                     currentOutput: String,
                     routeFallback: Bool,
                     routeReturnedFromSonanceEQ: Bool,
                     carAudioActive: Bool,
                     routeChangeBurst: Bool,
                     carAudioSpeakerBounce: Bool,
                     carAudioEQBounce: Bool,
                     recentChanges: String) -> String {
        let output = currentOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let transitions = recentChanges.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Sonance EQ route report
        App: \(appVersion) (\(build))
        iOS: \(osVersion)
        Current output: \(output.isEmpty || output == "—" ? "Unknown" : output)
        Route fallback: \(routeFallback)
        Returned from Sonance EQ: \(routeReturnedFromSonanceEQ)
        Car audio active: \(carAudioActive)
        Route changes in last 30 seconds: \(routeChangeBurst)
        CarPlay/iPhone speaker bounce: \(carAudioSpeakerBounce)
        CarPlay/Sonance EQ bounce: \(carAudioEQBounce)
        Recent route changes:
        \(transitions.isEmpty ? "None recorded" : transitions)
        """
    }
}
