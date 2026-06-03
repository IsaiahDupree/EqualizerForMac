import AudioToolbox
import CoreAudio
import Foundation

/// Minimal, original Core Audio property-access helpers.
///
/// These wrap the standard `AudioObjectGetPropertyData` dance. The selectors and
/// constants are Apple's public Core Audio API (functional facts, not creative
/// expression); the implementation here is our own.
extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    var isValid: Bool { self != AudioObjectID(kAudioObjectUnknown) }

    // MARK: Typed reads

    /// Read a fixed-size value for a property selector.
    func read<T>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                 default defaultValue: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { throw CoreAudioError.property(selector, status) }
        return value
    }

    /// Read a value that requires an input qualifier (e.g. PID → process object).
    func read<T, Q>(_ selector: AudioObjectPropertySelector,
                    qualifier: Q,
                    default defaultValue: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var inQualifier = qualifier
        let qualifierSize = UInt32(MemoryLayout<Q>.size)
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafeMutablePointer(to: &inQualifier) { qPtr in
            withUnsafeMutablePointer(to: &value) { vPtr in
                AudioObjectGetPropertyData(self, &address, qualifierSize, qPtr, &size, vPtr)
            }
        }
        guard status == noErr else { throw CoreAudioError.property(selector, status) }
        return value
    }

    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        let cf: CFString = try read(selector, default: "" as CFString)
        return cf as String
    }

    // MARK: Concrete helpers

    /// The device apps play to by default (the real speakers/headphones we re-route into).
    func readDefaultOutputDevice() throws -> AudioDeviceID {
        try read(kAudioHardwarePropertyDefaultOutputDevice, default: AudioDeviceID(kAudioObjectUnknown))
    }

    func readDeviceUID() throws -> String { try readString(kAudioDevicePropertyDeviceUID) }

    func readDeviceName() throws -> String { try readString(kAudioObjectPropertyName) }

    /// Format of the audio that will flow through a tap (an `AudioStreamBasicDescription`).
    func readTapStreamFormat() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
    }

    /// Translate a Unix pid into its Core Audio process object id (used to exclude ourselves).
    func translatePID(_ pid: pid_t) throws -> AudioObjectID {
        try read(kAudioHardwarePropertyTranslatePIDToProcessObject,
                 qualifier: pid,
                 default: AudioObjectID(kAudioObjectUnknown))
    }
}

enum CoreAudioError: LocalizedError {
    case property(AudioObjectPropertySelector, OSStatus)
    case create(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .property(sel, status):
            return "Core Audio property '\(sel.fourCC)' failed (\(status))"
        case let .create(what, status):
            return "\(what) failed (\(status))"
        }
    }
}

extension UInt32 {
    /// Render a four-char-code selector as a readable string for diagnostics.
    var fourCC: String {
        let bytes = [UInt8((self >> 24) & 0xFF), UInt8((self >> 16) & 0xFF),
                     UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
        return bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? String(bytes: bytes, encoding: .ascii) ?? "\(self)" : "\(self)"
    }
}
