import SwiftUI

/// Window onto the purchase conversion funnel recorded by `PurchaseEventTracker`. Shows the headline
/// rates, per-event counts, and the most recent events (including failures, with the underlying error
/// message). Shipped in every build (not DEBUG-only): with no remote crash/analytics reporting in this
/// app, this on-device log — visible from the footer's chart icon — is the only way a customer can see,
/// and relay to the developer (e.g. by screenshot), what actually happened around a failed purchase or
/// restore.
struct PurchaseAnalyticsView: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// Snapshot of the log (the tracker isn't `@Observable`, so we pull state explicitly and refresh).
    @State private var events: [TrackedEvent] = []
    @State private var conversion: Double?
    @State private var restoreRate: Double?
    @State private var failureRate: Double?

    private var tracker: PurchaseEventTracker { app.license.tracker }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Purchase Analytics").font(.title2.bold())
                Spacer()
                Text(app.license.store == .mock ? "MOCK STORE" : "LIVE")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((app.license.store == .mock ? Color.orange : Color.green).opacity(0.2),
                                in: Capsule())
            }

            HStack(spacing: 10) {
                rateCard("Conversion", conversion, hint: "completed ÷ paywalls", tint: .green)
                rateCard("Restore", restoreRate, hint: "restored ÷ attempts", tint: .blue)
                rateCard("Failure", failureRate, hint: "failed ÷ started", tint: .red)
            }

            Divider()

            Text("Event counts").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(PurchaseEvent.allCases, id: \.self) { event in
                    HStack {
                        Text(label(for: event)).font(.callout)
                        Spacer()
                        Text("\(tracker.count(of: event))").font(.callout.monospacedDigit().bold())
                    }
                }
            }

            Divider()

            HStack {
                Text("Recent events").font(.headline)
                Spacer()
                Text("\(events.count) total").font(.caption).foregroundStyle(.secondary)
            }
            if events.isEmpty {
                Text("No events yet — open the paywall or make a (mock) purchase.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(events.reversed().prefix(40).enumerated()), id: \.offset) { _, e in
                            eventRow(e)
                        }
                    }
                }
                .frame(height: 180)
            }

            Divider()
            HStack {
                Button(role: .destructive) {
                    tracker.clear()
                    refresh()
                } label: { Label("Clear log", systemImage: "trash") }
                .controlSize(.small)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear(perform: refresh)
    }

    // MARK: Pieces

    private func rateCard(_ title: String, _ value: Double?, hint: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(value == nil ? .secondary : tint)
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func eventRow(_ e: TrackedEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: glyph(for: e.event)).foregroundStyle(color(for: e.event)).frame(width: 16)
            Text(label(for: e.event)).font(.caption)
            if let detail = e.detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(e.store).font(.caption2).foregroundStyle(.tertiary)
            Text(Self.time.string(from: e.date)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        }
    }

    private func refresh() {
        events = tracker.events
        conversion = tracker.conversionRate
        restoreRate = tracker.restoreSuccessRate
        failureRate = tracker.purchaseFailureRate
    }

    private func label(for event: PurchaseEvent) -> String {
        switch event {
        case .paywallShown:       return "Paywall shown"
        case .purchaseStarted:    return "Purchase started"
        case .purchaseCompleted:  return "Purchase completed"
        case .purchaseCancelled:  return "Purchase cancelled"
        case .purchaseFailed:     return "Purchase failed"
        case .restoreStarted:     return "Restore started"
        case .restoreCompleted:   return "Restore completed"
        case .restoreNoEntitlement: return "Restore — nothing to restore"
        case .restoreFailed:      return "Restore failed"
        case .configured:         return "RevenueCat configured"
        case .customerInfoUpdated: return "Customer info updated"
        case .entitlementGranted: return "Entitlement granted"
        case .entitlementRevoked: return "Entitlement revoked"
        }
    }

    private func glyph(for event: PurchaseEvent) -> String {
        switch event {
        case .paywallShown:                       return "eye"
        case .purchaseStarted, .restoreStarted:   return "hourglass"
        case .purchaseCompleted, .restoreCompleted: return "checkmark.circle.fill"
        case .purchaseCancelled, .restoreNoEntitlement: return "minus.circle"
        case .purchaseFailed, .restoreFailed:     return "xmark.octagon.fill"
        case .configured:          return "gearshape"
        case .customerInfoUpdated: return "arrow.triangle.2.circlepath"
        case .entitlementGranted:  return "lock.open.fill"
        case .entitlementRevoked:  return "lock.fill"
        }
    }

    private func color(for event: PurchaseEvent) -> Color {
        switch event {
        case .purchaseCompleted, .restoreCompleted, .entitlementGranted: return .green
        case .purchaseFailed, .restoreFailed, .entitlementRevoked:       return .red
        case .purchaseCancelled, .restoreNoEntitlement: return .orange
        default: return .secondary
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
