import Foundation
import Network
import Security

// A real loopback-only Network.framework feasibility test. The transport is
// not yet integrated with the route lab or the Media Device extension.
enum ProbeError: Error { case random, listenerTimeout, listenerFailed, plaintextTimeout, wrongKeyTimeout, rejectedPeer, noPayload, badPayload, impostorTimeout, badNegotiation }

func randomData(count: Int) throws -> Data {
    var data = Data(count: count)
    let status = data.withUnsafeMutableBytes { bytes in
        SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
    }
    guard status == errSecSuccess else { throw ProbeError.random }
    return data
}

func tlsParameters(key: Data, identity: Data, listen: Bool = false) -> NWParameters {
    let options = NWProtocolTLS.Options()
    let security = options.securityProtocolOptions
    // Apple's current Network.framework PSK support uses TLS 1.2.
    sec_protocol_options_set_min_tls_protocol_version(security, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(security, .TLSv12)
    sec_protocol_options_append_tls_ciphersuite(security, tls_ciphersuite_t(rawValue: 0x00A8)!)
    let secret = key.withUnsafeBytes { DispatchData(bytes: $0) }
    let name = identity.withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(security, secret as __DispatchData, name as __DispatchData)
    let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
    if listen {
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    }
    return parameters
}

final class ListenerProbe {
    let queue = DispatchQueue(label: "sonance.route.tls-test")
    let ready = DispatchSemaphore(value: 0)
    let received = DispatchSemaphore(value: 0)
    let lock = NSLock()
    let listener: NWListener
    var failure: NWError?
    var payloads: [Data] = []
    var connections: [NWConnection] = []
    var badNegotiation = false
    let expectedBytes: Int

    init(key: Data, identity: Data, expectedBytes: Int) throws {
        self.expectedBytes = expectedBytes
        listener = try NWListener(using: tlsParameters(key: key, identity: identity, listen: true))
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state { self.ready.signal() }
            if case .failed(let error) = state {
                self.lock.lock(); self.failure = error; self.lock.unlock()
                self.ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.lock.lock(); self.connections.append(connection); self.lock.unlock()
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection else { return }
                if case .ready = state {
                    guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
                          sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata) == .TLSv12,
                          sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata.securityProtocolMetadata).rawValue == 0x00A8 else {
                        self.lock.lock(); self.badNegotiation = true; self.lock.unlock()
                        self.received.signal()
                        connection.cancel()
                        return
                    }
                    connection.receive(minimumIncompleteLength: self.expectedBytes, maximumLength: self.expectedBytes) {
                        [weak self] data, _, _, _ in
                        guard let self, let data, !data.isEmpty else { return }
                        self.lock.lock(); self.payloads.append(data); self.lock.unlock()
                        self.received.signal()
                    }
                }
            }
            connection.start(queue: self.queue)
        }
        listener.start(queue: queue)
    }

    func port() throws -> NWEndpoint.Port {
        guard ready.wait(timeout: .now() + 5) == .success else { throw ProbeError.listenerTimeout }
        lock.lock(); let error = failure; lock.unlock()
        guard error == nil, let port = listener.port else { throw ProbeError.listenerFailed }
        return port
    }

    func payloadSnapshot() -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return payloads
    }

    func negotiatedUnexpectedly() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return badNegotiation
    }

    func stop() {
        listener.cancel()
        lock.lock(); let peers = connections; lock.unlock()
        peers.forEach { $0.cancel() }
    }
}

func connect(port: NWEndpoint.Port, parameters: NWParameters, payload: Data,
             queue: DispatchQueue, onReady: DispatchSemaphore? = nil,
             onFailure: DispatchSemaphore? = nil) -> NWConnection {
    let connection = NWConnection(host: .ipv4(.loopback), port: port, using: parameters)
    connection.stateUpdateHandler = { [weak connection] state in
        guard let connection else { return }
        if case .ready = state {
            onReady?.signal()
            connection.send(content: payload, completion: .contentProcessed { _ in })
        }
        if case .failed(.tls(let status)) = state, status == errSSLPeerBadRecordMac { onFailure?.signal() }
        if case .waiting(.tls(let status)) = state, status == errSSLPeerBadRecordMac {
            onFailure?.signal()
        }
    }
    connection.start(queue: queue)
    return connection
}

@main
struct VerifyTLSPSK {
    static func main() {
        do { try run() }
        catch { fputs("FAIL: TLS-PSK probe: \(error)\n", stderr); exit(1) }
    }

    static func run() throws {
        let secret = try randomData(count: 32)
        let wrongSecret = try randomData(count: 32)
        let identity = try randomData(count: 16)
        let payload = try randomData(count: 64)
        let probe = try ListenerProbe(key: secret, identity: identity, expectedBytes: payload.count)
        defer { probe.stop() }
        let port = try probe.port()

        let wrongFailure = DispatchSemaphore(value: 0)
        let plaintextReady = DispatchSemaphore(value: 0)
        let wrong = connect(port: port, parameters: tlsParameters(key: wrongSecret, identity: identity),
                            payload: payload, queue: probe.queue, onFailure: wrongFailure)
        defer { wrong.cancel() }
        let plaintext = connect(port: port, parameters: .tcp, payload: payload, queue: probe.queue,
                                onReady: plaintextReady)
        defer { plaintext.cancel() }
        guard plaintextReady.wait(timeout: .now() + 5) == .success else { throw ProbeError.plaintextTimeout }
        guard wrongFailure.wait(timeout: .now() + 5) == .success else { throw ProbeError.wrongKeyTimeout }
        guard probe.received.wait(timeout: .now() + 2) == .timedOut,
              probe.payloadSnapshot().isEmpty else { throw ProbeError.rejectedPeer }

        let authorized = connect(port: port, parameters: tlsParameters(key: secret, identity: identity),
                                 payload: payload, queue: probe.queue)
        defer { authorized.cancel() }
        guard probe.received.wait(timeout: .now() + 5) == .success else { throw ProbeError.noPayload }
        guard !probe.negotiatedUnexpectedly() else { throw ProbeError.badNegotiation }
        guard probe.payloadSnapshot() == [payload] else { throw ProbeError.badPayload }

        // A client must also reject a server that has a different secret.
        let impostor = try ListenerProbe(key: wrongSecret, identity: identity, expectedBytes: payload.count)
        defer { impostor.stop() }
        let impostorPort = try impostor.port()
        let impostorFailure = DispatchSemaphore(value: 0)
        let cautiousClient = connect(port: impostorPort, parameters: tlsParameters(key: secret, identity: identity),
                                     payload: payload, queue: impostor.queue, onFailure: impostorFailure)
        defer { cautiousClient.cancel() }
        guard impostorFailure.wait(timeout: .now() + 5) == .success else { throw ProbeError.impostorTimeout }
        guard impostor.received.wait(timeout: .now() + 1) == .timedOut,
              impostor.payloadSnapshot().isEmpty else { throw ProbeError.rejectedPeer }
        print("PASS: TLS-PSK exchanged authorized data and rejected wrong-key, plaintext and impostor peers")
    }
}
