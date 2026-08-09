import Foundation
import MetricKit
import OSLog

/// Subscribes to Apple's on-device MetricKit pipeline so crashes, hangs, and CPU/disk exceptions
/// that happen on a customer's Mac aren't **completely** invisible to the developer.
///
/// Every other error path in this app (`PurchaseManager`, `SystemAudioTap`, ...) is deliberately
/// local-only — see `PurchaseEventTracker`'s doc comment: "without any third-party analytics SDK".
/// That's fine for errors the process is alive to log. It is not fine for a **crash**: the process
/// is dead before any `Logger` call can run, so today a crash produces zero signal anywhere, even
/// locally. MetricKit is the first-party, zero-dependency, zero-backend mechanism Apple ships for
/// exactly this: on the *next* launch after a crash/hang, the OS hands the app a summary of what
/// happened. No new SPM package, no new entitlement, no network code of our own — consistent with
/// the "no third-party SDK" decision already made for purchase tracking.
///
/// This does not replace real remote crash aggregation (Xcode Organizer, populated for users who've
/// opted in to "Share Mac Analytics With App Developers") — it's the guaranteed local backstop, and
/// it now means a support conversation can start with "let's check Console for MetricKit crash/hang
/// entries" instead of "there's no way to know what happened."
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    private let log = Logger(subsystem: kSubsystem, category: "Diagnostics")

    /// Call once at launch, before anything that could crash/hang.
    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: MXMetricManagerSubscriber

    /// Crash / hang / CPU / disk-write diagnostics for the *previous* run(s), delivered on this launch.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let window = "\(payload.timeStampBegin)..\(payload.timeStampEnd)"
            report(payload.crashDiagnostics?.count, kind: "crash", window: window)
            report(payload.hangDiagnostics?.count, kind: "hang", window: window)
            report(payload.cpuExceptionDiagnostics?.count, kind: "cpuException", window: window)
            report(payload.diskWriteExceptionDiagnostics?.count, kind: "diskWriteException", window: window)
        }
    }

    /// Aggregated performance metrics, including counts for any `os_signpost` events we emit
    /// (e.g. purchase/tap failures), delivered roughly daily.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            for signpost in payload.signpostMetrics ?? [] {
                log.notice("MetricKit signpost \(signpost.signpostCategory, privacy: .public).\(signpost.signpostName, privacy: .public) x\(signpost.totalCount)")
            }
        }
    }

    // MARK: Private

    private func report(_ count: Int?, kind: String, window: String) {
        guard let count, count > 0 else { return }
        log.error("MetricKit \(kind, privacy: .public) x\(count) — window \(window, privacy: .public)")
    }
}
