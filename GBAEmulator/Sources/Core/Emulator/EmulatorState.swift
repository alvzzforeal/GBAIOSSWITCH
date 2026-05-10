// EmulatorCore.swift
// Swift wrapper around MGBAEmulatorBridge (Objective-C++ bridge to mGBA C core)
//
// INTEGRATION NOTE:
// This file depends on MGBAEmulatorBridge, an Objective-C++ class that you must
// compile together with the mGBA source. See INTEGRATION.md for full instructions.
//
// Until mGBA is integrated, a StubEmulatorBridge is used so the UI compiles.

import Foundation
import CoreGraphics
import AVFoundation

// MARK: - EmulatorCore

final class EmulatorCore {

    // MARK: - Screen constants
    static let screenWidth = 240
    static let screenHeight = 160
    static let audioSampleRate: Int = 32768
    static let framesPerSecond: Double = 59.7275

    // MARK: - Internal bridge
    // In production: replace StubEmulatorBridge with MGBAEmulatorBridge
    #if MGBA_INTEGRATED
    private let bridge = MGBAEmulatorBridge()
    #else
    private let bridge = StubEmulatorBridge()
    #endif

    private var audioEngine: GBAAudioEngine?
    private var isRunning = false

    // MARK: - Lifecycle

    /// Load ROM data into the emulator core.
    /// - Throws: EmulatorError if the ROM is invalid or the core fails to initialize.
    func loadROM(data: Data) throws {
        let result = bridge.loadROM(data)
        guard result else {
            throw EmulatorError.romLoadFailed("Core rejected the ROM. Ensure it is a valid GBA ROM.")
        }
        audioEngine = GBAAudioEngine(sampleRate: Self.audioSampleRate)
        audioEngine?.start()
    }

    func start() {
        bridge.start()
        isRunning = true
    }

    func pause() {
        bridge.pause()
        isRunning = false
        audioEngine?.pause()
    }

    func resume() {
        bridge.resume()
        isRunning = true
        audioEngine?.resume()
    }

    func reset() {
        bridge.reset()
        isRunning = true
    }

    // MARK: - Frame step

    /// Advance the emulator by one frame (called at ~60Hz by the frame loop).
    func stepFrame() {
        bridge.stepFrame()

        // Pull audio samples from core and push to audio engine
        let rawSamples = bridge.getAudioSamples()
        if !rawSamples.isEmpty {
            let samples = rawSamples.map { $0.int16Value }
            audioEngine?.enqueue(samples: samples)
        }
    }

    // MARK: - Video

    /// Get the current video frame as a CGImage (240x160, RGB555/888).
    func getVideoFrame() -> CGImage? {
        guard let pixelData = bridge.getVideoFrameBuffer() else { return nil }
        return buildCGImage(from: pixelData)
    }

    private func buildCGImage(from data: Data) -> CGImage? {
        let width = Self.screenWidth
        let height = Self.screenHeight
        // mGBA outputs XBGR8888 or RGB565 depending on build flags.
        // We request RGBA8888 from the bridge for simplicity.
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        var mutableData = data
        return mutableData.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let baseAddress = ptr.baseAddress else { return nil }
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
            return context?.makeImage()
        }
    }

    // MARK: - Audio

    func getAudioSamples() -> [Int16] {
        return bridge.getAudioSamples().map { $0.int16Value }
    }

    // MARK: - Input

    func pressButton(_ button: GBAButton) {
        bridge.pressButton(button.rawValue)
    }

    func releaseButton(_ button: GBAButton) {
        bridge.releaseButton(button.rawValue)
    }

    // MARK: - Save States

    func saveState() -> Data? {
        return bridge.saveState()
    }

    func loadState(data: Data) {
        bridge.loadState(data)
    }

    // MARK: - Battery Save (SRAM/Flash/EEPROM)

    func exportBatterySave() -> Data? {
        return bridge.exportBatterySave()
    }

    func importBatterySave(data: Data) {
        bridge.importBatterySave(data)
    }
}

// MARK: - Errors

enum EmulatorError: LocalizedError {
    case romLoadFailed(String)
    case stateUnavailable

    var errorDescription: String? {
        switch self {
        case .romLoadFailed(let msg): return "ROM Load Failed: \(msg)"
        case .stateUnavailable: return "No save state available"
        }
    }
}
