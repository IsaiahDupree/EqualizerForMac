import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// A running app that is currently producing audio output.
struct AudioApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    /// The app's own icon (from `NSRunningApplication.icon`), for picker UI. Every `AudioApp` we
    /// construct comes from a resolved, user-facing `NSRunningApplication`, so this is only ever
    /// nil in the rare case Launch Services has no icon to hand back.
    let icon: NSImage?
    var id: String { bundleID }

    // `NSImage` isn't `Hashable`, and `bundleID` already is the identity (see `id`), so hash/compare
    // on that alone rather than deriving a synthesized conformance across all stored properties.
    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool { lhs.bundleID == rhs.bundleID }
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
}

/// What the EQ is applied to: every app (a global tap) or a chosen set of apps (a mixdown tap).
enum EQTarget: Equatable {
    case allApps
    case apps(Set<String>)   // bundle IDs

    var isAllApps: Bool { if case .allApps = self { return true } else { return false } }
}

/// Enumerates Core Audio "process objects" so the user can pick which apps to equalize (per-app EQ).
enum AudioProcesses {
    /// Sibling Sonance audio-tool apps we must NEVER tap. They re-inject system/other-app audio, so tapping
    /// one (or being tapped by it) creates a feedback/doubling loop when both apps run at once — the source
    /// of the "sound doubles / goes silent when I toggle the other app" interference.
    static let siblingBundleIDs: Set<String> = [
        "com.isaiahdupree.SonanceEQ", "com.isaiahdupree.SonanceMixer",
    ]

    /// All Core Audio process object IDs.
    static func processObjectIDs() -> [AudioObjectID] {
        (try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList) as [AudioObjectID]) ?? []
    }

    /// Apps that are currently playing audio (deduped by bundle id, excluding ourselves), sorted by name.
    static func runningOutputApps() -> [AudioApp] {
        let selfPID = getpid()
        var seen = Set<String>()
        var apps: [AudioApp] = []
        for object in processObjectIDs() {
            let isOutput: UInt32 = (try? object.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0
            guard isOutput != 0 else { continue }
            let pid: pid_t = (try? object.read(kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1
            guard pid != selfPID else { continue }
            let bundleID = (try? object.readString(kAudioProcessPropertyBundleID)) ?? ""
            guard !bundleID.isEmpty, !siblingBundleIDs.contains(bundleID), !seen.contains(bundleID) else { continue }
            // Only surface processes Launch Services tracks as real, user-facing apps. Background Core
            // Audio processes — system audio daemons, XPC services, telephony/Continuity helpers, etc. —
            // either don't resolve to an `NSRunningApplication` at all, or resolve with a `.prohibited`
            // activation policy (no Dock presence, no UI, can't be brought to front). Skip both instead
            // of falling back to displaying their raw Core Audio bundle ID.
            guard let runningApp = NSRunningApplication(processIdentifier: pid),
                  runningApp.activationPolicy != .prohibited,
                  let name = runningApp.localizedName else { continue }
            seen.insert(bundleID)
            apps.append(AudioApp(bundleID: bundleID, name: name, icon: runningApp.icon))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolve the given bundle IDs to their current process object IDs (those that exist right now).
    static func processObjectIDs(forBundleIDs bundleIDs: Set<String>) -> [AudioObjectID] {
        processObjectIDs().filter { object in
            let bundleID = (try? object.readString(kAudioProcessPropertyBundleID)) ?? ""
            return bundleIDs.contains(bundleID)
        }
    }

    /// Resolve many bundle IDs to their current process object IDs in a single system enumeration.
    /// Callers that need to resolve N bundle IDs (e.g. `PerAppMixer.apply` reconciling N active channels)
    /// MUST use this instead of calling `processObjectIDs(forBundleIDs:)` once per bundle ID — that would
    /// re-run the full `kAudioHardwarePropertyProcessObjectList` Core Audio scan N times over.
    static func processObjectIDMap(forBundleIDs bundleIDs: Set<String>) -> [String: AudioObjectID] {
        guard !bundleIDs.isEmpty else { return [:] }
        var result: [String: AudioObjectID] = [:]
        for object in processObjectIDs() {
            let bundleID = (try? object.readString(kAudioProcessPropertyBundleID)) ?? ""
            guard bundleIDs.contains(bundleID), result[bundleID] == nil else { continue }
            result[bundleID] = object   // first match wins, matching the `.first` semantics this replaces
        }
        return result
    }
}
