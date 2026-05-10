// StubEmulatorBridge.swift
// Pure Swift stub used when compiling without mGBA.
// Replace calls to this with MGBAEmulatorBridge once integrated.
//
// NOTE: In a real Xcode project, MGBAEmulatorBridge (ObjC++) would be
// accessible from Swift via the Bridging Header. The EmulatorCore.swift
// uses a compile-time flag (MGBA_INTEGRATED) to switch between them.
// This file exists only for standalone Swift compilation testing.

import Foundation
import CoreGraphics
import Darwin // for sin()

final class StubEmulatorBridge {
    private var frameCount: UInt32 = 0
    private var loaded = false
    private var keyState: UInt32 = 0

    static let width = 240
    static let height = 160

    func loadROM(_ data: Data) -> Bool {
        guard data.count >= 0xC0 else { return false }
        loaded = true
        return true
    }

    func start()  { frameCount = 0 }
    func pause()  {}
    func resume() {}
    func reset()  { frameCount = 0 }

    func stepFrame() {
        guard loaded else { return }
        frameCount &+= 1
    }

    func getVideoFrameBuffer() -> Data? {
        guard loaded else { return nil }
        let w = StubEmulatorBridge.width
        let h = StubEmulatorBridge.height
        var buf = Data(count: w * h * 4)
        let fc = frameCount
        buf.withUnsafeMutableBytes { ptr in
            guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    base[i+0] = UInt8((UInt32(x) &+ fc) & 0xFF)
                    base[i+1] = UInt8((UInt32(y * 2) &+ fc &>> 1) & 0xFF)
                    base[i+2] = UInt8((fc &* 2) & 0xFF)
                    base[i+3] = 0xFF
                }
            }
        }
        return buf
    }

    func getAudioSamples() -> [Int16] {
        let count = 32768 / 60
        var out = [Int16]()
        out.reserveCapacity(count * 2)
        let freq = 440.0
        let sr = 32768.0
        for i in 0..<count {
            let t = Double(UInt64(frameCount) * UInt64(count) + UInt64(i)) / sr
            let s = Int16(sin(2.0 * .pi * freq * t) * 800.0)
            out.append(s)
            out.append(s)
        }
        return out
    }

    func pressButton(_ index: Int)   { keyState |= (1 << index) }
    func releaseButton(_ index: Int) { keyState &= ~(1 << index) }

    func saveState() -> Data? {
        var fc = frameCount
        return Data(bytes: &fc, count: 4)
    }

    func loadState(_ data: Data) {
        guard data.count >= 4 else { return }
        data.withUnsafeBytes { ptr in
            frameCount = ptr.load(as: UInt32.self)
        }
    }

    func exportBatterySave() -> Data? { return nil }
    func importBatterySave(_ data: Data) {}
}
