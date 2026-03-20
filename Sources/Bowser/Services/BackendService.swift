// BackendService.swift
// Manages backend connection - either direct TCP (dev) or VM (production)

import Foundation

/// Runtime environment mode
enum BackendMode {
    case development  // Direct TCP connection to Python process on macOS
    case production   // VM-based backend with vsock
}

/// Backend service that handles both dev and production modes
@MainActor
class BackendService: ObservableObject {
    
    static let shared = BackendService()
    
    // MARK: - Properties
    
    @Published var isConnected = false
    @Published var mode: BackendMode
    @Published var connectionError: String?
    
    private var vmManager: VMManager?
    private var vsockClient: VSockClient?
    
    /// Base URL for dev mode
    private let devBaseURL = "http://localhost:8765"
    
    // MARK: - Initialization
    
    private init() {
        // Detect mode based on build configuration
        #if DEBUG
        self.mode = .development
        #else
        // Check if running from .app bundle
        if Bundle.main.bundlePath.hasSuffix(".app") {
            self.mode = .production
        } else {
            self.mode = .development
        }
        #endif
        
        print("[BackendService] Mode: \(mode)")
    }
    
    // MARK: - Lifecycle
    
    /// Start the backend service
    func start() async throws {
        switch mode {
        case .development:
            try await startDevMode()
        case .production:
            try await startProductionMode()
        }
    }
    
    /// Stop the backend service
    func stop() async throws {
        switch mode {
        case .development:
            // Dev mode: Python process runs independently
            isConnected = false
            
        case .production:
            // Production mode: Stop VM
            if let vm = vmManager {
                try await vm.stopVM()
            }
            isConnected = false
        }
    }
    
    // MARK: - Dev Mode
    
    private func startDevMode() async throws {
        print("[BackendService] Starting in development mode...")
        
        // Wait for backend to be available
        var attempts = 0
        let maxAttempts = 60 // 30 seconds
        
        while attempts < maxAttempts {
            if await checkDevBackendHealth() {
                isConnected = true
                print("[BackendService] Connected to dev backend")
                
                // Auto-configure if credentials are available
                await autoConfigureIfNeeded()
                
                return
            }
            
            attempts += 1
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
        
        connectionError = "Dev backend not available. Please start it with: ./run_dev.sh"
        throw BackendError.connectionFailed
    }
    
    private func checkDevBackendHealth() async -> Bool {
        guard let url = URL(string: "\(devBaseURL)/health") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Backend not ready yet
        }
        
        return false
    }
    
    /// Auto-configure backend with stored credentials if available
    private func autoConfigureIfNeeded() async {
        let settings = SettingsManager.shared
        
        // Check if API key is configured
        guard !settings.aiApiKey.isEmpty else {
            print("[BackendService] No API key stored, skipping auto-configuration")
            return
        }
        
        // Get provider and model
        let provider = settings.aiProvider.rawValue
        let model = settings.aiModel
        let apiKey = settings.aiApiKey
        
        print("[BackendService] Auto-configuring with stored credentials (provider: \(provider))...")
        
        do {
            try await configure(provider: provider, apiKey: apiKey, model: model)
            print("[BackendService] Successfully auto-configured AI services")
        } catch {
            print("[BackendService] Failed to auto-configure: \(error.localizedDescription)")
            // Don't throw - this is optional initialization
        }
    }
    
    // MARK: - Production Mode (VM)
    
    private func startProductionMode() async throws {
        print("[BackendService] Starting in production mode (VM)...")
        
        // Initialize VM manager if needed
        if vmManager == nil {
            vmManager = VMManager.shared
        }
        
        guard let vm = vmManager else {
            throw BackendError.vmInitFailed
        }
        
        // Check if VM image needs download
        let bootstrap = VMBootstrap()
        if bootstrap.needsDownload() {
            print("[BackendService] VM image needs download...")
            // This would trigger a UI prompt in the app
            throw BackendError.vmImageMissing
        }
        
        // Start VM
        try await vm.startVM()
        
        // Create vsock client
        // Note: In production, we'd get the actual CID from the VM
        let cid: UInt32 = 3 // Guest CID (typically 3)
        vsockClient = VSockClient(cid: cid)
        
        // Verify connection
        if let client = vsockClient, await (try? client.healthCheck()) == true {
            isConnected = true
            print("[BackendService] Connected to VM backend")
            
            // Auto-configure if credentials are available
            await autoConfigureIfNeeded()
        } else {
            throw BackendError.connectionFailed
        }
    }
    
    // MARK: - API Methods
    
    /// Execute AI task (works in both modes)
    func executeTask(task: String, context: [String: String]? = nil) async throws -> TaskResponse {
        guard isConnected else {
            throw BackendError.notConnected
        }
        
        switch mode {
        case .development:
            return try await executeTaskDev(task: task, context: context)
        case .production:
            return try await executeTaskVM(task: task, context: context)
        }
    }
    
    private func executeTaskDev(task: String, context: [String: String]?) async throws -> TaskResponse {
        struct TaskRequest: Codable {
            let task: String
            let context: [String: String]?
        }
        
        let url = URL(string: "\(devBaseURL)/api/ai/execute")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = TaskRequest(task: task, context: context)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TaskResponse.self, from: data)
    }
    
    private func executeTaskVM(task: String, context: [String: String]?) async throws -> TaskResponse {
        guard let client = vsockClient else {
            throw BackendError.notConnected
        }
        
        return try await client.executeTask(task: task, context: context)
    }
    
    /// Configure AI service
    func configure(provider: String, apiKey: String, model: String?) async throws {
        guard isConnected else {
            throw BackendError.notConnected
        }
        
        switch mode {
        case .development:
            try await configureDev(provider: provider, apiKey: apiKey, model: model)
        case .production:
            try await configureVM(provider: provider, apiKey: apiKey, model: model)
        }
    }
    
    private func configureDev(provider: String, apiKey: String, model: String?) async throws {
        struct ConfigRequest: Codable {
            let provider: String
            let api_key: String
            let model: String?
        }
        
        let url = URL(string: "\(devBaseURL)/api/ai/configure")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ConfigRequest(provider: provider, api_key: apiKey, model: model)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, _) = try await URLSession.shared.data(for: request)
    }
    
    private func configureVM(provider: String, apiKey: String, model: String?) async throws {
        guard let client = vsockClient else {
            throw BackendError.notConnected
        }
        
        try await client.configure(provider: provider, apiKey: apiKey, model: model)
    }
}

// MARK: - Errors

enum BackendError: LocalizedError {
    case notConnected
    case connectionFailed
    case vmInitFailed
    case vmImageMissing
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Backend not connected"
        case .connectionFailed:
            return "Failed to connect to backend"
        case .vmInitFailed:
            return "Failed to initialize VM"
        case .vmImageMissing:
            return "VM image not found. Please download it first."
        }
    }
}
