// EmulatorState.swift
// Observable state object that drives the SwiftUI views.

import Foundation
import SwiftUI
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

// MARK: - Emulator Status

enum EmulatorStatus: Equatable {
    case idle
    case running
    case paused
    case error(String)
}

// MARK: - EmulatorState

@MainActor
final class EmulatorState: ObservableObject {

    // MARK: - Published UI state
    @Published var status: EmulatorStatus = .idle
    @Published var currentROM: ROMEntry? = nil
    @Published var currentFrame: CGImage? = nil
    @Published var fps: Double = 0.0
    @Published var showPauseMenu: Bool = false

    // MARK: - Core
    let core = EmulatorCore()

    // MARK: - Frame loop
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    private var fpsUpdateTimer: Timer?

    // MARK: - ROM Loading

    func loadAndStart(rom: ROMEntry, library: ROMLibrary) async {
        do {
            let data = try library.romData(for: rom)
            try core.loadROM(data: data)
            currentROM = rom
            status = .running
            showPauseMenu = false
            startFrameLoop()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Lifecycle

    func start() {
        core.start()
        status = .running
        showPauseMenu = false
        startFrameLoop()
    }

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
    }

    func stop() {
        core.pause()
        stopFrameLoop()
        status = .idle
        currentROM = nil
        currentFrame = nil
        showPauseMenu = false
    }

    // MARK: - Input

    func press(button: GBAButton) {
        core.pressButton(button)
    }

    func release(button: GBAButton) {
        core.releaseButton(button)
    }

    // MARK: - Save / Load State

    func saveState(slot: Int) {
        guard let rom = currentROM, let data = core.saveState() else { return }
        SaveManager.shared.saveState(data: data, romID: rom.id, slot: slot)
    }

    func loadState(slot: Int) {
        guard let rom = currentROM,
              let data = SaveManager.shared.loadState(romID: rom.id, slot: slot) else { return }
        core.loadState(data: data)
    }

    // MARK: - Frame Loop

    private func startFrameLoop() {
        stopFrameLoop()
        let link = CADisplayLink(target: self, selector: #selector(frameStep))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link

        fpsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fps = Double(self.frameCount)
                self.frameCount = 0
            }
        }
    }

    private func stopFrameLoop() {
        displayLink?.invalidate()
        displayLink = nil
        fpsUpdateTimer?.invalidate()
        fpsUpdateTimer = nil
    }

    @objc private func frameStep() {
        guard case .running = status else { return }
        core.stepFrame()
        currentFrame = core.getVideoFrame()
        frameCount += 1

        // Auto-save battery save every 30 seconds
        if frameCount % (60 * 30) == 0, let rom = currentROM {
            if let batterySave = core.exportBatterySave() {
                SaveManager.shared.saveBatterySave(data: batterySave, romID: rom.id)
            }
        }
    }
}
