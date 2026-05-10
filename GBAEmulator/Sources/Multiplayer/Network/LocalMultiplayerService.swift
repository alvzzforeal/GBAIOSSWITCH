// LocalMultiplayerService.swift
// Handles device discovery, session management, and packet transport
// using Apple's MultipeerConnectivity framework over Wi-Fi / Bluetooth.
//
// Architecture:
//   Host → advertises service type "gba-link"
//   Client → browses for "gba-link" service
//   Both → use MCSession for reliable + unreliable data transfer
//
// MultipeerConnectivity automatically uses Wi-Fi Direct, infrastructure Wi-Fi,
// and Bluetooth depending on availability. For lowest latency, both devices
// should be on the same Wi-Fi network.

import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Peer info

struct GBAPeer: Identifiable, Hashable {
    let id: MCPeerID
    var displayName: String { id.displayName }
}

// MARK: - Session State

enum MultiplayerState {
    case idle
    case advertising      // Host
    case browsing         // Client
    case connecting(GBAPeer)
    case connected
    case failed(String)
}

// MARK: - LocalMultiplayerService

@MainActor
final class LocalMultiplayerService: NSObject, ObservableObject {
    static let serviceType = "gba-link"  // Must be ≤15 chars, lowercase alphanumeric + hyphen

    @Published var state: MultiplayerState = .idle
    @Published var discoveredPeers: [GBAPeer] = []
    @Published var connectedPeers: [GBAPeer] = []
    @Published var sessionLog: [String] = []

    var isHost: Bool = false
    var localPlayerID: UInt8 = 0

    var onPacketReceived: ((LinkPacket) -> Void)?

    private let localPeer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        let deviceName = UIDevice.current.name
        self.localPeer = MCPeerID(displayName: deviceName)
        super.init()
        createSession()
    }

    private func createSession() {
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
    }

    // MARK: - Host

    func startHosting() {
        stopAll()
        isHost = true
        localPlayerID = 0

        let info = ["role": "host", "version": "1"]
        advertiser = MCNearbyServiceAdvertiser(peer: localPeer, discoveryInfo: info, serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        state = .advertising
        log("Hosting session as \(localPeer.displayName)")
    }

    // MARK: - Client / Join

    func startBrowsing() {
        stopAll()
        isHost = false

        browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        state = .browsing
        log("Browsing for GBA sessions...")
    }

    func connect(to peer: GBAPeer) {
        guard let browser = browser else { return }
        state = .connecting(peer)
        browser.invitePeer(peer.id, to: session, withContext: nil, timeout: 10)
        log("Connecting to \(peer.displayName)...")
    }

    // MARK: - Disconnect

    func disconnect() {
        sendPacket(to: nil, packet: .disconnect(playerID: localPlayerID), reliable: true)
        stopAll()
        state = .idle
        connectedPeers.removeAll()
        discoveredPeers.removeAll()
        log("Disconnected")
    }

    private func stopAll() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session.disconnect()
        // Recreate session for reuse
        createSession()
    }

    // MARK: - Send / Broadcast

    func broadcast(packet: LinkPacket) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        let data = packet.encoded()
        // Use unreliable for frame data (latency > reliability)
        let mode: MCSessionSendDataMode = packet.type == .frameSync || packet.type == .linkData
            ? .unreliable : .reliable
        try? session.send(data, toPeers: peers, with: mode)
    }

    func sendPacket(to peer: GBAPeer?, packet: LinkPacket, reliable: Bool = false) {
        let targets = peer.map { [$0.id] } ?? session.connectedPeers
        guard !targets.isEmpty else { return }
        let data = packet.encoded()
        try? session.send(data, toPeers: targets, with: reliable ? .reliable : .unreliable)
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        sessionLog.append("[\(ts)] \(msg)")
        if sessionLog.count > 100 { sessionLog.removeFirst() }
    }
}

// MARK: - MCSessionDelegate

extension LocalMultiplayerService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                let peer = GBAPeer(id: peerID)
                if !connectedPeers.contains(peer) {
                    connectedPeers.append(peer)
                }
                // Assign player IDs
                localPlayerID = isHost ? 0 : UInt8(connectedPeers.count)
                self.state = .connected
                log("\(peerID.displayName) connected")

                // Send handshake
                let hs = LinkPacket.handshake(
                    playerID: localPlayerID,
                    deviceName: localPeer.displayName,
                    maxPlayers: UInt8(connectedPeers.count + 1)
                )
                broadcast(packet: hs)

            case .notConnected:
                connectedPeers.removeAll { $0.id == peerID }
                log("\(peerID.displayName) disconnected")
                if connectedPeers.isEmpty { self.state = .idle }

            case .connecting:
                log("\(peerID.displayName) is connecting...")
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = LinkPacket.decode(from: data) else { return }
        Task { @MainActor in
            onPacketReceived?(packet)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension LocalMultiplayerService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            log("Received invitation from \(peerID.displayName) — auto-accepting")
            invitationHandler(true, session)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension LocalMultiplayerService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            let peer = GBAPeer(id: peerID)
            if !discoveredPeers.contains(peer) {
                discoveredPeers.append(peer)
                log("Found: \(peerID.displayName)")
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            discoveredPeers.removeAll { $0.id == peerID }
            log("Lost: \(peerID.displayName)")
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            state = .failed(error.localizedDescription)
            log("Browse failed: \(error.localizedDescription)")
        }
    }
}
