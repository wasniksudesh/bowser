// VMBootstrap.swift
// Handles first-launch VM image download and setup

import Foundation

/// Manages VM image downloads and initial setup
class VMBootstrap {

    // MARK: - Properties

    /// CDN URL for VM images
    private let imageBaseURL = "https://downloads.bowser.io/vm"

    /// Current VM version
    private let vmVersion = "1.0.0"

    /// Paths
    private let vmDirectory: URL
    private let systemImagePath: URL
    private let versionFilePath: URL

    // MARK: - Progress Tracking

    typealias ProgressHandler = @Sendable (Double, String) -> Void

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        vmDirectory = appSupport.appendingPathComponent("Bowser/VM", isDirectory: true)
        systemImagePath = vmDirectory.appendingPathComponent("system.img")
        versionFilePath = vmDirectory.appendingPathComponent("version.txt")

        // Create VM directory
        try? FileManager.default.createDirectory(at: vmDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Bundle-bundled VM artifacts (build_full.sh)

    /// When the full build bundles VM artifacts directly into Resources/VM/, copy them to
    /// Application Support on first launch so VMManager can find them at its expected paths.
    func installBundledArtifactsIfNeeded() {
        let bundleVMDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/VM", isDirectory: true)

        let bundledSystem    = bundleVMDir.appendingPathComponent("system.img")
        let bundledKernel    = bundleVMDir.appendingPathComponent("vmlinuz")
        let bundledInitramfs = bundleVMDir.appendingPathComponent("initramfs")

        guard FileManager.default.fileExists(atPath: bundledSystem.path) else {
            // Not a full build — nothing to install
            return
        }

        let destSystem    = vmDirectory.appendingPathComponent("system.img")
        let destKernel    = vmDirectory.appendingPathComponent("vmlinuz")
        let destInitramfs = vmDirectory.appendingPathComponent("initramfs")

        let files: [(URL, URL)] = [
            (bundledSystem, destSystem),
            (bundledKernel, destKernel),
            (bundledInitramfs, destInitramfs),
        ]

        for (src, dst) in files {
            guard !FileManager.default.fileExists(atPath: dst.path) else { continue }
            do {
                try FileManager.default.copyItem(at: src, to: dst)
                print("[VMBootstrap] Installed bundled artifact: \(dst.lastPathComponent)")
            } catch {
                print("[VMBootstrap] Failed to install \(src.lastPathComponent): \(error)")
            }
        }

        // Mark version so needsDownload() returns false
        if !FileManager.default.fileExists(atPath: versionFilePath.path) {
            try? vmVersion.write(to: versionFilePath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Image Management

    /// Check if VM image needs to be downloaded or updated.
    /// Returns false when artifacts are already present (bundled or previously downloaded).
    func needsDownload() -> Bool {
        // Check if system.img exists
        guard FileManager.default.fileExists(atPath: systemImagePath.path) else {
            return true
        }

        // Check version
        if let installedVersion = try? String(contentsOf: versionFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            return installedVersion != vmVersion
        }

        return true
    }

    /// Get current installed version
    func installedVersion() -> String? {
        try? String(contentsOf: versionFilePath, encoding: .utf8).trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// Download VM system image
    func downloadSystemImage(progress: ProgressHandler?) async throws {
        let imageURL = URL(string: "\(imageBaseURL)/system-\(vmVersion).img")!

        print("[VMBootstrap] Downloading system image from: \(imageURL)")
        progress?(0.0, "Preparing download...")

        // Download to temporary location first
        let tempPath = vmDirectory.appendingPathComponent("system.img.download")

        // Remove any existing partial download
        try? FileManager.default.removeItem(at: tempPath)

        // Create URLSession with progress tracking
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)

        let (downloadURL, response) = try await session.download(from: imageURL)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw BootstrapError.downloadFailed("Invalid response from server")
        }

        progress?(0.9, "Verifying download...")

        // Move to temporary location
        try FileManager.default.moveItem(at: downloadURL, to: tempPath)

        // Verify downloaded image (basic size check)
        let attributes = try FileManager.default.attributesOfItem(atPath: tempPath.path)
        guard let fileSize = attributes[.size] as? UInt64, fileSize > 100_000_000 else {
            try? FileManager.default.removeItem(at: tempPath)
            throw BootstrapError.downloadFailed("Downloaded image is too small")
        }

        progress?(0.95, "Installing...")

        // Remove old image if exists
        try? FileManager.default.removeItem(at: systemImagePath)

        // Move to final location
        try FileManager.default.moveItem(at: tempPath, to: systemImagePath)

        // Save version
        try vmVersion.write(to: versionFilePath, atomically: true, encoding: .utf8)

        progress?(1.0, "Complete!")
        print("[VMBootstrap] System image downloaded successfully")
    }

    /// Download with progress callback using URLSessionDownloadDelegate
    func downloadSystemImageWithProgress(progress: @escaping ProgressHandler) async throws {
        let imageURL = URL(string: "\(imageBaseURL)/system-\(vmVersion).img")!

        print("[VMBootstrap] Downloading system image from: \(imageURL)")
        progress(0.0, "Connecting...")

        let tempPath = vmDirectory.appendingPathComponent("system.img.download")
        try? FileManager.default.removeItem(at: tempPath)

        // Use download delegate for progress
        let delegate = DownloadDelegate(tempPath: tempPath, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let task = session.downloadTask(with: imageURL)

        // Start download
        task.resume()

        // Wait for completion
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            delegate.completion = continuation
        }

        progress(0.95, "Installing...")

        // Remove old image
        try? FileManager.default.removeItem(at: systemImagePath)

        // Move to final location
        try FileManager.default.moveItem(at: tempPath, to: systemImagePath)

        // Save version
        try vmVersion.write(to: versionFilePath, atomically: true, encoding: .utf8)

        progress(1.0, "Complete!")
        print("[VMBootstrap] System image downloaded and installed")
    }

    /// Remove all VM files (for troubleshooting)
    func cleanupVMFiles() throws {
        try FileManager.default.removeItem(at: vmDirectory)
        try FileManager.default.createDirectory(at: vmDirectory, withIntermediateDirectories: true)
        print("[VMBootstrap] VM files cleaned up")
    }

    /// Get VM directory size for display
    func getVMDirectorySize() -> UInt64 {
        guard
            let enumerator = FileManager.default.enumerator(
                at: vmDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return 0
        }

        var totalSize: UInt64 = 0

        for case let fileURL as URL in enumerator {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                let fileSize = attributes[.size] as? UInt64
            else {
                continue
            }
            totalSize += fileSize
        }

        return totalSize
    }

    /// Format bytes for display
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let tempPath: URL
    let progress: VMBootstrap.ProgressHandler
    var completion: CheckedContinuation<Void, Error>?

    init(tempPath: URL, progress: @escaping VMBootstrap.ProgressHandler) {
        self.tempPath = tempPath
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            // Move downloaded file to temp location
            try FileManager.default.moveItem(at: location, to: tempPath)
            completion?.resume()
        } catch {
            completion?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progressValue = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let downloaded = ByteCountFormatter.string(
            fromByteCount: totalBytesWritten, countStyle: .file)
        let total = ByteCountFormatter.string(
            fromByteCount: totalBytesExpectedToWrite, countStyle: .file)

        progress(progressValue, "Downloading \(downloaded) / \(total)...")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error = error {
            completion?.resume(throwing: error)
        }
    }
}

// MARK: - Errors

enum BootstrapError: LocalizedError {
    case downloadFailed(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .installFailed(let message):
            return "Installation failed: \(message)"
        }
    }
}
