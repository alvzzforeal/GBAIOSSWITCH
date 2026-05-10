// LinkCableManager.swift
// Adapts network packets from LocalMultiplayerService to the emulator core's
// link cable interface. This is the "glue" between networking and emulation.
//
// GBA Link Cable Technical Context:
//   The GBA uses a SIO (Serial I/O) system with a hardware shift register.
//   In Normal Mode 32-bit: master clocks the transfer, all slaves shift simultaneously.
//   In Multiplayer Mode: 4 players, master sends clock, data aggregated by hardware.
//
//   We emulate this by:
//   - Collecting each player's 32-bit SIO data word at frame boundaries
//   - Master aggregates and broadcasts the combined result
//   - Each client updates its emulator's SIO received register
//
//   IMPORTANT: mGBA has internal network link support (LinkRaw) but it's designed
//   for local socket/pipe connections. For iOS we replicate the protocol over
//   MultipeerConnectivity. See LocalMultiplayerService.swift for transport.

import Foundation
import Combine

// MARK: - Link Cable Manager

@MainActor
final class LinkCableManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectedPlayers: Int = 0
    @Published var playerID: UInt8 = 0
    @Published var isHost: Bool = false

    private var networkService: LocalMultiplayerService?
    private var emulatorCore: EmulatorCore?

    // Per-frame state accumulation
    private var currentFrame: UInt32 = 0
    private var pendingPlayerData: [UInt8: UInt32] = [:] // playerID -> SIO data
    private var frameCancellable: AnyCancellable?

    // Callback for when the emulator should receive SIO data
    var onSIOReceive: ((UInt32) -> Void)?

    // MARK: - Setup

    func attach(to network: LocalMultiplayerService, core: EmulatorCore) {
        self.networkService = network
        self.emulatorCore = core

        networkService?.onPacketReceived = { [weak self] packet in
            Task { @MainActor in
                self?.handlePacket(packet)
            }
        }

        isHost = network.isHost
        playerID = network.localPlayerID
        isConnected = true
    }

    func detach() {
        networkService?.onPacketReceived = nil
        networkService = nil
        isConnected = false
        pendingPlayerData.removeAll()
    }

    // MARK: - Per-Frame API (called by emulator frame loop)

    /// Called each frame by the emulator. Sends our SIO data and collects responses.
    /// - Parameter sioData: The 32-bit value the local GBA core wants to send over link cable
    /// - Returns: The received value (from master's aggregated response), or 0xFFFFFFFF if not ready
    func exchangeSIOData(_ sioData: UInt32) -> UInt32 {
        currentFrame &+= 1

        guard let service = networkService, isConnected else {
            return 0xFFFFFFFF // No link connection
        }

        // Send our data to peers
        let packet = LinkPacket.linkData(
            playerID: playerID,
            frame: currentFrame,
            sioData: sioData
        )
        service.broadcast(packet: packet)

        // If we're host, aggregate and broadcast result
        if isHost {
            pendingPlayerData[playerID] = sioData

            // Check if we have all players' data
            if pendingPlayerData.count >= connectedPlayers {
                let result = aggregateSIOData()
                broadcastFrameSync(result)
                pendingPlayerData.removeAll()
                return result[playerID] ?? 0xFFFFFFFF
            }
        }

        // Return last known received data (client waits for master's broadcast)
        return lastReceivedSIO
    }

    private var lastReceivedSIO: UInt32 = 0xFFFFFFFF

    // MARK: - Packet Handling

    private func handlePacket(_ packet: LinkPacket) {
        guard packet.isValid else {
            print("[LinkCableManager] Corrupt packet from player \(packet.playerID)")
            return
        }

        switch packet.type {
        case .linkData:
            handleLinkDataPacket(packet)
        case .frameSync:
            handleFrameSyncPacket(packet)
        case .keyState:
            handleKeyStatePacket(packet)
        case .handshake:
            handleHandshakePacket(packet)
        case .disconnect:
            handleDisconnect(packet)
        case .ack:
            break
        }
    }

    private func handleLinkDataPacket(_ packet: LinkPacket) {
        guard isHost else { return } // Only host aggregates
        guard let payload = try? JSONDecoder().decode(LinkDataPayload.self, from: packet.payload) else { return }
        pendingPlayerData[packet.playerID] = payload.sioData
    }

    private func handleFrameSyncPacket(_ packet: LinkPacket) {
        guard !isHost else { return } // Clients receive frame sync from host
        guard let payload = try? JSONDecoder().decode(FrameSyncPayload.self, from: packet.payload) else { return }

        if let myData = payload.playerData[playerID] {
            lastReceivedSIO = myData
            onSIOReceive?(myData)
        }
    }

    private func handleKeyStatePacket(_ packet: LinkPacket) {
        // For games using key synchronization instead of link cable
        guard let payload = try? JSONDecoder().decode(KeyStatePayload.self, from: packet.payload) else { return }
        _ = payload.keyMask // Route to emulator input if needed
    }

    private func handleHandshakePacket(_ packet: LinkPacket) {
        guard let payload = try? JSONDecoder().decode(HandshakePayload.self, from: packet.payload) else { return }
        connectedPlayers = Int(payload.maxPlayers)
        print("[LinkCableManager] Player \(payload.playerID) (\(payload.deviceName)) joined. Players: \(connectedPlayers)")
    }

    private func handleDisconnect(_ packet: LinkPacket) {
        print("[LinkCableManager] Player \(packet.playerID) disconnected")
        pendingPlayerData.removeValue(forKey: packet.playerID)
        connectedPlayers = max(1, connectedPlayers - 1)
    }

    // MARK: - Host Aggregation

    /// In GBA Multiplayer Mode, master broadcasts collected words.
    /// Word layout: [Player0 data][Player1 data][Player2 data][Player3 data]
    /// For 2-player games, only lower 16 bits of each word matter.
    private func aggregateSIOData() -> [UInt8: UInt32] {
        // Each player gets back the OTHER players' data (their own is echoed by hardware)
        var result: [UInt8: UInt32] = [:]
        for (pid, _) in pendingPlayerData {
            // Simplified: give each player the master's aggregated word
            // In real GBA multiplayer mode, the specific layout depends on the game's protocol
            var aggregated: UInt32 = 0
            for (opid, data) in pendingPlayerData where opid != pid {
                aggregated ^= data // XOR merge (simplification; real protocol varies)
            }
            result[pid] = aggregated
        }
        return result
    }

    private func broadcastFrameSync(_ result: [UInt8: UInt32]) {
        guard let service = networkService else { return }
        let payload = FrameSyncPayload(masterFrame: currentFrame, playerData: result)
        guard let payloadData = try? JSONEncoder().encode(payload) else { return }
        let packet = LinkPacket(type: .frameSync, playerID: playerID, frameNumber: currentFrame, payload: payloadData)
        service.broadcast(packet: packet)
    }
}
