// LinkPacket.swift
// Network packet structures for GBA link cable emulation over Wi-Fi.
//
// The GBA link cable protocol:
//   - Serial peripheral interface (SPI) at 256Kbps or 2Mbps
//   - Master sends 32-bit word, each slave responds with 32-bit word simultaneously
//   - Used for: Pokémon trading, multiplayer games (Mario Kart, etc.)
//
// Over Wi-Fi we approximate this by:
//   1. Designating one device as Master (Host)
//   2. Each frame, Master sends its data word + frame number
//   3. Clients respond with their data word
//   4. Master broadcasts the aggregated response back to all clients
//   5. Emulator core's "link" register is updated with received data
//
// Latency trade-off: ~16ms frame boundary sync introduces 1 frame delay.
// This is acceptable for most GBA multiplayer games except latency-critical ones.

import Foundation

// MARK: - Packet Types

enum LinkPacketType: UInt8, Codable {
    case handshake = 0x01   // Initial connection
    case frameSync = 0x02   // Per-frame sync data
    case keyState  = 0x03   // Button state broadcast (for non-link games)
    case linkData  = 0x04   // Raw link cable SIO data (32-bit word)
    case ack       = 0x05   // Acknowledgement
    case disconnect = 0x06  // Clean disconnect
}

// MARK: - Link Packet

struct LinkPacket: Codable {
    let type: LinkPacketType
    let playerID: UInt8          // 0 = Master/Host, 1-3 = Clients
    let frameNumber: UInt32      // Emulator frame counter
    let timestamp: Double        // Date.timeIntervalSinceReferenceDate
    let payload: Data            // Variable payload depending on type
    let checksum: UInt16         // Simple XOR checksum over payload

    init(type: LinkPacketType, playerID: UInt8, frameNumber: UInt32, payload: Data) {
        self.type = type
        self.playerID = playerID
        self.frameNumber = frameNumber
        self.timestamp = Date.timeIntervalSinceReferenceDate
        self.payload = payload
        self.checksum = LinkPacket.computeChecksum(payload)
    }

    var isValid: Bool {
        return checksum == LinkPacket.computeChecksum(payload)
    }

    static func computeChecksum(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    // MARK: - Serialization

    func encoded() -> Data {
        return (try? JSONEncoder().encode(self)) ?? Data()
    }

    static func decode(from data: Data) -> LinkPacket? {
        return try? JSONDecoder().decode(LinkPacket.self, from: data)
    }
}

// MARK: - Payload Types

/// Payload for .linkData packets: the 32-bit SIO transfer value
struct LinkDataPayload: Codable {
    let sioData: UInt32      // The 32-bit value being transferred over link cable
    let sioControl: UInt16   // SIO control register value (mode flags)
}

/// Payload for .frameSync packets
struct FrameSyncPayload: Codable {
    let masterFrame: UInt32
    /// Collected SIO data from all players, indexed by playerID
    let playerData: [UInt8: UInt32]
}

/// Payload for .keyState packets (for synchronized button state)
struct KeyStatePayload: Codable {
    let keyMask: UInt16      // GBA key register value (active-low bitmask)
}

/// Payload for .handshake packets
struct HandshakePayload: Codable {
    let version: UInt8       // Protocol version
    let playerID: UInt8      // Assigned player ID
    let deviceName: String
    let maxPlayers: UInt8
}

// MARK: - Convenience builders

extension LinkPacket {
    static func handshake(playerID: UInt8, deviceName: String, maxPlayers: UInt8 = 4) -> LinkPacket {
        let p = HandshakePayload(version: 1, playerID: playerID, deviceName: deviceName, maxPlayers: maxPlayers)
        let data = (try? JSONEncoder().encode(p)) ?? Data()
        return LinkPacket(type: .handshake, playerID: playerID, frameNumber: 0, payload: data)
    }

    static func linkData(playerID: UInt8, frame: UInt32, sioData: UInt32, control: UInt16 = 0) -> LinkPacket {
        let p = LinkDataPayload(sioData: sioData, sioControl: control)
        let data = (try? JSONEncoder().encode(p)) ?? Data()
        return LinkPacket(type: .linkData, playerID: playerID, frameNumber: frame, payload: data)
    }

    static func keyState(playerID: UInt8, frame: UInt32, keys: UInt16) -> LinkPacket {
        let p = KeyStatePayload(keyMask: keys)
        let data = (try? JSONEncoder().encode(p)) ?? Data()
        return LinkPacket(type: .keyState, playerID: playerID, frameNumber: frame, payload: data)
    }

    static func disconnect(playerID: UInt8) -> LinkPacket {
        return LinkPacket(type: .disconnect, playerID: playerID, frameNumber: 0, payload: Data())
    }
}
