// GBAEmulatorApp.swift
// Entry point of the GBA Emulator app

import SwiftUI

@main
struct GBAEmulatorApp: App {
    @StateObject private var romLibrary = ROMLibrary()
    @StateObject private var emulatorState = EmulatorState()
    @StateObject private var multiplayerService = LocalMultiplayerService()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(romLibrary)
                .environmentObject(emulatorState)
                .environmentObject(multiplayerService)
                .environmentObject(settingsStore)
        }
    }
}
