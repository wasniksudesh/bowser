// MCPBridge.swift
// Bridges vsock communication from VM to Docker MCP Gateway on macOS host

import Foundation

/// Bridges vsock requests from VM to Docker MCP Gateway on host
actor MCPBridge {

    // MARK: - Properties

    private var isRunning = false
    private var bridgeTask: Task<Void, Error>?

    /// Port for vsock listener (VM connects to this)
    private let vsockPort: UInt32 = 9002

    // MARK: - Lifecycle

    /// Start the MCP bridge
    func start() {
        guard !isRunning else {
            print("[MCPBridge] Already running")
            return
        }

        isRunning = true

        bridgeTask = Task {
            await runBridge()
        }

        print("[MCPBridge] Started")
    }

    /// Stop the MCP bridge
    func stop() {
        guard isRunning else {
            print("[MCPBridge] Not running")
            return
        }

        isRunning = false
        bridgeTask?.cancel()
        bridgeTask = nil

        print("[MCPBridge] Stopped")
    }

    // MARK: - Bridge Logic

    private func runBridge() async {
        print("[MCPBridge] Listening for MCP requests from VM...")

        // In production, this would:
        // 1. Listen on vsock port 9002
        // 2. Receive JSON-RPC requests from VM
        // 3. Forward to Docker MCP Gateway via stdio
        // 4. Return responses back to VM

        // For now, this is a placeholder that would be implemented
        // when MCP integration is needed

        while isRunning {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: - Docker MCP Gateway Interface

    /// Call Docker MCP Gateway tool
    private func callDockerMCP(tool: String, arguments: [String: Any]) async throws -> [String: Any]
    {
        // Create process to run docker mcp gateway
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
        process.arguments = ["mcp", "gateway", "run"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Start process
        try process.run()

        // Send JSON-RPC request
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": tool,
                "arguments": arguments,
            ],
        ]

        let requestData = try JSONSerialization.data(withJSONObject: request)
        inputPipe.fileHandleForWriting.write(requestData)
        inputPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
        try inputPipe.fileHandleForWriting.close()

        // Read response
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        // Wait for process to complete
        process.waitUntilExit()

        // Parse response
        guard let response = try JSONSerialization.jsonObject(with: outputData) as? [String: Any]
        else {
            throw MCPBridgeError.invalidResponse
        }

        if let error = response["error"] as? [String: Any] {
            throw MCPBridgeError.toolError(error["message"] as? String ?? "Unknown error")
        }

        guard let result = response["result"] as? [String: Any] else {
            throw MCPBridgeError.invalidResponse
        }

        return result
    }
}

// MARK: - Errors

enum MCPBridgeError: LocalizedError {
    case invalidResponse
    case toolError(String)
    case bridgeNotRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Docker MCP Gateway"
        case .toolError(let message):
            return "MCP tool error: \(message)"
        case .bridgeNotRunning:
            return "MCP bridge is not running"
        }
    }
}
