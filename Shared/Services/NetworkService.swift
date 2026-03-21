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
import AppKit

/// Represents a connected iPhone with its pairing status
public struct ConnectedClient: Sendable, Hashable {
    public let connectionID: String
    public let deviceInfo: DeviceInfo?
    public let isPaired: Bool
    
    public init(connectionID: String, deviceInfo: DeviceInfo? = nil, isPaired: Bool = false) {
        self.connectionID = connectionID
        self.deviceInfo = deviceInfo
        self.isPaired = isPaired
    }
}

@MainActor
@Observable
public final class MacScrollNetworkListener {
    public private(set) var isListening = false
    /// Connected clients keyed by device UUID (for paired) or connection ID (for unpaired)
    public private(set) var connectedClients: [String: ConnectedClient] = [:]
    
    /// Called for incoming pairing requests (first-time devices)
    public var onPairingRequest: ((DeviceInfo, @escaping (Bool) -> Void) -> Void)?
    public var onCommandReceived: ((ScrollCommand) -> Void)?
    public var onStateChanged: (() -> Void)?

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    /// Maps device UUID to connection ID for paired devices
    private var deviceToConnection: [UUID: String] = [:]
    private let queue = DispatchQueue(label: "com.scroll.mac.network", qos: .userInteractive)
    
    // For cleanup in deinit - suppress warnings since we only mutate from main actor
    @ObservationIgnored private var _listenerForCleanup: NWListener?
    @ObservationIgnored private var _connectionsForCleanup: [NWConnection] = []

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
                // Don't add to connectedClients yet - wait for pairing message
                self?.startReceiving(from: conn, id: id)
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Find and remove client by connection ID
                    for (key, client) in self.connectedClients where client.connectionID == id {
                        self.connectedClients.removeValue(forKey: key)
                        if let deviceInfo = client.deviceInfo {
                            self.deviceToConnection.removeValue(forKey: deviceInfo.id)
                        }
                    }
                    self.connections.removeValue(forKey: id)
                    self._connectionsForCleanup.removeAll { $0 === conn }
                    self.onStateChanged?()
                }
            default: break
            }
        }
        conn.start(queue: queue)
        connections[id] = conn
        _connectionsForCleanup.append(conn)
    }
    
    /// Send a pairing response to a specific connection
    public func sendPairingResponse(to connectionID: String, approved: Bool) {
        guard let conn = connections[connectionID] else { return }
        let myInfo = DeviceIdentity.currentDeviceInfo()
        let response = PairingMessage(
            messageType: approved ? .approved : .rejected,
            deviceID: myInfo.id,
            deviceName: myInfo.name
        )
        conn.send(content: response.toWireData(), completion: .idempotent)
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
                // Check if it's a pairing message or scroll command
                if PairingMessage.isPairingMessage(data) {
                    if let pairing = PairingMessage(wireData: data) {
                        Task { @MainActor [weak self] in
                            self?.handlePairingMessage(pairing, from: id)
                        }
                    }
                } else if let cmd = try? ScrollCommand(wireData: data) {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        // Check if this connection belongs to a paired device
                        let isPaired = self.connectedClients.values.contains { 
                            $0.connectionID == id && $0.isPaired 
                        }
                        if isPaired {
                            // Update last seen timestamp for scroll activity
                            for (_, client) in self.connectedClients where client.connectionID == id {
                                if let deviceID = client.deviceInfo?.id {
                                    var devices = Defaults[.approvedDevices]
                                    if let idx = devices.firstIndex(where: { $0.id == deviceID }) {
                                        devices[idx].lastSeen = Date()
                                        Defaults[.approvedDevices] = devices
                                    }
                                }
                                break
                            }
                            self.onCommandReceived?(cmd)
                        }
                    }
                }
            }
            // Re-arm receive
            self?.startReceiving(from: conn, id: id)
        }
    }
    
    private func handlePairingMessage(_ message: PairingMessage, from connectionID: String) {
        let deviceInfo = DeviceInfo(id: message.deviceID, name: message.deviceName)
        let deviceKey = deviceInfo.id.uuidString  // Use UUID as key for deduplication
        
        // Handle unpair message from iPhone
        if message.messageType == .unpaired {
            var devices = Defaults[.approvedDevices]
            devices.removeAll { $0.id == deviceInfo.id }
            Defaults[.approvedDevices] = devices
            connectedClients.removeValue(forKey: deviceKey)
            deviceToConnection.removeValue(forKey: deviceInfo.id)
            connections[connectionID]?.cancel()
            connections.removeValue(forKey: connectionID)
            onStateChanged?()
            return
        }
        
        guard message.messageType == .request else { return }
        
        // Remove any existing connection for this device (reconnection case)
        if let oldConnectionID = deviceToConnection[deviceInfo.id], oldConnectionID != connectionID {
            connections[oldConnectionID]?.cancel()
            connections.removeValue(forKey: oldConnectionID)
        }
        
        // Check if device is already approved
        let approvedDevices = Defaults[.approvedDevices]
        if approvedDevices.contains(where: { $0.id == deviceInfo.id }) {
            // Auto-approve and update last seen
            var updated = approvedDevices
            if let idx = updated.firstIndex(where: { $0.id == deviceInfo.id }) {
                updated[idx].lastSeen = Date()
                updated[idx].name = deviceInfo.name
            }
            Defaults[.approvedDevices] = updated
            
            // Key by device UUID, not connection ID
            connectedClients[deviceKey] = ConnectedClient(
                connectionID: connectionID,
                deviceInfo: deviceInfo,
                isPaired: true
            )
            deviceToConnection[deviceInfo.id] = connectionID
            sendPairingResponse(to: connectionID, approved: true)
            onStateChanged?()
        } else {
            // Ask for approval
            onPairingRequest?(deviceInfo) { [weak self] approved in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if approved {
                        var devices = Defaults[.approvedDevices]
                        devices.append(deviceInfo)
                        Defaults[.approvedDevices] = devices
                        
                        self.connectedClients[deviceKey] = ConnectedClient(
                            connectionID: connectionID,
                            deviceInfo: deviceInfo,
                            isPaired: true
                        )
                        self.deviceToConnection[deviceInfo.id] = connectionID
                    }
                    self.sendPairingResponse(to: connectionID, approved: approved)
                    self.onStateChanged?()
                }
            }
        }
    }

    public func stopListening() {
        listener?.cancel()
        listener = nil
        _listenerForCleanup = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        _connectionsForCleanup.removeAll()
        deviceToConnection.removeAll()
        isListening = false
        connectedClients.removeAll()
        onStateChanged?()
    }
    
    /// Remove a device from the approved list and notify it
    public func unpairDevice(_ deviceID: UUID) {
        var devices = Defaults[.approvedDevices]
        devices.removeAll { $0.id == deviceID }
        Defaults[.approvedDevices] = devices
        
        let deviceKey = deviceID.uuidString
        
        // Find the connection for this device
        if let connectionID = deviceToConnection[deviceID],
           let conn = connections[connectionID] {
            // Send unpair notification before disconnecting
            let myInfo = DeviceIdentity.currentDeviceInfo()
            let unpairMsg = PairingMessage(messageType: .unpaired, deviceID: myInfo.id, deviceName: myInfo.name)
            conn.send(content: unpairMsg.toWireData(), completion: .idempotent)
            
            // Small delay to let message send, then disconnect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                conn.cancel()
                self?.connections.removeValue(forKey: connectionID)
                self?.connectedClients.removeValue(forKey: deviceKey)
                self?.deviceToConnection.removeValue(forKey: deviceID)
                self?.onStateChanged?()
            }
        } else {
            // Device not currently connected, just remove from tracking
            connectedClients.removeValue(forKey: deviceKey)
            deviceToConnection.removeValue(forKey: deviceID)
            onStateChanged?()
        }
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
import UIKit

/// Represents a discovered Mac with its identity
public struct DiscoveredMac: Sendable, Hashable, Identifiable {
    public let browseResult: NWBrowser.Result
    public var deviceInfo: DeviceInfo?
    public var pairingState: PairingState
    
    public var id: String {
        if case .service(let name, _, _, _) = browseResult.endpoint {
            return name
        }
        return "\(browseResult.endpoint)"
    }
    
    public var displayName: String {
        deviceInfo?.name ?? id
    }
    
    public enum PairingState: Sendable {
        case unknown
        case pending
        case approved
        case rejected
    }
    
    public init(browseResult: NWBrowser.Result, deviceInfo: DeviceInfo? = nil, pairingState: PairingState = .unknown) {
        self.browseResult = browseResult
        self.deviceInfo = deviceInfo
        self.pairingState = pairingState
    }
}

@MainActor
@Observable
public final class iPhoneScrollNetworkClient {
    public private(set) var isConnected: Bool = false
    public private(set) var isPaired: Bool = false
    public private(set) var discoveredHosts: [DiscoveredMac] = []
    public private(set) var currentMac: DiscoveredMac?
    public private(set) var pairingState: DiscoveredMac.PairingState = .unknown
    
    /// Called when pairing response is received
    public var onPairingComplete: ((Bool, DeviceInfo?) -> Void)?
    /// Called when Mac unpairs this device
    public var onUnpaired: ((DeviceInfo) -> Void)?

    private var connection: NWConnection?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.scroll.iphone.network", qos: .userInteractive)
    private var pendingPairingRequest = false
    private var hasAttemptedAutoConnect = false

    public init() {}
    
    public var currentHostName: String? {
        currentMac?.displayName
    }

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
                guard let self else { return }
                // Preserve existing device info for known hosts
                self.discoveredHosts = results.map { result in
                    if let existing = self.discoveredHosts.first(where: { $0.browseResult == result }) {
                        return existing
                    }
                    
                    // Check if this is our last connected Mac
                    var mac = DiscoveredMac(browseResult: result)
                    if let lastMac = Defaults[.lastConnectedMac] {
                        // We'll match by name for now since we don't have MAC's ID yet
                        if case .service(let name, _, _, _) = result.endpoint,
                           name == lastMac.name || lastMac.name.contains(name) {
                            mac.deviceInfo = lastMac
                        }
                    }
                    return mac
                }
                
                // Auto-connect to last Mac if enabled
                self.attemptAutoConnect()
            }
        }
        b.start(queue: queue)
        browser = b
    }
    
    private func attemptAutoConnect() {
        guard Defaults[.autoConnectEnabled],
              !isConnected,
              !hasAttemptedAutoConnect,
              let lastMac = Defaults[.lastConnectedMac] else { return }
        
        hasAttemptedAutoConnect = true
        
        // Find the last connected Mac in discovered hosts
        // Try matching by UUID first, then by name
        if let mac = discoveredHosts.first(where: { $0.deviceInfo?.id == lastMac.id }) {
            connectToHost(mac.browseResult)
        } else if let mac = discoveredHosts.first(where: { host in
            // Match by service name containing Mac name
            if case .service(let name, _, _, _) = host.browseResult.endpoint {
                return name == lastMac.name || lastMac.name.contains(name) || name.contains(lastMac.name)
            }
            return false
        }) {
            connectToHost(mac.browseResult)
        }
    }
    
    /// Trigger auto-connect check (call from onAppear)
    public func checkAutoConnect() {
        // Reset flag so auto-connect can happen when results come in
        hasAttemptedAutoConnect = false
        // Also try immediately in case hosts are already discovered
        attemptAutoConnect()
    }

    public func connectToHost(_ result: NWBrowser.Result) {
        disconnect()
        
        // Find or create DiscoveredMac
        let mac = discoveredHosts.first(where: { $0.browseResult == result })
            ?? DiscoveredMac(browseResult: result)
        
        let conn = NWConnection(to: result.endpoint, using: .scrollUDP())
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.currentMac = mac
                    self.pairingState = .pending
                    // Start receiving for pairing response
                    self.startReceiving(from: conn)
                    // Send pairing request
                    self.sendPairingRequest()
                case .failed, .cancelled:
                    self.isConnected = false
                    self.isPaired = false
                    self.currentMac = nil
                    self.pairingState = .unknown
                default: break
                }
            }
        }
        conn.start(queue: queue)
        connection = conn
    }
    
    private func sendPairingRequest() {
        guard let conn = connection, conn.state == .ready else { return }
        let myInfo = DeviceIdentity.currentDeviceInfo()
        let request = PairingMessage(messageType: .request, deviceID: myInfo.id, deviceName: myInfo.name)
        conn.send(content: request.toWireData(), completion: .idempotent)
        pendingPairingRequest = true
    }
    
    nonisolated private func startReceiving(from conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let error {
                if case .posix(let code) = error, code == .ECANCELED { return }
                return
            }
            if let data, !data.isEmpty {
                if PairingMessage.isPairingMessage(data),
                   let pairing = PairingMessage(wireData: data) {
                    Task { @MainActor [weak self] in
                        self?.handlePairingResponse(pairing)
                    }
                }
            }
            // Re-arm receive
            self?.startReceiving(from: conn)
        }
    }
    
    private func handlePairingResponse(_ message: PairingMessage) {
        let macInfo = DeviceInfo(id: message.deviceID, name: message.deviceName)
        
        // Handle unpair notification from Mac
        if message.messageType == .unpaired {
            isPaired = false
            pairingState = .unknown
            // Clear stored Mac if it matches
            if Defaults[.lastConnectedMac]?.id == macInfo.id {
                Defaults[.lastConnectedMac] = nil
            }
            disconnect()
            onUnpaired?(macInfo)
            return
        }
        
        guard pendingPairingRequest else { return }
        pendingPairingRequest = false
        
        switch message.messageType {
        case .approved:
            isPaired = true
            pairingState = .approved
            
            // Update current mac with device info
            if var mac = currentMac {
                mac.deviceInfo = macInfo
                mac.pairingState = .approved
                currentMac = mac
            }
            
            // Remember this Mac for auto-connect
            Defaults[.lastConnectedMac] = macInfo
            
            onPairingComplete?(true, macInfo)
            
        case .rejected:
            isPaired = false
            pairingState = .rejected
            if var mac = currentMac {
                mac.pairingState = .rejected
                currentMac = mac
            }
            onPairingComplete?(false, macInfo)
            
        default:
            break
        }
    }

    // Fire-and-forget: UDP, no completion overhead on hot path
    public func sendCommand(_ command: ScrollCommand) {
        guard isPaired, let conn = connection, conn.state == .ready else { return }
        let data = command.toWireData()
        conn.send(content: data, completion: .idempotent)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        isPaired = false
        pairingState = .unknown
        currentMac = nil
        pendingPairingRequest = false
    }
    
    /// Forget the last connected Mac and notify it
    public func forgetLastMac() {
        // Send unpair notification if connected
        if let conn = connection, conn.state == .ready, currentMac?.deviceInfo != nil {
            let myInfo = DeviceIdentity.currentDeviceInfo()
            let unpairMsg = PairingMessage(messageType: .unpaired, deviceID: myInfo.id, deviceName: myInfo.name)
            conn.send(content: unpairMsg.toWireData(), completion: .idempotent)
        }
        
        Defaults[.lastConnectedMac] = nil
        disconnect()
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
