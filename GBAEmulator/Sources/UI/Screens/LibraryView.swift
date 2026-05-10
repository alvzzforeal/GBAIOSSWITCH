// LibraryView.swift
// Main game library screen with ROM import.

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var romLibrary: ROMLibrary
    @EnvironmentObject var emulatorState: EmulatorState
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var showDocumentPicker = false
    @State private var showSettings = false
    @State private var showMultiplayer = false
    @State private var romToDelete: ROMEntry?
    @State private var searchText = ""

    var filteredROMs: [ROMEntry] {
        if searchText.isEmpty { return romLibrary.roms }
        return romLibrary.roms.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    libraryHeader

                    if romLibrary.roms.isEmpty {
                        emptyState
                    } else {
                        romGrid
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView(allowedTypes: [.init(filenameExtension: "gba")!]) { url in
                    Task { await romLibrary.importROM(from: url) }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showMultiplayer) {
                MultiplayerView()
            }
            .alert("Import Error", isPresented: .constant(romLibrary.importError != nil)) {
                Button("OK") { romLibrary.importError = nil }
            } message: {
                Text(romLibrary.importError ?? "")
            }
            .confirmationDialog("Delete ROM?", isPresented: .constant(romToDelete != nil), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let rom = romToDelete {
                        romLibrary.deleteROM(rom)
                        romToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { romToDelete = nil }
            } message: {
                Text("This will also delete all saves for \(romToDelete?.title ?? "this game").")
            }
        }
    }

    // MARK: - Header

    private var libraryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GBA")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("LIBRARY")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                    .tracking(4)
            }
            Spacer()
            HStack(spacing: 16) {
                Button {
                    showMultiplayer = true
                } label: {
                    Image(systemName: "wifi.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                }
                Button {
                    showDocumentPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("Import")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.6, green: 0.4, blue: 1.0))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }

    // MARK: - ROM Grid

    private var romGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach(filteredROMs) { rom in
                    ROMCardView(rom: rom)
                        .onTapGesture { launchROM(rom) }
                        .contextMenu {
                            Button("Play", systemImage: "play.fill") { launchROM(rom) }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { romToDelete = rom }
                        }
                }
            }
            .padding(16)
            .searchable(text: $searchText, prompt: "Search games...")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(red: 0.15, green: 0.1, blue: 0.2))
                    .frame(width: 120, height: 120)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            }
            VStack(spacing: 8) {
                Text("No Games Yet")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Tap Import to add your GBA ROM files.\nOnly use ROMs you own legally.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showDocumentPicker = true
            } label: {
                Label("Import ROM", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.6, green: 0.4, blue: 1.0))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Launch

    private func launchROM(_ rom: ROMEntry) {
        Task {
            await emulatorState.loadAndStart(rom: rom, library: romLibrary)
        }
    }
}

// MARK: - ROM Card

struct ROMCardView: View {
    let rom: ROMEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Artwork / placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [artColor(rom.title).opacity(0.8), artColor(rom.title).opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1.5, contentMode: .fill)

                VStack {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.6))
                    Text(String(rom.title.prefix(2)).uppercased())
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(rom.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(rom.formattedSize)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func artColor(_ title: String) -> Color {
        let colors: [Color] = [
            Color(red: 0.6, green: 0.2, blue: 0.8),
            Color(red: 0.2, green: 0.5, blue: 0.9),
            Color(red: 0.9, green: 0.3, blue: 0.3),
            Color(red: 0.2, green: 0.7, blue: 0.5),
            Color(red: 0.9, green: 0.6, blue: 0.1),
        ]
        let index = abs(title.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedTypes: [UTType]
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
