// SaveManager.swift
// Handles persistence of save states and battery saves (SRAM/EEPROM/Flash).

import Foundation

final class SaveManager {
    static let shared = SaveManager()
    private init() { ensureDirectories() }

    private let fileManager = FileManager.default

    // MARK: - Directories

    private var savesRoot: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Saves", isDirectory: true)
    }

    private func stateDir(romID: UUID) -> URL {
        savesRoot.appendingPathComponent(romID.uuidString, isDirectory: true)
    }

    private func batteryDir(romID: UUID) -> URL {
        savesRoot.appendingPathComponent(romID.uuidString, isDirectory: true)
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: savesRoot, withIntermediateDirectories: true)
    }

    private func ensureROMDir(romID: UUID) {
        try? fileManager.createDirectory(at: stateDir(romID: romID), withIntermediateDirectories: true)
    }

    // MARK: - Save States

    /// slot == -1 means auto-save slot
    func saveState(data: Data, romID: UUID, slot: Int) {
        ensureROMDir(romID: romID)
        let fileName = slot == -1 ? "auto.state" : "slot\(slot).state"
        let url = stateDir(romID: romID).appendingPathComponent(fileName)
        try? data.write(to: url, options: .atomic)

        // Write metadata
        let meta = SaveStateMetadata(slot: slot, date: Date(), size: data.count)
        let metaURL = url.deletingPathExtension().appendingPathExtension("json")
        if let metaData = try? JSONEncoder().encode(meta) {
            try? metaData.write(to: metaURL, options: .atomic)
        }
    }

    func loadState(romID: UUID, slot: Int) -> Data? {
        let fileName = slot == -1 ? "auto.state" : "slot\(slot).state"
        let url = stateDir(romID: romID).appendingPathComponent(fileName)
        return try? Data(contentsOf: url)
    }

    func stateExists(romID: UUID, slot: Int) -> Bool {
        let fileName = slot == -1 ? "auto.state" : "slot\(slot).state"
        let url = stateDir(romID: romID).appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path)
    }

    func stateMetadata(romID: UUID, slot: Int) -> SaveStateMetadata? {
        let fileName = slot == -1 ? "auto.json" : "slot\(slot).json"
        let url = stateDir(romID: romID).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SaveStateMetadata.self, from: data)
    }

    // MARK: - Battery Saves

    func saveBatterySave(data: Data, romID: UUID) {
        ensureROMDir(romID: romID)
        let url = batteryDir(romID: romID).appendingPathComponent("battery.sav")
        try? data.write(to: url, options: .atomic)
    }

    func loadBatterySave(romID: UUID) -> Data? {
        let url = batteryDir(romID: romID).appendingPathComponent("battery.sav")
        return try? Data(contentsOf: url)
    }

    // MARK: - Deletion

    func deleteSaves(forROM romID: UUID) {
        let dir = stateDir(romID: romID)
        try? fileManager.removeItem(at: dir)
    }

    // MARK: - List all slots for a ROM (0-9)

    func availableSlots(romID: UUID) -> [SaveSlotInfo] {
        return (-1...9).compactMap { slot in
            let meta = stateMetadata(romID: romID, slot: slot)
            let exists = stateExists(romID: romID, slot: slot)
            return exists ? SaveSlotInfo(slot: slot, metadata: meta) : nil
        }
    }
}

// MARK: - Models

struct SaveStateMetadata: Codable {
    let slot: Int
    let date: Date
    let size: Int

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var slotLabel: String {
        slot == -1 ? "Auto Save" : "Slot \(slot)"
    }
}

struct SaveSlotInfo: Identifiable {
    var id: Int { slot }
    let slot: Int
    let metadata: SaveStateMetadata?

    var label: String { slot == -1 ? "Auto Save" : "Slot \(slot)" }
}
