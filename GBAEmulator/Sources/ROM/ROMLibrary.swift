// ROMLibrary.swift
// Manages importing, storing and listing GBA ROMs

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

// MARK: - ROM Model

struct ROMEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var fileName: String
    var fileSize: Int64
    var importDate: Date
    var lastPlayedDate: Date?
    var artworkData: Data?
    var checksum: String // SHA256 of first 0x100 bytes for quick ID

    // Derived bookmark path stored separately (not Codable, resolved at runtime)
    var localPath: String // relative to documents/roms/

    var formattedSize: String {
        let mb = Double(fileSize) / 1_048_576.0
        return String(format: "%.2f MB", mb)
    }
}

// MARK: - ROM Library

@MainActor
final class ROMLibrary: ObservableObject {
    @Published var roms: [ROMEntry] = []
    @Published var isImporting = false
    @Published var importError: String?

    private let fileManager = FileManager.default
    private let romsDirectoryName = "ROMs"
    private let metadataFileName = "rom_library.json"

    var romsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(romsDirectoryName, isDirectory: true)
    }

    private var metadataURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(metadataFileName)
    }

    init() {
        ensureROMsDirectory()
        loadMetadata()
    }

    // MARK: - Directory Setup

    private func ensureROMsDirectory() {
        if !fileManager.fileExists(atPath: romsDirectory.path) {
            try? fileManager.createDirectory(at: romsDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Import ROM

    func importROM(from sourceURL: URL) async {
        isImporting = true
        importError = nil

        do {
            // Security-scoped resource access for Files app / iCloud
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { sourceURL.stopAccessingSecurityScopedResource() }
            }

            // Validate extension
            guard sourceURL.pathExtension.lowercased() == "gba" else {
                throw ROMImportError.invalidFormat("Only .gba files are supported")
            }

            let data = try Data(contentsOf: sourceURL)
            guard data.count >= 0xC0 else {
                throw ROMImportError.invalidFormat("File too small to be a valid GBA ROM")
            }

            // Validate GBA ROM header magic (Nintendo logo offset 0x4 is verified by hardware but
            // we check the entry point instruction at 0x00 – should be ARM branch or NOP)
            let entryPoint = data.subdata(in: 0..<4)
            let isARM = entryPoint[3] == 0xEA || entryPoint[3] == 0xE5 || entryPoint[1] == 0x00
            if !isARM {
                throw ROMImportError.invalidFormat("File does not appear to be a valid GBA ROM (invalid entry point)")
            }

            // Extract title from ROM header (offset 0xA0, 12 bytes, ASCII)
            let titleBytes = data.subdata(in: 0xA0..<0xAC)
            var romTitle = String(bytes: titleBytes, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespaces) ?? sourceURL.deletingPathExtension().lastPathComponent
            if romTitle.isEmpty { romTitle = sourceURL.deletingPathExtension().lastPathComponent }

            // Compute checksum
            let checksumData = data.subdata(in: 0..<min(0x100, data.count))
            let digest = SHA256.hash(data: checksumData)
            let checksum = digest.compactMap { String(format: "%02x", $0) }.joined()

            // Check for duplicate
            if roms.contains(where: { $0.checksum == checksum }) {
                throw ROMImportError.duplicate
            }

            // Copy to local storage
            let uniqueName = UUID().uuidString + ".gba"
            let destURL = romsDirectory.appendingPathComponent(uniqueName)
            try data.write(to: destURL)

            let entry = ROMEntry(
                id: UUID(),
                title: romTitle,
                fileName: uniqueName,
                fileSize: Int64(data.count),
                importDate: Date(),
                lastPlayedDate: nil,
                artworkData: nil,
                checksum: checksum,
                localPath: uniqueName
            )

            roms.append(entry)
            roms.sort { $0.title < $1.title }
            saveMetadata()

        } catch let error as ROMImportError {
            importError = error.localizedDescription
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }

        isImporting = false
    }

    // MARK: - Delete ROM

    func deleteROM(_ rom: ROMEntry) {
        let url = romsDirectory.appendingPathComponent(rom.localPath)
        try? fileManager.removeItem(at: url)

        // Also remove saves
        SaveManager.shared.deleteSaves(forROM: rom.id)

        roms.removeAll { $0.id == rom.id }
        saveMetadata()
    }

    // MARK: - URL resolution

    func fileURL(for rom: ROMEntry) -> URL {
        romsDirectory.appendingPathComponent(rom.localPath)
    }

    func romData(for rom: ROMEntry) throws -> Data {
        let url = fileURL(for: rom)
        return try Data(contentsOf: url)
    }

    // MARK: - Persistence

    private func saveMetadata() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(roms) {
            try? data.write(to: metadataURL)
        }
    }

    private func loadMetadata() {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: metadataURL),
           let decoded = try? decoder.decode([ROMEntry].self, from: data) {
            // Verify files still exist
            roms = decoded.filter { entry in
                fileManager.fileExists(atPath: romsDirectory.appendingPathComponent(entry.localPath).path)
            }
        }
    }
}

// MARK: - Errors

enum ROMImportError: LocalizedError {
    case invalidFormat(String)
    case duplicate
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "Invalid ROM: \(msg)"
        case .duplicate: return "This ROM is already in your library"
        case .fileTooLarge: return "File exceeds maximum size"
        }
    }
}
