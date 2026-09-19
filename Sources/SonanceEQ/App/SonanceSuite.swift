import AppKit
import Foundation
import SwiftUI

enum SonanceSuiteApp: String, CaseIterable, Identifiable {
    case eq, mixer, recorder, voice

    var id: String { rawValue }
    var name: String {
        switch self {
        case .eq: "Sonance EQ"
        case .mixer: "Sonance Mixer"
        case .recorder: "Sonance Recorder"
        case .voice: "Sonance Voice"
        }
    }
    var appStoreID: String {
        switch self {
        case .eq: "6782463839"
        case .mixer: "6787488996"
        case .recorder: "6787489259"
        case .voice: "6787489282"
        }
    }
    var appStoreURL: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }
}

enum SonanceSuite {
    static func siblings(of current: SonanceSuiteApp) -> [SonanceSuiteApp] {
        SonanceSuiteApp.allCases.filter { $0 != current }
    }

    static func open(_ destination: SonanceSuiteApp, from source: SonanceSuiteApp,
                     defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: referralKey(from: source, to: destination)) + 1,
                     forKey: referralKey(from: source, to: destination))
        NSWorkspace.shared.open(destination.appStoreURL)
    }

    static func referralKey(from source: SonanceSuiteApp, to destination: SonanceSuiteApp) -> String {
        "sonanceSuiteReferral.\(source.rawValue).\(destination.rawValue)"
    }
}

struct SonanceSuiteMenu: View {
    let current: SonanceSuiteApp
    var body: some View {
        Menu("More Sonance") {
            ForEach(SonanceSuite.siblings(of: current)) { destination in
                Button(destination.name) { SonanceSuite.open(destination, from: current) }
            }
        }
    }
}
