// GBAAudioEngine.swift
// AVAudioEngine-based audio output for GBA emulation.
// Receives Int16 stereo samples from the core and plays them with low latency.

import AVFoundation
import Accelerate

final class GBAAudioEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Int

    // Lock-free circular buffer
    private var sampleBuffer: [Float] = []
    private let bufferLock = NSLock()
    private let maxBufferSamples = 32768 * 2 // 2 seconds at 32768 Hz stereo

    init(sampleRate: Int = 32768) {
        self.sampleRate = sampleRate
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 2,
            interleaved: true
        )!
        setupEngine()
    }

    private func setupEngine() {
        configureAudioSession()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.play()
        } catch {
            print("[GBAAudioEngine] Failed to start: \(error)")
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005) // 5ms for low latency
            try session.setActive(true)
        } catch {
            print("[GBAAudioEngine] Session config error: \(error)")
        }
    }

    // MARK: - Feed samples from emulator core

    /// Enqueue interleaved stereo Int16 samples (L, R, L, R...) from the emulator.
    func enqueue(samples: [Int16]) {
        guard !samples.isEmpty, samples.count % 2 == 0 else { return }

        // Convert Int16 to Float32 normalized to [-1, 1]
        var floats = [Float](repeating: 0, count: samples.count)
        vDSP_vflt16(samples, 1, &floats, 1, vDSP_Length(samples.count))
        var scale: Float = 1.0 / 32768.0
        vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(floats.count))

        bufferLock.lock()
        sampleBuffer.append(contentsOf: floats)
        // Trim if buffer grows too large (emulator running fast)
        if sampleBuffer.count > maxBufferSamples {
            sampleBuffer.removeFirst(sampleBuffer.count - maxBufferSamples)
        }
        let available = sampleBuffer.count
        bufferLock.unlock()

        // Schedule audio if we have at least half a frame
        let frameSize = sampleRate / 60 * 2
        if available >= frameSize {
            scheduleBuffer()
        }
    }

    private func scheduleBuffer() {
        bufferLock.lock()
        let frameSize = sampleRate / 60 * 2
        guard sampleBuffer.count >= frameSize else { bufferLock.unlock(); return }
        let chunk = Array(sampleBuffer.prefix(frameSize))
        sampleBuffer.removeFirst(frameSize)
        bufferLock.unlock()

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameSize / 2)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(frameSize / 2)

        guard let channelData = pcmBuffer.floatChannelData else { return }
        // Interleaved → deinterleaved (AVAudioEngine uses deinterleaved for non-interleaved formats,
        // but we set interleaved: true above so we can write directly)
        let mutablePtr = channelData[0]
        for i in 0..<frameSize {
            mutablePtr[i] = chunk[i]
        }

        playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
    }

    // MARK: - Lifecycle

    func start() {
        if !engine.isRunning {
            try? engine.start()
            playerNode.play()
        }
    }

    func pause() {
        playerNode.pause()
    }

    func resume() {
        if !engine.isRunning { try? engine.start() }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        engine.stop()
    }

    // MARK: - Volume

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }
}
