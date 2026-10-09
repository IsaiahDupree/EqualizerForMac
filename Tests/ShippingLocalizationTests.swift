import Foundation
import Testing
@testable import SonanceEQ

@Suite struct ShippingLocalizationTests {
    private let languages = ["pl", "vi", "cs", "it", "pt-PT", "el", "hu", "zh-Hant"]

    @Test func shippingBundlesHaveCompleteCatalogsAndPermissionCopy() throws {
        let app = Bundle(identifier: "com.isaiahdupree.SonanceEQ") ?? .main
        let englishPath = try #require(app.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let english = try catalog(englishPath)
        for language in languages {
            let path = try #require(app.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            let translated = try catalog(path)
            #expect(Set(translated.keys) == Set(english.keys))
            for (key, value) in translated {
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(placeholders(key) == placeholders(value))
            }
            let permissionPath = try #require(app.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language))
            let permission = try catalog(permissionPath)
            #expect(permission["NSAudioCaptureUsageDescription"] != nil)
            #expect(permission["NSAudioCaptureUsageDescription"] != english["NSAudioCaptureUsageDescription"])
            let bundlePath = try #require(app.path(forResource: language, ofType: "lproj"))
            let localizedBundle = try #require(Bundle(path: bundlePath))
            #expect(localizedBundle.localizedString(forKey: "Unlock Pro", value: nil, table: nil) != "Unlock Pro")
            let format = localizedBundle.localizedString(forKey: "Unlock Pro · %@", value: nil, table: nil)
            #expect(String(format: format, "PRICE-FROM-STOREKIT").contains("PRICE-FROM-STOREKIT"))
        }
    }

    private func catalog(_ path: String) throws -> [String: String] {
        let parsed = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil)
        return try #require(parsed as? [String: String])
    }

    private func placeholders(_ text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: "%[+\\-.0-9$]*[@dfiu]")
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            String(text[Range($0.range, in: text)!])
        }.sorted()
    }
}
