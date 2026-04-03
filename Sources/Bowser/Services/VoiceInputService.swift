// VoiceInputService.swift - Microphone voice-to-text via AVAudioEngine + Whisper
// Captures microphone input in 2-second chunks, sends to Sidecar /api/transcribe,
// and calls back with transcript text for progressive text field population.

import AVFoundation
import Foundation

// =============================================================================
// MARK: - Voice Input Service
// =============================================================================

/// Singleton service that captures microphone audio and returns live transcription.
///
/// Usage:
/// ```swift
/// VoiceInputService.shared.startListening { text in
///     myTextField += text + " "
/// }
/// // ...
/// VoiceInputService.shared.stopListening()
/// ```
@Observable
@MainActor
final class VoiceInputService {

    // MARK: - Singleton

    static let shared = VoiceInputService()

    // MARK: - Public State

    var isListening: Bool = false
    var errorMessage: String?

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var sampleBuffer: [Float] = []
    private var chunkTimer: Timer?
    private var onTranscript: ((String) -> Void)?
    private let sampleRate: Double = 16000   // Whisper performs best at 16 kHz
    private let chunkInterval: TimeInterval = 2.0

    private let sidecarURL = URL(string: "http://localhost:8765")!

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Start listening on the microphone and call `onTranscript` for each chunk.
    /// The callback is called on MainActor with transcribed text.
    func startListening(onTranscript: @escaping @MainActor (String) -> Void) {
        guard !isListening else { return }
        errorMessage = nil
        self.onTranscript = onTranscript
        sampleBuffer = []

        // Request microphone permission then start
        Task {
            let granted = await requestMicPermission()
            guard granted else {
                errorMessage = "Microphone access denied. Enable it in System Settings → Privacy."
                return
            }
            startAudioEngine()
        }
    }

    /// Stop listening, flush the remaining buffer, and clean up.
    func stopListening() {
        guard isListening else { return }
        chunkTimer?.invalidate()
        chunkTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        audioConverter = nil
        isListening = false

        // Flush remaining audio *before* clearing the callback
        let remaining = sampleBuffer
        sampleBuffer = []
        if !remaining.isEmpty {
            let cb = onTranscript
            Task {
                await flushBuffer(remaining, callback: cb)
            }
        }
        onTranscript = nil
    }

    // MARK: - Permission

    private func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - Audio Engine

    private func startAudioEngine() {
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            errorMessage = "Failed to create audio format"
            return
        }

        // Create a single converter and reuse it across all tap callbacks
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            errorMessage = "Failed to create audio converter"
            return
        }
        self.audioConverter = converter

        // Capture everything the tap closure needs so it never touches @MainActor state.
        let capturedConverter = converter
        let capturedTargetSR = sampleRate
        let hwSR = hwFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) {
            [weak self] buffer, _ in
            let outputFrameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * capturedTargetSR / hwSR
            )
            guard outputFrameCapacity > 0,
                  let convertedBuffer = AVAudioPCMBuffer(
                      pcmFormat: targetFormat,
                      frameCapacity: outputFrameCapacity
                  )
            else { return }

            var error: NSError?
            var inputConsumed = false
            capturedConverter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard error == nil,
                  let channelData = convertedBuffer.floatChannelData?[0]
            else { return }

            let frameCount = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            Task { @MainActor [weak self] in
                self?.sampleBuffer.append(contentsOf: samples)
            }
        }

        do {
            try engine.start()
            isListening = true

            chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkInterval, repeats: true) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.flushCurrentChunk()
                }
            }
        } catch {
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
            audioConverter = nil
        }
    }

    // MARK: - Chunking

    private func flushCurrentChunk() {
        guard !sampleBuffer.isEmpty else { return }
        let chunk = sampleBuffer
        sampleBuffer = []
        Task {
            await flushBuffer(chunk)
        }
    }

    private func flushBuffer(_ samples: [Float], callback: ((String) -> Void)? = nil) async {
        let cb = callback ?? onTranscript
        guard let wavData = encodeWAV(samples: samples, channels: 1, sampleRate: Int(sampleRate)),
              let cb
        else { return }

        do {
            let text = try await transcribe(wavData: wavData)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            cb(text)
        } catch {
            print("[VoiceInput] Transcription error: \(error)")
        }
    }

    // MARK: - Sidecar Call

    private func transcribe(wavData: Data) async throws -> String {
        let url = sidecarURL.appendingPathComponent("api/transcribe")
        let boundary = "VoiceBoundary\(UUID().uuidString.prefix(8))"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"voice.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct TranscribeResponse: Decodable { let text: String }
        return try JSONDecoder().decode(TranscribeResponse.self, from: data).text
    }

    // MARK: - WAV Encoding

    private func encodeWAV(samples: [Float], channels: Int, sampleRate: Int) -> Data? {
        guard channels > 0, sampleRate > 0, !samples.isEmpty else { return nil }

        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels) * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count) * UInt32(bitsPerSample / 8)

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLEUInt32(36 + dataSize)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLEUInt32(16)
        wav.appendLEUInt16(1)
        wav.appendLEUInt16(UInt16(channels))
        wav.appendLEUInt32(UInt32(sampleRate))
        wav.appendLEUInt32(byteRate)
        wav.appendLEUInt16(blockAlign)
        wav.appendLEUInt16(bitsPerSample)
        wav.append(contentsOf: "data".utf8)
        wav.appendLEUInt32(dataSize)

        for sample in samples {
            let s16 = Int16(max(-32768, min(32767, Int(sample * 32767.0))))
            wav.appendLEInt16(s16)
        }
        return wav
    }
}

// =============================================================================
// MARK: - Data Helpers
// =============================================================================

private extension Data {
    mutating func appendLEUInt16(_ v: UInt16) {
        var le = v.littleEndian; Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendLEUInt32(_ v: UInt32) {
        var le = v.littleEndian; Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendLEInt16(_ v: Int16) {
        var le = v.littleEndian; Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
