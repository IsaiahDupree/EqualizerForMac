import Foundation
import Testing
@testable import SonanceEQ

/// Real UserDefaults and a separate actual loopback HTTP server. The receiver
/// owns its acceptance protocol; these tests never impersonate PostHog.
private final class JourneyAcceptanceServer {
    let directory: URL
    let process = Process()
    let token = UUID().uuidString
    private let output: FileHandle

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("accept.py")
        try """
        import http.server,json,pathlib,sys
        root=pathlib.Path(sys.argv[1]); token=sys.argv[2]
        class Receiver(http.server.BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_POST(self):
                length=int(self.headers.get('Content-Length','0'))
                body=json.loads(self.rfile.read(length))
                if body.get('api_key')!=token:
                    self.send_response(401); self.end_headers(); return
                (root/'received.json').write_text(json.dumps(body))
                self.send_response(307 if self.path=='/redirect' else 403 if self.path=='/reject' else 202)
                if self.path=='/redirect': self.send_header('Location','/followed')
                self.end_headers()
                (root/'path.txt').write_text(self.path)
                if self.path=='/oversized': self.wfile.write(b'x'*131072)
        server=http.server.HTTPServer(('127.0.0.1',0),Receiver)
        (root/'port.txt').write_text(str(server.server_port))
        server.serve_forever()
        """.write(to: script, atomically: true, encoding: .utf8)
        let log = directory.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        output = try FileHandle(forWritingTo: log)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, directory.path, token]
        process.standardOutput = output; process.standardError = output
        try process.run()
    }

    func endpoint(_ path: String = "/accept") async throws -> URL {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let portFile = directory.appendingPathComponent("port.txt")
        while !FileManager.default.fileExists(atPath: portFile.path), process.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let port = try String(contentsOf: portFile, encoding: .utf8)
        return try #require(URL(string: "http://127.0.0.1:\(port)\(path)"))
    }

    func body() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("received.json"))) as? [String: Any])
    }

    func close() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? output.close(); try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct ProductJourneyTrackerTests {
    private func fresh() throws -> (ProductJourneyTracker, UserDefaults, String) {
        let name = "test.nativeJourney.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (ProductJourneyTracker(defaults: defaults, configuration: nil), defaults, name)
    }

    @Test func noConsentCreatesNoQueueAndNoNetworkRead() async throws {
        let (tracker, _, name) = try fresh()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        tracker.observeSession(); tracker.observeAudioFlow(true)
        await tracker.flush()
        #expect(!tracker.optedIn); #expect(tracker.pendingCount == 0); #expect(tracker.delivery == .disabled)
    }

    @Test func consentRevocationClearsPersistenceAndRotatesSubject() throws {
        let (tracker, defaults, name) = try fresh()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        tracker.setConsent(true); tracker.observeSession()
        #expect(ProductJourneyTracker(defaults: defaults, configuration: nil).pendingCount == 1)
        tracker.setConsent(false)
        let reloaded = ProductJourneyTracker(defaults: defaults, configuration: nil)
        #expect(!reloaded.optedIn); #expect(reloaded.pendingCount == 0)
        tracker.setConsent(true); #expect(tracker.pendingCount == 0)
    }

    @Test func routeObservationRequiresFlowAndQueueStaysBounded() throws {
        let (tracker, _, name) = try fresh()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        tracker.setConsent(true); tracker.observeAudioFlow(false)
        #expect(tracker.pendingCount == 0)
        tracker.observeAudioFlow(true); tracker.observeAudioFlow(true)
        #expect(tracker.pendingCount == 1)
        for _ in 0..<110 { tracker.observeSession() }
        #expect(tracker.pendingCount == 100); #expect(tracker.discardedCount == 11)
    }

    @Test func handoffRejectsAmbiguityIdentityAndWrongProduct() throws {
        let (tracker, _, name) = try fresh()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        tracker.setConsent(true)
        let base = "sonanceeq://campaign?cie_product_id=sonance-eq&cie_click_id=probe-click&cie_campaign_id=probe-campaign"
        #expect(tracker.receive(try #require(URL(string: base))))
        for text in [base + "&cie_click_id=other", base + "&email=private", base + "#fragment",
                     base.replacingOccurrences(of: "sonance-eq", with: "everreach"),
                     base.replacingOccurrences(of: "probe-click", with: "name%40example.com")] {
            #expect(!tracker.receive(try #require(URL(string: text))))
        }
        #expect(tracker.pendingCount == 1)
        #expect(ProductJourneyTracker.Configuration(projectToken: "phx_reader", origin: "https://us.i.posthog.com") == nil)
        #expect(ProductJourneyTracker.Configuration(projectToken: "phc_project", origin: "https://us.i.posthog.com@other.example") == nil)
    }

    @Test func actualHTTPDeliveryHasPrivateFieldsAndNoInventedLineage() async throws {
        let server = try JourneyAcceptanceServer(); defer { server.close() }
        let (tracker, _, name) = try fresh()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        tracker.setConsent(true)
        #expect(tracker.receive(try #require(URL(string: "sonanceeq://campaign?cie_product_id=sonance-eq&cie_click_id=probe-click&cie_campaign_id=probe-campaign"))))
        tracker.observeAudioFlow(true)
        await tracker.deliverToLocalAcceptanceServer(try await server.endpoint(), token: server.token)
        #expect(tracker.delivery == .accepted); #expect(tracker.pendingCount == 0)
        let body = try server.body(), batch = try #require(body["batch"] as? [[String: Any]])
        #expect(batch.count == 2)
        let subjects = Set(batch.compactMap { $0["distinct_id"] as? String })
        #expect(subjects.count == 1)
        for item in batch {
            let properties = try #require(item["properties"] as? [String: Any])
            #expect(properties["$process_person_profile"] as? Bool == false)
            #expect(properties["$geoip_disable"] as? Bool == true)
            #expect(properties["audibility_verified"] as? Bool == false)
            #expect(properties["is_test"] as? Bool == true)
            #expect(properties["cie_click_id"] == nil); #expect(properties["click_id"] == nil)
            #expect(properties["email"] == nil); #expect(properties["revenue"] == nil)
        }
    }

    @Test func actualHTTPRejectionAndRedirectPreserveUnsentQueue() async throws {
        let server = try JourneyAcceptanceServer(); defer { server.close() }
        let (tracker, _, name) = try fresh()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        tracker.setConsent(true); tracker.observeSession()
        await tracker.deliverToLocalAcceptanceServer(try await server.endpoint("/reject"), token: server.token)
        #expect(tracker.delivery == .failed); #expect(tracker.pendingCount == 1)
        let rejected = try server.body()
        await tracker.deliverToLocalAcceptanceServer(try await server.endpoint("/redirect"), token: server.token)
        #expect(tracker.delivery == .failed); #expect(tracker.pendingCount == 1)
        let redirected = try server.body()
        #expect(try String(contentsOf: server.directory.appendingPathComponent("path.txt"), encoding: .utf8) == "/redirect")
        #expect(try JSONSerialization.data(withJSONObject: rejected, options: .sortedKeys)
                == JSONSerialization.data(withJSONObject: redirected, options: .sortedKeys))
        await tracker.deliverToLocalAcceptanceServer(try await server.endpoint("/oversized"), token: server.token)
        #expect(tracker.delivery == .failed); #expect(tracker.pendingCount == 1)
    }
}
