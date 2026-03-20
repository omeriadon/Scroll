import Foundation
import Network

// MARK: - Network Protocol Constants
public enum ScrollNetworkProtocol {
    public static let serviceType = "_scroll._tcp"
    public static let serviceName = "Scroll"
    public static let defaultPort: UInt16 = 50505
}

// MARK: - TCP Configuration Extension
extension NWParameters {
    static func lowLatencyTCP() -> NWParameters {
        let parameters = NWParameters.tcp

        // Optimize TCP for minimal latency
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 2
            tcpOptions.noDelay = true // TCP_NODELAY - disable Nagle's algorithm
        }

        return parameters
    }
}

// MARK: - Mac Network Listener
#if os(macOS)
import AppKit
import Observation

@Observable
public final class MacScrollNetworkListener {
    public private(set) var isListening = false
    public private(set) var connectedClients: Set<String> = []

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.scroll.mac.network", qos: .userInteractive)
    public var onCommandReceived: ((ScrollCommand) -> Void)?
    public var onStateChanged: (() -> Void)?

    public init() {}

    @MainActor
    public func startListening() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.lowLatencyTCP()
            parameters.allowLocalEndpointReuse = true
            parameters.acceptLocalOnly = true

            // Set up Bonjour service advertisement
            parameters.includePeerToPeer = true
            let service = NWListener.Service(name: ScrollNetworkProtocol.serviceName, type: ScrollNetworkProtocol.serviceType)

            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: ScrollNetworkProtocol.defaultPort))
            listener.service = service

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isListening = true
                        self?.onStateChanged?()
                        print("🖥️ Mac listener ready on port \(ScrollNetworkProtocol.defaultPort)")
                    case .failed(let error):
                        print("🖥️ Mac listener failed: \(error)")
                        self?.isListening = false
                        self?.onStateChanged?()
                        self?.restartListener()
                    case .cancelled:
                        self?.isListening = false
                        self?.onStateChanged?()
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener

        } catch {
            print("🖥️ Failed to create listener: \(error)")
        }
    }

    @MainActor
    private func restartListener() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            startListening()
        }
    }

    private nonisolated func handleNewConnection(_ connection: NWConnection) {
        let clientID = "\(connection.endpoint)"
        print("🖥️ New connection from: \(clientID)")

        Task { @MainActor in
            connectedClients.insert(clientID)
            onStateChanged?()
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("🖥️ Connection ready: \(clientID)")
                self?.receiveMessagesNonisolated(from: connection)
            case .failed(let error):
                print("🖥️ Connection failed: \(error)")
                Task { @MainActor [weak self] in
                    self?.connectedClients.remove(clientID)
                    self?.connections.removeAll { $0 === connection }
                    self?.onStateChanged?()
                }
            case .cancelled:
                Task { @MainActor [weak self] in
                    self?.connectedClients.remove(clientID)
                    self?.connections.removeAll { $0 === connection }
                    self?.onStateChanged?()
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
        Task { @MainActor [weak self] in
            self?.connections.append(connection)
        }
    }

    private nonisolated func receiveMessagesNonisolated(from connection: NWConnection) {
        // Read 4-byte length prefix first
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            print("🖥️ [RX] waiting header complete=\(isComplete)")
            if let error = error {
                print("🖥️ Receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data = data, data.count == 4 else {
                if !isComplete {
                    self?.receiveMessagesNonisolated(from: connection)
                }
                return
            }

            var messageLengthRaw: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &messageLengthRaw) { rawBuffer in
                data.copyBytes(to: rawBuffer, from: 0..<4)
            }
            let messageLength = UInt32(bigEndian: messageLengthRaw)
            print("🖥️ [RX] header length=\(messageLength)")

            guard messageLength > 0 else {
                if !isComplete {
                    self?.receiveMessagesNonisolated(from: connection)
                }
                return
            }

            self?.receiveExactPayloadNonisolated(
                from: connection,
                expectedLength: Int(messageLength),
                accumulated: Data()
            ) { [weak self] messageData, payloadComplete, payloadError in
                print("🖥️ [RX] payload callback complete=\(payloadComplete) err=\(String(describing: payloadError))")
                if let payloadError {
                    print("🖥️ Message receive error: \(payloadError)")
                    return
                }

                if let messageData {
                    print("🖥️ [RX] payload bytes=\(messageData.count)")
                    do {
                        let command = try ScrollCommand(binaryData: messageData)
                        Task { @MainActor [weak self] in
                            self?.onCommandReceived?(command)
                        }
                    } catch {
                        let versionByte = messageData.first.map(String.init) ?? "nil"
                        print(
                            "🖥️ Failed to decode command: \(error) " +
                            "(payload=\(messageData.count) bytes, versionByte=\(versionByte))"
                        )
                    }
                }

                if !payloadComplete {
                    self?.receiveMessagesNonisolated(from: connection)
                } else {
                    connection.cancel()
                }
            }
        }
    }

    private nonisolated func receiveExactPayloadNonisolated(
        from connection: NWConnection,
        expectedLength: Int,
        accumulated: Data,
        completion: @escaping (_ payload: Data?, _ isComplete: Bool, _ error: NWError?) -> Void
    ) {
        let remaining = expectedLength - accumulated.count
        print("🖥️ [RX] accumulate expected=\(expectedLength) current=\(accumulated.count) remaining=\(remaining)")
        guard remaining > 0 else {
            completion(accumulated, false, nil)
            return
        }

        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: remaining
        ) { [weak self] chunk, _, isComplete, error in
                if let error = error {
                    completion(nil, isComplete, error)
                    return
                }

                var updated = accumulated
                if let chunk, !chunk.isEmpty {
                    updated.append(chunk)
                    print("🖥️ [RX] chunk bytes=\(chunk.count) updated=\(updated.count)/\(expectedLength)")
                } else {
                    print("🖥️ [RX] chunk empty isComplete=\(isComplete)")
                }

                if updated.count >= expectedLength {
                    completion(Data(updated.prefix(expectedLength)), isComplete, nil)
                    return
                }

                guard !isComplete else {
                    completion(nil, isComplete, nil)
                    return
                }

                self?.receiveExactPayloadNonisolated(
                    from: connection,
                    expectedLength: expectedLength,
                    accumulated: updated,
                    completion: completion
                )
        }
    }

    @MainActor
    public func stopListening() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isListening = false
        connectedClients.removeAll()
        onStateChanged?()
    }

    nonisolated deinit {
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }
}
#endif

// MARK: - iPhone Network Client
#if canImport(UIKit)
import UIKit
import Observation

@MainActor
@Observable
public final class iPhoneScrollNetworkClient {
    public private(set) var isConnected = false
    public private(set) var discoveredHosts: [NWBrowser.Result] = []
    public private(set) var currentHostName: String?

    private var connection: NWConnection?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.scroll.iphone.network", qos: .userInteractive)
    private var sendQueue: DispatchQueue = DispatchQueue(label: "com.scroll.iphone.send", qos: .userInteractive)

    public init() {}

    public func startDiscovery() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: ScrollNetworkProtocol.serviceType, domain: nil), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("📱 Browser ready")
            case .failed(let error):
                print("📱 Browser failed: \(error)")
                Task { @MainActor [weak self] in
                    self?.restartBrowser()
                }
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.discoveredHosts = Array(results)
                print("📱 Discovered \(results.count) hosts")
            }
        }

        browser.start(queue: queue)
        self.browser = browser
    }

    private func restartBrowser() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            startDiscovery()
        }
    }

    public func connectToHost(_ result: NWBrowser.Result) {
        disconnect()

        let parameters = NWParameters.lowLatencyTCP()

        let connection = NWConnection(to: result.endpoint, using: parameters)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isConnected = true
                    if case .service(let name, _, _, _) = result.endpoint {
                        self?.currentHostName = name
                    }
                    print("📱 Connected to Mac")
                case .failed(let error):
                    print("📱 Connection failed: \(error)")
                    self?.isConnected = false
                    self?.currentHostName = nil
                case .cancelled:
                    self?.isConnected = false
                    self?.currentHostName = nil
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
        self.connection = connection
    }

    public func sendCommand(_ command: ScrollCommand) {
        guard let connection = connection, connection.state == .ready else {
            print("📱 [TX] skip send: no ready connection")
            return
        }

        sendQueue.async { [weak connection] in
            let commandData = command.toBinaryData()

            // Combine length prefix and data into single buffer for single send
            var length = UInt32(commandData.count).bigEndian
            var combinedData = Data(capacity: 4 + commandData.count)
            combinedData.append(Data(bytes: &length, count: 4))
            combinedData.append(commandData)
            print("📱 [TX] frame payload=\(commandData.count) total=\(combinedData.count)")

            // Single send operation for minimal latency
            connection?.send(content: combinedData, completion: .contentProcessed { error in
                if let error = error {
                    print("📱 Failed to send command: \(error)")
                } else {
                    print("📱 [TX] send success payload=\(commandData.count)")
                }
            })
        }
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

    @MainActor deinit {
        disconnect()
        stopDiscovery()
    }
}
#endif
