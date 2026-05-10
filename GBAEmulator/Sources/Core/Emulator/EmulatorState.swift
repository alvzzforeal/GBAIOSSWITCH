// EmulatorState.swift
// Observable state for the running emulator session

import Foundation
import Combine
import SwiftUI

// MARK: - GBA Button Enum

enum GBAButton: Int, CaseIterable, Codable {
    case a = 0
    case b = 1
    case select = 2
    case start = 3
    case right = 4
    case left = 5
    case up = 6
    case down = 7
    case r = 8
    case l = 9

    var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .select: return "Select"
        case .start: return "Start"
        case .right: return "Right"
        case .left: return "Left"
        case .up: return "Up"
        case .down: return "Down"
        case .r: return "R"
        case .l: return "L"
        }
    }
}

// MARK: - Emulator Status

enum EmulatorStatus {
    case idle
    case running
    case paused
    case error(String)
}

// MARK: - EmulatorState

@MainActor
final class EmulatorState: ObservableObject {
    @Published var status: EmulatorStatus = .idle
    @Published var currentROM: ROMEntry?
    @Published var fps: Double = 0
    @Published var currentFrame: CGImage?
    @Published var showPauseMenu = false

    // The underlying core - this is the bridge to mGBA
    let core: EmulatorCore

    private var frameTimer: AnyCancellable?
    private var fpsCounter = FPSCounter()

    init() {
        self.core = EmulatorCore()
    }

    // MARK: - Load & Start

    func loadAndStart(rom: ROMEntry, library: ROMLibrary) async {
        do {
            let data = try library.romData(for: rom)
            currentROM = rom
            try core.loadROM(data: data)

            // Load battery save if exists
            if let saveData = SaveManager.shared.loadBatterySave(romID: rom.id) {
                core.importBatterySave(data: saveData)
            }

            core.start()
            status = .running
            startFrameLoop()
        } catch {
            status = .error("Failed to load ROM: \(error.localizedDescription)")
        }
    }

    // MARK: - Controls

    func press(button: GBAButton) {
        core.pressButton(button)
    }

    func release(button: GBAButton) {
        core.releaseButton(button)
    }

    // MARK: - Pause / Resume

    func pause() {
        core.pause()
        status = .paused
        showPauseMenu = true
        stopFrameLoop()
    }

    func resume() {
        core.resume()
        status = .running
        showPauseMenu = false
        startFrameLoop()
    }

    func reset() {
        core.reset()
        status = .running
        showPauseMenu = false
        startFrameLoop()
    }

    func stop() {
        autoSave()
        core.pause()
        status = .idle
        currentROM = nil
        currentFrame = nil
        stopFrameLoop()
    }

    // MARK: - Save States

    func saveState(slot: Int) {
        guard let rom = currentROM else { return }
        if let stateData = core.saveState() {
            SaveManager.shared.saveState(data: stateData, romID: rom.id, slot: slot)
        }
    }

    func loadState(slot: Int) {
        guard let rom = currentROM else { return }
        if let stateData = SaveManager.shared.loadState(romID: rom.id, slot: slot) {
            core.loadState(data: stateData)
        }
    }

    func autoSave() {
        guard let rom = currentROM else { return }
        // Battery save (SRAM)
        if let saveData = core.exportBatterySave() {
            SaveManager.shared.saveBatterySave(data: saveData, romID: rom.id)
        }
        // Auto save state
        if let stateData = core.saveState() {
            SaveManager.shared.saveState(data: stateData, romID: rom.id, slot: -1) // slot -1 = auto
        }
    }

    // MARK: - Frame Loop

    private func startFrameLoop() {
        stopFrameLoop()
        // GBA runs at ~59.73 fps. We use a display-link style timer.
        frameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopFrameLoop() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func tick() {
        guard case .running = status else { return }
        core.stepFrame()
        if let cgImage = core.getVideoFrame() {
            currentFrame = cgImage
        }
        fps = fpsCounter.tick()
    }
}

// MARK: - FPS Counter

private struct FPSCounter {
    private var lastTime = Date()
    private var frameCount = 0
    private var currentFPS: Double = 0

    mutating func tick() -> Double {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastTime = now
        }
        return currentFPS
    }
}
