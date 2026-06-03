import Foundation
import OSLog

/// Checks/requests the macOS "Audio Capture" TCC permission required to tap system audio.
///
/// There is no PUBLIC API to query or request this permission. For the direct
/// (Developer ID) build we use the private TCC SPI behind `ENABLE_TCC_SPI` to give a
/// clean onboarding flow. For a Mac App Store build that flag is turned off and we fall
/// back to the public behavior (the prompt appears the first time capture starts).
@MainActor
@Observable
final class AudioRecordingPermission {
    enum Status { case unknown, denied, authorized }

    private(set) var status: Status = .unknown
    private let log = Logger(subsystem: kSubsystem, category: "Permission")

    init() {
        #if ENABLE_TCC_SPI
        refresh()
        #else
        status = .authorized   // assume; failures surface when the tap fails to start
        #endif
    }

    func refresh() {
        #if ENABLE_TCC_SPI
        guard let preflight = Self.preflight else { return }
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: status = .authorized
        case 1: status = .denied
        default: status = .unknown
        }
        #endif
    }

    func request(_ completion: @escaping (Bool) -> Void) {
        #if ENABLE_TCC_SPI
        guard let request = Self.request else {
            log.fault("TCCAccessRequest SPI unavailable")
            completion(false)
            return
        }
        request("kTCCServiceAudioCapture" as CFString, nil) { granted in
            DispatchQueue.main.async {
                self.status = granted ? .authorized : .denied
                completion(granted)
            }
        }
        #else
        status = .authorized
        completion(true)
        #endif
    }

    #if ENABLE_TCC_SPI
    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static let preflight: PreflightFn? = symbol("TCCAccessPreflight")
    private static let request: RequestFn? = symbol("TCCAccessRequest")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
    #endif
}
