import Foundation
import SonanceAnalytics

// Generate the server allowlist from the same typed catalog used by all clients.
let catalog: [String: Any] = [
    "schema_version": 2,
    "apps": Dictionary(uniqueKeysWithValues: SonanceApp.allCases.map { app in
        (app.rawValue, ["title": app.title, "features": app.features.map(\.rawValue)] as [String: Any])
    }),
    "feedback_reasons": FeatureFeedback.allCases.map(\.rawValue),
    "outcome_reasons": Dictionary(uniqueKeysWithValues: FeatureOutcome.allCases.map { outcome in
        (outcome.rawValue, FeatureReason.allCases.filter { $0.supports(outcome) }.map(\.rawValue))
    })
]
let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
