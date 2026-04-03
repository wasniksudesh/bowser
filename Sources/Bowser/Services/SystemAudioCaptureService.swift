// SystemAudioCaptureService.swift - OS-level system audio capture via ScreenCaptureKit
// Captures all macOS audio output (any app: WhatsApp, Zoom, FaceTime, browser, etc.)
// and feeds interleaved float32 PCM into MeetingRecorderService.

import Foundation
@preconcurrency import ScreenCaptureKit

// =============================================================================
// MARK: - System Audio Capture Service
// =============================================================================

/// Captures system-wide audio output using ScreenCaptureKit and forwards PCM
/// samples to `MeetingRecorderService` for chunking and transcription.
///
/// Requires Screen Recording permission (System Settings → Privacy & Security →
/// Screen Recording). The TCC prompt fires automatically on the first call to
/// `SCShareableContent`.
@Observable
@MainActor
final class SystemAudioCaptureService: NSObject {

    // MARK: - Singleton

    static let shared = SystemAudioCaptureService()

    // MARK: - Public State

    /// True after the user denies Screen Recording permission.
    var permissionDenied: Bool = false

    /// True while capture is active.
    private(set) var isCapturing: Bool = false

    // MARK: - Private State

    private var stream: SCStream?

    // Fixed format delivered by SCK when configured below
    private let sampleRate = 48000
    private let channelCount = 2

    // MARK: - Init

    private override init() {}

    // MARK: - Public API

    /// Start capturing all system audio output.
    /// Triggers a TCC permission prompt on first call if not yet granted.
    func start() async {
        NSLog("[RecordStart] ⑤ SystemAudioCaptureService.start() — isCapturing=%d", isCapturing ? 1 : 0)
        guard !isCapturing else {
            NSLog("[RecordStart] ⑤ already capturing, early return")
            return
        }
        permissionDenied = false

        do {
            NSLog("[RecordStart] ⑤ requesting SCShareableContent…")
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            NSLog("[RecordStart] ⑤ SCShareableContent OK — displays=%d", content.displays.count)

            guard let display = content.displays.first else {
                NSLog("[SystemAudio] No display found for SCContentFilter")
                return
            }

            NSLog("[RecordStart] ⑤ creating SCStream filter+config")
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = sampleRate
            config.channelCount = channelCount
            config.width = 2
            config.height = 2

            NSLog("[RecordStart] ⑤ creating SCStream")
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            NSLog("[RecordStart] ⑤ addStreamOutput")
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            NSLog("[RecordStart] ⑤ startCapture…")
            try await newStream.startCapture()

            stream = newStream
            isCapturing = true
            NSLog("[RecordStart] ⑤ SystemAudio capture started ✓")

        } catch let error as SCStreamError where error.code == .userDeclined {
            permissionDenied = true
            print("[SystemAudio] Permission denied by user")
        } catch {
            let nsError = error as NSError
            if nsError.code == 5 || nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
                permissionDenied = true
                print("[SystemAudio] Screen Recording permission not granted: \(error)")
            } else {
                print("[SystemAudio] Failed to start capture: \(error)")
            }
        }
    }

    /// Stop capturing system audio.
    func stop() async {
        guard isCapturing, let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            print("[SystemAudio] Error stopping capture: \(error)")
        }
        self.stream = nil
        isCapturing = false
        print("[SystemAudio] Capture stopped")
    }
}

// =============================================================================
// MARK: - SCStreamOutput (audio sample delivery)
// =============================================================================

extension SystemAudioCaptureService: SCStreamOutput {

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let ptr = dataPointer, totalLength > 0 else { return }

        let count = totalLength / MemoryLayout<Float>.size
        guard count > 0 else { return }

        let samples = Array(UnsafeBufferPointer(
            start: UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self),
            count: count
        ))

        Task { @MainActor in
            MeetingRecorderService.shared.receiveAudioData(samples)
        }
    }
}

// =============================================================================
// MARK: - SCStreamDelegate (error / stop handling)
// =============================================================================

extension SystemAudioCaptureService: SCStreamDelegate {

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let nsErr = error as NSError
        NSLog("[RecordStart] ⑦ SCStream didStopWithError — domain=%@ code=%d desc=%@",
              nsErr.domain, nsErr.code, nsErr.localizedDescription)
        Task { @MainActor in
            self.stream = nil
            self.isCapturing = false
        }
    }
}
