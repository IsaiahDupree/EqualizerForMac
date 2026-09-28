import Foundation
import Testing
@testable import SonanceEQ

@Suite struct PaywallLocalizationTests {
    @Test func frenchPaywallContainsEveryShippingString() throws {
        let appBundle = Bundle(identifier: "com.isaiahdupree.SonanceEQ") ?? .main
        let path = try #require(appBundle.path(forResource: "fr", ofType: "lproj"))
        let french = try #require(Bundle(path: path))

        let expected = [
            "Sonance EQ Pro": "Sonance EQ Pro",
            "Unlock the full equalizer — a one-time purchase.":
                "Débloquez l’égaliseur complet avec un achat unique.",
            "8,850 AutoEq headphone corrections": "8 850 corrections AutoEq pour casques",
            "Full parametric EQ — up to 32 bands":
                "Égaliseur paramétrique complet — jusqu’à 32 bandes",
            "Linear-phase mode": "Mode à phase linéaire",
            "Mid-Side EQ (center vs. width)": "Égaliseur Mid-Side (centre et largeur)",
            "Import & export presets": "Importer et exporter des préréglages",
            "Unlock Pro · %@": "Débloquer Pro · %@",
            "Unlock Pro (mock) · %@": "Débloquer Pro (test) · %@",
            "Restore Purchase": "Restaurer l’achat",
            "Relock (mock)": "Reverrouiller (test)",
            "Not now": "Plus tard",
            "Cancel": "Annuler",
        ]

        for (key, value) in expected {
            #expect(french.localizedString(forKey: key, value: nil, table: nil) == value)
        }
    }
}
