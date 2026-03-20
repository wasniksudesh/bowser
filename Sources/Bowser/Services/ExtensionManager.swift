// ExtensionManager.swift - Chrome Extension Management Service
// Manages loading, unloading, and tracking browser extensions

import AppKit
import CEFWrapper
import Foundation

/// Manages Chrome extensions in the browser
@Observable
@MainActor
final class ExtensionManager {

    // MARK: - Properties

    /// List of loaded extensions
    var extensions: [ExtensionInfo] = []

    /// Storage key for persisted extension paths
    private static let extensionPathsKey = "bowser.extensions.paths"

    /// Reference to BrowserState for opening tabs
    weak var browserState: BrowserState?

    // MARK: - Initialization

    init(browserState: BrowserState? = nil) {
        self.browserState = browserState
        setupCallbacks()
    }

    // MARK: - Public Methods

    /// Load an extension from a directory path
    /// - Parameter path: URL to the extension directory containing manifest.json
    func loadExtension(from path: URL) async {
        let pathString = path.path

        // Validate that manifest.json exists
        let manifestPath = path.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            print("[ExtensionManager] Error: manifest.json not found at \(manifestPath.path)")
            return
        }

        print("[ExtensionManager] Processing extension load: \(pathString)")

        // Parse and add to local list (off-thread)
        let info = await Task.detached {
            return self.parseExtensionManifest(path: pathString)
        }.value

        if let info = info {
            updateExtensionList(with: info)
        }

        // Call CEF to attempt dynamic load (this will trigger the "Restart required" log if not supported)
        cef_load_extension(pathString)

        // Persist the path for reload on next launch
        persistExtensionPath(pathString)
    }

    /// Unload an extension by ID
    /// - Parameter id: The extension ID to unload
    func unloadExtension(id: String) {
        print("[ExtensionManager] Unloading extension: \(id)")

        // Get the path before removing from list
        let extensionPath = extensions.first(where: { $0.id == id })?.path

        // Call CEF to unload
        cef_unload_extension(id)

        // Remove from extensions list
        extensions.removeAll { $0.id == id }

        // Remove from persisted paths
        if let path = extensionPath {
            removePersistedExtensionPath(path)
        }
    }

    /// Refresh the list of extensions from CEF
    func refreshExtensions() {
        print("[ExtensionManager] Refreshing extensions list")

        // Get extension info JSON from CEF
        guard let jsonCString = cef_get_extension_info_json() else {
            print("[ExtensionManager] Failed to get extension info")
            return
        }

        let jsonString = String(cString: jsonCString)
        cef_free_string(jsonCString)

        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("[ExtensionManager] Failed to convert JSON string to data")
            return
        }

        do {
            let decoder = JSONDecoder()
            let newExtensions = try decoder.decode([ExtensionInfo].self, from: jsonData)
            self.extensions = newExtensions
            print("[ExtensionManager] Loaded \(newExtensions.count) extensions")
        } catch {
            print("[ExtensionManager] Failed to decode extensions JSON: \(error)")
        }
    }

    /// Open the options page for an extension in a new tab
    /// - Parameter extension: The extension whose options page to open
    func openOptionsPage(for ext: ExtensionInfo) {
        guard let optionsUrl = ext.optionsUrl,
            let url = URL(string: optionsUrl)
        else {
            print("[ExtensionManager] Extension has no options page: \(ext.name)")
            return
        }

        print("[ExtensionManager] Opening options page: \(optionsUrl)")

        // Open in new tab via BrowserState
        browserState?.createTab(url: url)
    }

    /// Load all persisted extensions on app launch
    func loadPersistedExtensions() {
        let paths = getPersistedExtensionPaths()
        print("[ExtensionManager] Restoring \(paths.count) persisted extensions")

        Task.detached(priority: .userInitiated) {
            for path in paths {
                if let info = self.parseExtensionManifest(path: path) {
                    await MainActor.run {
                        self.updateExtensionList(with: info)
                    }
                }
            }
        }
        // Note: We do NOT call cef_load_extension here.
        // Extensions are loaded via command-line switches processed in C++ (SimpleApp::OnBeforeCommandLineProcessing).
    }

    // MARK: - Private Methods

    /// Setup CEF extension callbacks
    private func setupCallbacks() {
        // Register C callbacks that will be called from CEF
        // These are implemented in CEFExtensionBridge
        CEFExtensionBridge.registerCallbacks(manager: self)
    }

    /// Handle extension loaded callback from CEF
    func handleExtensionLoaded(extensionJSON: String) {
        print("[ExtensionManager] Extension loaded: \(extensionJSON)")

        // Parse the extension info
        guard let jsonData = extensionJSON.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            let extensionInfo = try decoder.decode(ExtensionInfo.self, from: jsonData)

            // Add to list if not already present
            if !extensions.contains(where: { $0.id == extensionInfo.id }) {
                extensions.append(extensionInfo)
            }
        } catch {
            print("[ExtensionManager] Failed to decode extension JSON: \(error)")
        }
    }

    /// Handle extension load failed callback from CEF
    func handleExtensionLoadFailed(path: String, errorCode: Int) {
        print("[ExtensionManager] Extension load failed: \(path), error: \(errorCode)")
        // Could show an alert to the user here
    }

    /// Handle extension unloaded callback from CEF
    func handleExtensionUnloaded(extensionId: String) {
        print("[ExtensionManager] Extension unloaded: \(extensionId)")
        extensions.removeAll { $0.id == extensionId }
    }

    // MARK: - Helper Methods

    private func updateExtensionList(with info: ExtensionInfo) {
        if let index = extensions.firstIndex(where: { $0.path == info.path }) {
            extensions[index] = info
        } else {
            extensions.append(info)
        }
        print("[ExtensionManager] Tracked extension: \(info.name) (\(info.version))")
    }

    nonisolated private func parseExtensionManifest(path: String) -> ExtensionInfo? {
        let url = URL(fileURLWithPath: path)
        let manifestUrl = url.appendingPathComponent("manifest.json")

        guard let data = try? Data(contentsOf: manifestUrl),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[ExtensionManager] Failed to parse manifest at \(manifestUrl.path)")
            return nil
        }

        let name = json["name"] as? String ?? "Unknown Extension"
        let version = json["version"] as? String ?? "0.0.0"
        let description = json["description"] as? String ?? ""

        var optionsPage = json["options_page"] as? String
        if optionsPage == nil, let optionsUi = json["options_ui"] as? [String: Any] {
            optionsPage = optionsUi["page"] as? String
        }

        // Use path as ID for local tracking
        let id = path

        return ExtensionInfo(
            id: id,
            name: name,
            version: version,
            description: description,
            path: path,
            optionsUrl: optionsPage,
            isEnabled: true
        )
    }

    // MARK: - Persistence

    private func persistExtensionPath(_ path: String) {
        var paths = getPersistedExtensionPaths()
        if !paths.contains(path) {
            paths.append(path)
            UserDefaults.standard.set(paths, forKey: Self.extensionPathsKey)
        }
    }

    private func removePersistedExtensionPath(_ path: String) {
        var paths = getPersistedExtensionPaths()
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: Self.extensionPathsKey)
    }

    private func getPersistedExtensionPaths() -> [String] {
        return UserDefaults.standard.stringArray(forKey: Self.extensionPathsKey) ?? []
    }
}

// MARK: - CEF Extension Bridge

/// Bridge between CEF C callbacks and Swift ExtensionManager
@MainActor
final class CEFExtensionBridge {

    fileprivate static weak var manager: ExtensionManager?

    /// Register callbacks with CEF
    static func registerCallbacks(manager: ExtensionManager) {
        self.manager = manager

        // Register C callbacks
        cef_register_extension_callbacks(
            extensionLoadedCallback,
            extensionLoadFailedCallback,
            extensionUnloadedCallback
        )
    }
}

// MARK: - C Callback Functions

/// C callback for extension loaded
private let extensionLoadedCallback: CefExtensionLoadedCallback = { jsonCString in
    guard let jsonCString = jsonCString else { return }
    let jsonString = String(cString: jsonCString)

    Task { @MainActor in
        CEFExtensionBridge.manager?.handleExtensionLoaded(extensionJSON: jsonString)
    }
}

/// C callback for extension load failed
private let extensionLoadFailedCallback: CefExtensionLoadFailedCallback = {
    pathCString, errorCode in
    let path = pathCString != nil ? String(cString: pathCString!) : ""

    Task { @MainActor in
        CEFExtensionBridge.manager?.handleExtensionLoadFailed(path: path, errorCode: Int(errorCode))
    }
}

/// C callback for extension unloaded
private let extensionUnloadedCallback: CefExtensionUnloadedCallback = { idCString in
    guard let idCString = idCString else { return }
    let extensionId = String(cString: idCString)

    Task { @MainActor in
        CEFExtensionBridge.manager?.handleExtensionUnloaded(extensionId: extensionId)
    }
}
