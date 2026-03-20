// VMManager.swift
// Manages the lifecycle of the Alpine Linux VM running the Python backend

import Foundation
import Network
import Virtualization

/// Manages the Alpine Linux VM that runs the Python backend in production mode
@MainActor
class VMManager: NSObject, ObservableObject {
    static let shared = VMManager()

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

            print("[VMManager] Starting VM...")
            try await virtualMachine?.start()

            // Wait for backend to be ready
            try await waitForBackend()

            isRunning = true
            isBooting = false
            print("[VMManager] VM started successfully")

        } catch {
            isBooting = false
            bootError = error.localizedDescription
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

        // Boot loader (EFI)
        let bootloader = VZEFIBootLoader()
        let efiVariableStorePath = vmDirectory.appendingPathComponent("efi-vars.bin")

        // Create EFI variable store if needed
        if !FileManager.default.fileExists(atPath: efiVariableStorePath.path) {
            _ = try VZEFIVariableStore(creatingVariableStoreAt: efiVariableStorePath)
        }
        bootloader.variableStore = VZEFIVariableStore(url: efiVariableStorePath)
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

        // Serial console (for debugging)
        let serialConfig = VZVirtioConsoleDeviceSerialPortConfiguration()
        let serialPort = VZFileHandleSerialPortAttachment(
            fileHandleForReading: FileHandle.standardInput,
            fileHandleForWriting: FileHandle.standardOutput
        )
        serialConfig.attachment = serialPort
        config.serialPorts = [serialConfig]

        // Validate configuration
        try config.validate()

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
        // This will be implemented using VSockClient
        // For now, return true after a delay to simulate boot time
        return true
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
    case vmNotRunning
    case backendTimeout
    case invalidLuksKey
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .systemImageNotFound:
            return "VM system image not found. Please download it first."
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
