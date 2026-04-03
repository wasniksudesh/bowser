// MicCaptureService.swift - OS-level microphone capture via AVCaptureSession
// Uses AVCaptureSession (CMSampleBuffer path) instead of AVAudioEngine to avoid
// reconfiguring the Core Audio graph, which crashes CEF's Bowser Helper audio
// renderer when ScreenCaptureKit is also active.

import AVFoundation
import Foundation

// Lightweight box that lets non-Sendable ObjC objects cross actor boundaries safely.
// Only use this for classes whose thread-safety is guaranteed externally (e.g. AVCaptureSession
// configured only from MainActor, used read-only from the background task below).
private final class SendableRef<T: AnyObject>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// =============================================================================
// MARK: - Mic Capture Service
// =============================================================================

/// Captures the default microphone via `AVCaptureSession` and forwards PCM
/// samples to `MeetingRecorderService` for chunked Whisper transcription.
///
/// Requires Microphone permission (System Settings → Privacy & Security →
/// Microphone). The TCC prompt fires automatically on the first call to
/// `AVCaptureDevice.requestAccess`.
@Observable
@MainActor
final class MicCaptureService: NSObject {

    // MARK: - Singleton

    static let shared = MicCaptureService()

    // MARK: - Public State

    /// True after the user denies Microphone permission.
    var permissionDenied: Bool = false

    /// True while capture is active.
    private(set) var isCapturing: Bool = false

    // MARK: - Private State

    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "bowser.mic-capture", qos: .userInitiated)
    private var sessionObservers: [NSObjectProtocol] = []

    // MARK: - Init

    private override init() {}

    // MARK: - Public API

    /// Start capturing the default microphone.
    /// Requests Microphone TCC permission on the first call if not yet granted.
    func start() async {
        NSLog("[RecordStart] ⑥ MicCaptureService.start() — isCapturing=%d", isCapturing ? 1 : 0)
        guard !isCapturing else {
            NSLog("[RecordStart] ⑥ already capturing, early return")
            return
        }
        permissionDenied = false

        NSLog("[RecordStart] ⑥ requesting mic permission…")
        let granted = await requestMicPermission()
        NSLog("[RecordStart] ⑥ mic permission result=%d", granted ? 1 : 0)
        guard granted else {
            permissionDenied = true
            NSLog("[MicCapture] Microphone permission denied")
            return
        }

        NSLog("[RecordStart] ⑥ calling startCaptureSession()")
        startCaptureSession()
        NSLog("[RecordStart] ⑥ startCaptureSession() returned — isCapturing=%d", isCapturing ? 1 : 0)
    }

    /// Stop capturing the microphone and tear down the session.
    func stop() {
        NSLog("[RecordStart] ⑦ MicCaptureService.stop() — isCapturing=%d", isCapturing ? 1 : 0)
        sessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sessionObservers = []
        // Guard on captureSession (not isCapturing) so we can stop even when
        // startRunning() is still in-flight and isCapturing hasn't been set yet.
        guard captureSession != nil else { return }
        captureSession?.stopRunning()
        captureSession = nil
        isCapturing = false
        NSLog("[RecordStart] ⑦ MicCaptureService stopped")
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

    // MARK: - Capture Session

    private func startCaptureSession() {
        NSLog("[RecordStart] ⑥ checking for audio input device")
        guard let micDevice = AVCaptureDevice.default(for: .audio) else {
            NSLog("[MicCapture] No audio input device available")
            return
        }
        NSLog("[RecordStart] ⑥ mic device: %@", micDevice.localizedName)

        let session = AVCaptureSession()

        NSLog("[RecordStart] ⑥ adding device input")
        guard let input = try? AVCaptureDeviceInput(device: micDevice) else {
            NSLog("[MicCapture] Failed to create AVCaptureDeviceInput")
            return
        }
        guard session.canAddInput(input) else {
            NSLog("[MicCapture] Cannot add input to session")
            return
        }
        session.addInput(input)

        NSLog("[RecordStart] ⑥ adding audio data output")
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            NSLog("[MicCapture] Cannot add output to session")
            return
        }
        session.addOutput(output)

        // Store session reference before startRunning() so stop() can interrupt it
        // even if called while startRunning() is still blocking on the background queue.
        captureSession = session
        registerSessionObservers(for: session)

        // AVCaptureSession.startRunning() is a blocking call. Apple docs explicitly
        // require it runs off the main thread to prevent UI freezes (can take 500ms+
        // with Bluetooth mics or when the audio subsystem is initialising).
        // We box `session` in SendableRef so Swift 6 strict-concurrency doesn't flag
        // the capture; we own the thread-safety by only mutating session state from MainActor.
        let sessionRef = SendableRef(session)
        NSLog("[RecordStart] ⑥ dispatching startRunning() to background queue…")
        Task.detached(priority: .userInitiated) { [weak self] in
            sessionRef.value.startRunning()
            let isRunning = sessionRef.value.isRunning
            NSLog("[RecordStart] ⑥ startRunning() returned — isRunning=%d", isRunning ? 1 : 0)
            await MainActor.run { [weak self] in
                guard let self, self.captureSession === sessionRef.value else { return }
                self.isCapturing = isRunning
                if isRunning {
                    NSLog("[RecordStart] ⑥ MicCapture started OK via AVCaptureSession")
                } else {
                    NSLog("[MicCapture] Session failed to start after startRunning()")
                }
            }
        }
    }

    // MARK: - Session Observers

    private func registerSessionObservers(for session: AVCaptureSession) {
        let errorObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            NSLog("[MicCapture] Runtime error: %@", error?.localizedDescription ?? "unknown")
            Task { @MainActor [weak self] in
                self?.captureSession = nil
                self?.isCapturing = false
            }
        }

        let interruptObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            NSLog("[MicCapture] Session interrupted (device disconnected or taken by another app)")
            Task { @MainActor [weak self] in self?.isCapturing = false }
        }

        let resumeObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: .main
        ) { [weak self] _ in
            NSLog("[MicCapture] Session interruption ended — resuming")
            Task { @MainActor [weak self] in self?.isCapturing = true }
        }

        sessionObservers = [errorObserver, interruptObserver, resumeObserver]
    }
}

// =============================================================================
// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
// =============================================================================

extension MicCaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
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

        // Determine the sample format from the format description
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        guard let desc = asbd?.pointee else { return }

        let sampleRate = Int(desc.mSampleRate)
        let channels = Int(desc.mChannelsPerFrame)
        let bytesPerSample = Int(desc.mBitsPerChannel / 8)

        // Convert to Float32 samples regardless of source format
        let samples: [Float]
        if desc.mFormatFlags & kAudioFormatFlagIsFloat != 0 && bytesPerSample == 4 {
            let count = totalLength / MemoryLayout<Float>.size
            guard count > 0 else { return }
            samples = Array(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self),
                count: count
            ))
        } else if desc.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && bytesPerSample == 2 {
            let count = totalLength / MemoryLayout<Int16>.size
            guard count > 0 else { return }
            let int16Ptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Int16.self)
            samples = (0..<count).map { Float(int16Ptr[$0]) / 32768.0 }
        } else {
            return
        }

        // Mix down to mono if stereo
        let monoSamples: [Float]
        if channels == 2 {
            let frameCount = samples.count / 2
            var mixed = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                mixed[i] = (samples[i * 2] + samples[i * 2 + 1]) * 0.5
            }
            monoSamples = mixed
        } else {
            monoSamples = samples
        }

        Task { @MainActor in
            MeetingRecorderService.shared.receiveMicData(monoSamples, sampleRate: sampleRate)
        }
    }
}
