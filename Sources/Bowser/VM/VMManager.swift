// VMManager.swift
// Manages the lifecycle of the Alpine Linux VM running the Python backend

import Foundation
import Network
import os.log
import Security
@preconcurrency import Virtualization

/// Manages the Alpine Linux VM that runs the Python backend in production mode
@MainActor
class VMManager: NSObject, ObservableObject {
    static let shared = VMManager()

    private let logger = Logger(subsystem: "com.bowser.mac", category: "VMManager")

    // MARK: - Properties

    @Published var isRunning = false
    @Published var isBooting = false
    @Published var bootError: String?

    private var virtualMachine: VZVirtualMachine?
    private var vsockDevice: VZVirtioSocketDevice?

    /// VM configuration
    private let cpuCount = 2
    private let memorySize: UInt64 = 2 * 1024 * 1024 * 1024  // 2GB

    /// Paths
    private let vmDirectory: URL
    private let systemImagePath: URL
    private let mem0ImagePath: URL
    private let luksKeyPath: URL
    private let kernelPath: URL
    private let initramfsPath: URL
    private let consoleLogPath: URL


    // MARK: - Initialization

    private override init() {
        // Setup paths
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        vmDirectory = appSupport.appendingPathComponent("Bowser/VM", isDirectory: true)
        systemImagePath = vmDirectory.appendingPathComponent("system.img")
        mem0ImagePath = vmDirectory.appendingPathComponent("mem0.img")
        luksKeyPath = vmDirectory.appendingPathComponent(".luks-key")
        kernelPath = vmDirectory.appendingPathComponent("vmlinuz")
        initramfsPath = vmDirectory.appendingPathComponent("initramfs")
        consoleLogPath = vmDirectory.appendingPathComponent("vm-console.log")

        super.init()

        // Create VM directory if needed
        try? FileManager.default.createDirectory(at: vmDirectory, withIntermediateDirectories: true)
    }

    // MARK: - VM Lifecycle

    /// Start the VM
    func startVM() async throws {
        guard !isRunning else {
            print("[VMManager] VM already running")
            return
        }

        isBooting = true
        bootError = nil

        do {
            // Check if images exist
            guard FileManager.default.fileExists(atPath: systemImagePath.path) else {
                throw VMError.systemImageNotFound
            }

            guard FileManager.default.fileExists(atPath: kernelPath.path) else {
                throw VMError.kernelNotFound
            }

            guard FileManager.default.fileExists(atPath: initramfsPath.path) else {
                throw VMError.initramfsNotFound
            }

            // Create mem0.img if it doesn't exist
            if !FileManager.default.fileExists(atPath: mem0ImagePath.path) {
                try createMem0Image()
            }

            // Create VM configuration
            let config = try createVMConfiguration()

            // Create and start VM
            virtualMachine = VZVirtualMachine(configuration: config)
            virtualMachine?.delegate = self
            self.vsockDevice = virtualMachine?.socketDevices.first as? VZVirtioSocketDevice

            logger.info("Starting VM with kernel=\(self.kernelPath.lastPathComponent, privacy: .public) initramfs=\(self.initramfsPath.lastPathComponent, privacy: .public) system=\(self.systemImagePath.lastPathComponent, privacy: .public)")
            do {
                try await virtualMachine?.start(options: VZVirtualMachineStartOptions())
            } catch let vzErr as NSError {
                // Use privacy: .public so we can read error details without sudo
                let desc = vzErr.localizedDescription
                let reason = vzErr.localizedFailureReason ?? "none"
                let userInfoStr = String(describing: vzErr.userInfo)
                logger.error("VZVirtualMachine.start failed: domain=\(vzErr.domain, privacy: .public) code=\(vzErr.code, privacy: .public) desc=\(desc, privacy: .public) reason=\(reason, privacy: .public) userInfo=\(userInfoStr, privacy: .public)")
                throw vzErr
            }

            // Stream VM serial console → log file for post-mortem debugging
            startConsoleLogging()

            // Wait for backend to be ready
            try await waitForBackend(timeout: 60)

            isRunning = true
            isBooting = false
            logger.info("VM started successfully")

        } catch {
            isBooting = false
            bootError = error.localizedDescription
            logger.error("Failed to start VM: \(error)")
            print("[VMManager] Failed to start VM: \(error)")
            throw error
        }
    }

    /// Stop the VM
    func stopVM() async throws {
        guard let vm = virtualMachine, isRunning else {
            print("[VMManager] VM not running")
            return
        }

        print("[VMManager] Stopping VM...")

        do {
            try await vm.stop()
            isRunning = false
            virtualMachine = nil
            print("[VMManager] VM stopped successfully")
        } catch {
            print("[VMManager] Error stopping VM: \(error)")
            throw error
        }
    }

    // MARK: - VM Configuration

    private func createVMConfiguration() throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()

        // CPU
        config.cpuCount = cpuCount

        // Memory
        config.memorySize = memorySize

        // Platform (generic Linux)
        let platform = VZGenericPlatformConfiguration()
        config.platform = platform

        // Boot loader — directly load the Linux kernel + initramfs extracted at image build time
        let bootloader = VZLinuxBootLoader(kernelURL: kernelPath)
        bootloader.initialRamdiskURL = initramfsPath
        // system.img is mounted read-only (ro); hvc0 = virtio console; vda = first virtio block disk
        // NOTE: debug_init=1 enables set -x in Alpine initramfs for verbose mdev/nlplug-findfs output
        bootloader.commandLine = "console=hvc0 root=/dev/vda ro"
        config.bootLoader = bootloader

        // Storage devices
        config.storageDevices = try createStorageDevices()

        // Network - NAT for internet access (TODO: replace with HTTP proxy on vsock)
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [networkDevice]

        // Socket device (vsock for IPC)
        let socketDevice = VZVirtioSocketDeviceConfiguration()
        config.socketDevices = [socketDevice]

        // Entropy (random number generator)
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        // Serial console — use VZFileSerialPortAttachment to write guest output to a log file.
        // Using stdin/stdout fails in bundled GUI apps (connected to OS logging, not real fds).
        // We only add the serial port if the file attachment succeeds; a nil attachment or a
        // VZVirtioConsoleDeviceSerialPortConfiguration with no attachment can cause VZError.internalError.
        FileManager.default.createFile(atPath: consoleLogPath.path, contents: nil)
        if let fileAttachment = try? VZFileSerialPortAttachment(url: consoleLogPath, append: false) {
            let serialConfig = VZVirtioConsoleDeviceSerialPortConfiguration()
            serialConfig.attachment = fileAttachment
            config.serialPorts = [serialConfig]
        } else {
            logger.warning("VZFileSerialPortAttachment failed — running without serial console logging")
        }

        // Validate configuration — any errors here surface BEFORE start()
        do {
            try config.validate()
            logger.info("VM config validated OK: \(config.cpuCount, privacy: .public) CPUs, \(config.memorySize / (1024*1024), privacy: .public)MB RAM")
        } catch let validateErr {
            logger.error("VM config validation FAILED: \(String(describing: validateErr), privacy: .public)")
            throw validateErr
        }

        return config
    }

    private func createStorageDevices() throws -> [VZStorageDeviceConfiguration] {
        var devices: [VZStorageDeviceConfiguration] = []

        // System disk (read-only)
        let systemAttachment = try VZDiskImageStorageDeviceAttachment(
            url: systemImagePath,
            readOnly: true
        )
        let systemDisk = VZVirtioBlockDeviceConfiguration(attachment: systemAttachment)
        devices.append(systemDisk)

        // Memory/data disk (read-write, encrypted)
        let mem0Attachment = try VZDiskImageStorageDeviceAttachment(
            url: mem0ImagePath,
            readOnly: false
        )
        let mem0Disk = VZVirtioBlockDeviceConfiguration(attachment: mem0Attachment)
        devices.append(mem0Disk)

        return devices
    }

    // MARK: - LUKS Key Management

    /// Get or generate LUKS encryption key from macOS Keychain
    func getLuksKey() throws -> String {
        // Try to load from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bowser.vm.luks",
            kSecAttrAccount as String: "mem0-encryption-key",
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        {
            return key
        }

        // Generate new key if not found
        let newKey = generateLuksKey()
        try saveLuksKeyToKeychain(newKey)
        return newKey
    }

    private func generateLuksKey() -> String {
        // Generate 256-bit (32 bytes) random key
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func saveLuksKeyToKeychain(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw VMError.invalidLuksKey
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bowser.vm.luks",
            kSecAttrAccount as String: "mem0-encryption-key",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess && status != errSecDuplicateItem {
            throw VMError.keychainError(status)
        }
    }

    // MARK: - mem0.img Creation

    private func createMem0Image() throws {
        print("[VMManager] Creating mem0.img...")

        let imageSizeGB: UInt64 = 5
        let imageSizeBytes = imageSizeGB * 1024 * 1024 * 1024

        // Create empty disk image
        FileManager.default.createFile(atPath: mem0ImagePath.path, contents: nil)

        // Resize to desired size
        let fileHandle = try FileHandle(forWritingTo: mem0ImagePath)
        try fileHandle.truncate(atOffset: imageSizeBytes)
        try fileHandle.close()

        print("[VMManager] Created mem0.img (\(imageSizeGB)GB)")

        // Note: LUKS formatting will be done inside the VM on first boot
    }

    // MARK: - Console Logging

    /// Log the path of the VM serial console output file.
    private func startConsoleLogging() {
        print("[VMManager] VM console log: \(consoleLogPath.path)")
    }

    // MARK: - Backend Health Check

    private func waitForBackend(timeout: TimeInterval = 30) async throws {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            // Try to connect to backend via vsock
            if await checkBackendHealth() {
                return
            }

            try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        }

        throw VMError.backendTimeout
    }

    private func checkBackendHealth() async -> Bool {
        do {
            let client = VSockClient()
            return try await client.healthCheck()
        } catch {
            return false
        }
    }

    // MARK: - VSock Connection

    /// Open a new vsock connection to the given port on the guest.
    /// The caller owns the returned connection and is responsible for closing it.
    func connectToPort(_ port: UInt32) async throws -> VZVirtioSocketConnection {
        guard let device = vsockDevice else {
            throw VMError.vmNotRunning
        }
        return try await device.connect(toPort: port)
    }

    // MARK: - API Key Injection

    /// Send API keys to VM via vsock
    func injectAPIKeys(_ keys: [String: String]) async throws {
        guard isRunning else {
            throw VMError.vmNotRunning
        }

        // This will be implemented using VSockClient
        print("[VMManager] Injecting API keys to VM: \(keys.keys)")
    }

    // MARK: - LUKS Key Management

    /// Returns the existing LUKS key or generates a new random 64-byte key.
    private func getOrCreateLuksKey() throws -> Data {
        if FileManager.default.fileExists(atPath: luksKeyPath.path) {
            let data = try Data(contentsOf: luksKeyPath)
            if !data.isEmpty { return data }
        }
        var keyBytes = [UInt8](repeating: 0, count: 64)
        guard SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes) == errSecSuccess else {
            throw VMError.invalidLuksKey
        }
        let keyData = Data(keyBytes)
        try keyData.write(to: luksKeyPath, options: [.atomic])
        logger.info("Generated new LUKS key and saved to \(self.luksKeyPath.lastPathComponent, privacy: .public)")
        return keyData
    }

    /// Connects to the VM's vsock port 9000 and sends the LUKS key.
    /// Retries for up to 30 s while the VM is still booting its vsock listener.
    private func sendLuksKeyToVM() async throws {
        let keyData = try getOrCreateLuksKey()
        logger.info("Sending LUKS key to VM (\(keyData.count, privacy: .public) bytes)…")

        guard let device = vsockDevice else {
            throw VMError.vmNotRunning
        }

        var lastError: Error?
        for attempt in 1...60 {
            do {
                let connection = try await device.connect(toPort: 9000)
                let writeHandle = FileHandle(
                    fileDescriptor: connection.fileDescriptor, closeOnDealloc: false)
                writeHandle.write(keyData)
                connection.close()
                logger.info("LUKS key sent successfully (attempt \(attempt, privacy: .public))")
                return
            } catch {
                lastError = error
                if attempt < 60 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        logger.error("Failed to send LUKS key after 30 s: \(String(describing: lastError), privacy: .public)")
        throw lastError ?? VMError.invalidLuksKey
    }
}

// MARK: - VZVirtualMachineDelegate

extension VMManager: VZVirtualMachineDelegate {
    nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        Task { @MainActor in
            print("[VMManager] Guest stopped")
            self.isRunning = false
        }
    }

    nonisolated func virtualMachine(
        _ virtualMachine: VZVirtualMachine, didStopWithError error: Error
    ) {
        Task { @MainActor in
            print("[VMManager] Guest stopped with error: \(error)")
            self.isRunning = false
            self.bootError = error.localizedDescription
        }
    }
}

// MARK: - Errors

enum VMError: LocalizedError {
    case systemImageNotFound
    case kernelNotFound
    case initramfsNotFound
    case vmNotRunning
    case backendTimeout
    case invalidLuksKey
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .systemImageNotFound:
            return "VM system image not found. Please download it first."
        case .kernelNotFound:
            return "VM kernel (vmlinuz) not found. Please rebuild the VM image."
        case .initramfsNotFound:
            return "VM initramfs not found. Please rebuild the VM image."
        case .vmNotRunning:
            return "VM is not running"
        case .backendTimeout:
            return "Backend failed to start within timeout"
        case .invalidLuksKey:
            return "Invalid LUKS encryption key"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
