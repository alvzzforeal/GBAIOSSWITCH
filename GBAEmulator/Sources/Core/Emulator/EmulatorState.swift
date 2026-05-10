// EmulatorState.swift
// Observable state object that drives the SwiftUI views.

import Foundation
import Combine

// MARK: - GBAButton

enum GBAButton: Int, CaseIterable, Hashable {
    case a      = 0
    case b      = 1
    case select = 2
    case start  = 3
    case right  = 4
    case left   = 5
    case up     = 6
    case down   = 7
    case r      = 8
    case l      = 9
}

// MARK: - EmulatorState

final class EmulatorState: ObservableObject {

    // MARK: - Published UI state
    @Published var isROMLoaded: Bool = false
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentROMName: String = ""
    @Published var errorMessage: String? = nil

    // MARK: - Core
    let core = EmulatorCore()

    // MARK: - ROM Loading

    func loadROM(data: Data, name: String) {
        do {
            try core.loadROM(data: data)
            currentROMName = name
            isROMLoaded = true
            errorMessage = nil
            start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Lifecycle

    func start() {
        core.start()
        isRunning = true
        isPaused = false
    }

    func pause() {
        core.pause()
        isPaused = true
        isRunning = false
    }

    func resume() {
        core.resume()
        isPaused = false
        isRunning = true
    }

    func reset() {
        core.reset()
        isRunning = true
        isPaused = false
    }

    // MARK: - Input

    func pressButton(_ button: GBAButton) {
        core.pressButton(button)
    }

    func releaseButton(_ button: GBAButton) {
        core.releaseButton(button)
    }

    // MARK: - Save / Load State

    func saveState() -> Data? {
        return core.saveState()
    }

    func loadState(data: Data) {
        core.loadState(data: data)
    }

    // MARK: - Battery Save

    func exportBatterySave() -> Data? {
        return core.exportBatterySave()
    }

    func importBatterySave(data: Data) {
        core.importBatterySave(data: data)
    }
}
