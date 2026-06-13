import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// A running app that is currently producing audio output.
struct AudioApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// What the EQ is applied to: every app (a global tap) or a chosen set of apps (a mixdown tap).
enum EQTarget: Equatable {
    case allApps
    case apps(Set<String>)   // bundle IDs

    var isAllApps: Bool { if case .allApps = self { return true } else { return false } }
}

/// Enumerates Core Audio "process objects" so the user can pick which apps to equalize (per-app EQ).
enum AudioProcesses {
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
            guard !bundleID.isEmpty, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID
            apps.append(AudioApp(bundleID: bundleID, name: name))
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
}
