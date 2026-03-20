import Foundation
import Network

// MARK: - Protocol constants

public enum ScrollNetworkProtocol {
    public static let serviceType = "_scroll._tcp"   // Bonjour label only; transport is UDP
    public static let serviceName = "Scroll"
    public static let defaultPort: UInt16 = 50505
}

// MARK: - Shared UDP parameters

private extension NWParameters {
    static func scrollUDP() -> NWParameters {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true
        return params
    }
}

// MARK: - Mac UDP Listener

#if os(macOS)
import Observation

@MainActor
@Observable
public final class MacScrollNetworkListener {
    public private(set) var isListening   = false
    public private(set) var connectedClients: Set<String> = []

    public var onCommandReceived: ((ScrollCommand) -> Void)?
    public var onStateChanged:    (() -> Void)?

    private var listener:    NWListener?
    private var connections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.scroll.mac.network", qos: .userInteractive)
    
    // For cleanup in deinit
    nonisolated(unsafe) private var _listenerForCleanup: NWListener?
    nonisolated(unsafe) private var _connectionsForCleanup: [NWConnection] = []

    public init() {}

    public func startListening() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.scrollUDP()
            params.acceptLocalOnly = true

            let l = try NWListener(
                using: params,
                on: NWEndpoint.Port(integerLiteral: ScrollNetworkProtocol.defaultPort)
            )
            l.service = NWListener.Service(
                name: ScrollNetworkProtocol.serviceName,
                type: ScrollNetworkProtocol.serviceType
            )

            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.onStateChanged?()
                    case .failed:
                        self.isListening = false
                        self.onStateChanged?()
                        self.restartAfterDelay()
                    case .cancelled:
                        self.isListening = false
                        self.onStateChanged?()
                    default: break
                    }
                }
            }

            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor [weak self] in
                    self?.accept(conn)
                }
            }

            l.start(queue: queue)
            listener = l
            _listenerForCleanup = l
        } catch {
            print("MacScrollNetworkListener: failed to start – \(error)")
        }
    }

    private func restartAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            listener = nil
            _listenerForCleanup = nil
            startListening()
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = "\(conn.endpoint)"
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor [weak self] in
                    self?.connectedClients.insert(id)
                    self?.onStateChanged?()
                }
                self?.startReceiving(from: conn, id: id)
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.connectedClients.remove(id)
                    self?.connections.removeValue(forKey: id)
                    self?._connectionsForCleanup.removeAll { $0 === conn }
                    self?.onStateChanged?()
                }
            default: break
            }
        }
        conn.start(queue: queue)
        connections[id] = conn
        _connectionsForCleanup.append(conn)
    }

    // UDP: one call = one complete datagram
    nonisolated private func startReceiving(from conn: NWConnection, id: String) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let error {
                if case .posix(let code) = error, code == .ECANCELED { return }
                print("MacScrollNetworkListener: receive error – \(error)")
                return
            }
            if let data, !data.isEmpty {
                if let cmd = try? ScrollCommand(wireData: data) {
                    Task { @MainActor [weak self] in
                        self?.onCommandReceived?(cmd)
                    }
                }
            }
            // Re-arm receive
            self?.startReceiving(from: conn, id: id)
        }
    }

    public func stopListening() {
        listener?.cancel()
        listener = nil
        _listenerForCleanup = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        _connectionsForCleanup.removeAll()
        isListening = false
        connectedClients.removeAll()
        onStateChanged?()
    }

    deinit {
        _listenerForCleanup?.cancel()
        _connectionsForCleanup.forEach { $0.cancel() }
    }
}
#endif

// MARK: - iPhone UDP Client

#if canImport(UIKit)
import Observation

@MainActor
@Observable
public final class iPhoneScrollNetworkClient {
    public private(set) var isConnected:     Bool = false
    public private(set) var discoveredHosts: [NWBrowser.Result] = []
    public private(set) var currentHostName: String?

    private var connection: NWConnection?
    private var browser:    NWBrowser?
    private let queue = DispatchQueue(label: "com.scroll.iphone.network", qos: .userInteractive)

    public init() {}

    public func startDiscovery() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: ScrollNetworkProtocol.serviceType, domain: nil), using: params)

        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor [weak self] in self?.restartBrowser() }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.discoveredHosts = Array(results)
            }
        }
        b.start(queue: queue)
        browser = b
    }

    public func connectToHost(_ result: NWBrowser.Result) {
        disconnect()
        let conn = NWConnection(to: result.endpoint, using: .scrollUDP())
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.currentHostName = name
                    }
                case .failed, .cancelled:
                    self.isConnected = false
                    self.currentHostName = nil
                default: break
                }
            }
        }
        conn.start(queue: queue)
        connection = conn
    }

    // Fire-and-forget: UDP, no completion overhead on hot path
    public func sendCommand(_ command: ScrollCommand) {
        guard let conn = connection, conn.state == .ready else { return }
        let data = command.toWireData()
        conn.send(content: data, completion: .idempotent)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        currentHostName = nil
    }

    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        discoveredHosts.removeAll()
    }

    private func restartBrowser() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            browser = nil
            startDiscovery()
        }
    }

    @MainActor deinit {
        disconnect()
        stopDiscovery()
    }
}
#endif
