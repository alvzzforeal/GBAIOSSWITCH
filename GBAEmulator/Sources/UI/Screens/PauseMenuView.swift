// PauseMenuView.swift
// In-game pause overlay with save/load/settings actions.

import SwiftUI

struct PauseMenuView: View {
    @EnvironmentObject var emulatorState: EmulatorState
    @EnvironmentObject var romLibrary: ROMLibrary
    @State private var showSaveSlots = false
    @State private var showLoadSlots = false
    @State private var actionMessage: String?

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { emulatorState.resume() }

            VStack(spacing: 0) {
                // Title
                HStack {
                    Text(emulatorState.currentROM?.title ?? "Paused")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button { emulatorState.resume() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(20)

                Divider().overlay(Color.white.opacity(0.15))

                ScrollView {
                    VStack(spacing: 8) {
                        menuButton("Resume", icon: "play.fill", color: .green) {
                            emulatorState.resume()
                        }
                        menuButton("Save State", icon: "square.and.arrow.down.fill", color: Color(red: 0.4, green: 0.6, blue: 1.0)) {
                            showSaveSlots = true
                        }
                        menuButton("Load State", icon: "square.and.arrow.up.fill", color: Color(red: 1.0, green: 0.7, blue: 0.2)) {
                            showLoadSlots = true
                        }
                        menuButton("Reset", icon: "arrow.counterclockwise", color: .orange) {
                            emulatorState.reset()
                        }
                        Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 4)
                        menuButton("Quit to Library", icon: "house.fill", color: .red) {
                            emulatorState.stop()
                        }
                    }
                    .padding()
                }

                if let msg = actionMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 30)
            .padding(.horizontal, 32)
            .sheet(isPresented: $showSaveSlots) {
                SaveSlotPickerView(mode: .save) { slot in
                    emulatorState.saveState(slot: slot)
                    showSaveSlots = false
                    showAction("Saved to Slot \(slot)")
                }
            }
            .sheet(isPresented: $showLoadSlots) {
                SaveSlotPickerView(mode: .load) { slot in
                    emulatorState.loadState(slot: slot)
                    showLoadSlots = false
                    emulatorState.resume()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: actionMessage)
    }

    @ViewBuilder
    private func menuButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func showAction(_ msg: String) {
        actionMessage = msg
        Task {
            try? await Task.sleep(for: .seconds(2))
            actionMessage = nil
        }
    }
}

// MARK: - Save Slot Picker

enum SlotMode { case save, load }

struct SaveSlotPickerView: View {
    @EnvironmentObject var emulatorState: EmulatorState
    let mode: SlotMode
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) var dismiss

    var slots: [SaveSlotInfo] {
        guard let rom = emulatorState.currentROM else { return [] }
        return (0...9).map { slot in
            let meta = SaveManager.shared.stateMetadata(romID: rom.id, slot: slot)
            let exists = SaveManager.shared.stateExists(romID: rom.id, slot: slot)
            return SaveSlotInfo(slot: slot, metadata: meta.map { _ in meta! })
        }
    }

    var body: some View {
        NavigationStack {
            List(0...9, id: \.self) { slot in
                let exists = emulatorState.currentROM.map {
                    SaveManager.shared.stateExists(romID: $0.id, slot: slot)
                } ?? false
                let meta = emulatorState.currentROM.flatMap {
                    SaveManager.shared.stateMetadata(romID: $0.id, slot: slot)
                }

                Button {
                    if mode == .load && !exists { return }
                    onSelect(slot)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Slot \(slot)")
                                .font(.headline)
                            if let meta = meta {
                                Text(meta.formattedDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(mode == .save ? "Empty — tap to save" : "No save")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if exists {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(mode == .load && !exists)
            }
            .navigationTitle(mode == .save ? "Save State" : "Load State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
