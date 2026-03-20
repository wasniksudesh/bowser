// SettingsManager.swift - Central Settings Management
// Handles persistence and state for application settings
// Phase 1 implementation

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Settings Enums
// =============================================================================

enum StartupBehavior: String, CaseIterable, Codable {
  case newTab = "New Tab"
  case continueWhereLeftOff = "Continue where you left off"
  case specificPages = "Open specific pages"
}

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
  case google = "Google"
  case duckduckgo = "DuckDuckGo"
  case bing = "Bing"
  case brave = "Brave Search"
  case custom = "Custom"

  var id: String { rawValue }
}

enum CookiePolicy: String, CaseIterable, Codable, Identifiable {
  case allowAll = "Allow all cookies"
  case blockThirdParty = "Block third-party cookies"
  case blockAll = "Block all cookies"

  var id: String { rawValue }
}

enum PermissionStatus: String, CaseIterable, Codable, Identifiable {
  case ask = "Ask"
  case allow = "Allow"
  case block = "Block"

  var id: String { rawValue }
}

enum AIProvider: String, CaseIterable, Codable, Identifiable {
  case openai = "OpenAI"
  case anthropic = "Anthropic"
  case local = "Local"

  var id: String { rawValue }
}

// =============================================================================
// MARK: - Settings Manager
// =============================================================================

/// Central manager for application settings
/// Persists values to UserDefaults and notifies observers
@Observable
@MainActor
final class SettingsManager {

  static let shared = SettingsManager()

  // MARK: - Storage Keys

  private enum Keys {
    // General
    static let onStartup = "bowser.settings.onStartup"
    static let downloadLocation = "bowser.settings.downloadLocation"
    static let askDownloadSave = "bowser.settings.askDownloadSave"

    // Search
    static let searchEngine = "bowser.settings.searchEngine"
    static let customSearchUrl = "bowser.settings.customSearchUrl"
    static let showSearchSuggestions = "bowser.settings.showSearchSuggestions"
    static let historyMaxItems = "bowser.settings.historyMaxItems"

    // Privacy
    static let cookiePolicy = "bowser.settings.cookiePolicy"
    static let cameraPermission = "bowser.settings.permission.camera"
    static let microphonePermission = "bowser.settings.permission.microphone"
    static let locationPermission = "bowser.settings.permission.location"
    static let notificationsPermission = "bowser.settings.permission.notifications"
    static let popupsPermission = "bowser.settings.permission.popups"
    static let redactorEnabled = "bowser.settings.redactorEnabled"

    // AI
    static let aiProvider = "bowser.settings.aiProvider"
    static let aiModel = "bowser.settings.aiModel"
    static let aiApiKey = "bowser.settings.aiApiKey"
    static let autoUrlEnabled = "bowser.settings.autoUrlEnabled"
    static let autoUrlTrigger = "bowser.settings.autoUrlTrigger"
    static let autoUrlFallback = "bowser.settings.autoUrlFallback"
  }

  // MARK: - General Settings

  var onStartup: StartupBehavior {
    didSet { save(onStartup.rawValue, key: Keys.onStartup) }
  }

  var downloadLocation: String {
    didSet { save(downloadLocation, key: Keys.downloadLocation) }
  }

  var askDownloadSave: Bool {
    didSet { save(askDownloadSave, key: Keys.askDownloadSave) }
  }

  // MARK: - Search Settings

  var searchEngine: SearchEngine {
    didSet { save(searchEngine.rawValue, key: Keys.searchEngine) }
  }

  var customSearchUrl: String {
    didSet { save(customSearchUrl, key: Keys.customSearchUrl) }
  }

  var showSearchSuggestions: Bool {
    didSet { save(showSearchSuggestions, key: Keys.showSearchSuggestions) }
  }

  var historyMaxItems: Int {
    didSet {
      save(historyMaxItems, key: Keys.historyMaxItems)
      SearchHistoryStore.shared.maxHistoryItems = historyMaxItems
    }
  }

  // MARK: - Privacy Settings

  var cookiePolicy: CookiePolicy {
    didSet { save(cookiePolicy.rawValue, key: Keys.cookiePolicy) }
  }

  var cameraPermission: PermissionStatus {
    didSet { save(cameraPermission.rawValue, key: Keys.cameraPermission) }
  }

  @MainActor
  func clearBrowsingData() {
    CEFBridge.shared.clearAllCookies()
    // Future: Clear cache and other data when API is available
  }

  var microphonePermission: PermissionStatus {
    didSet { save(microphonePermission.rawValue, key: Keys.microphonePermission) }
  }

  var locationPermission: PermissionStatus {
    didSet { save(locationPermission.rawValue, key: Keys.locationPermission) }
  }

  var notificationsPermission: PermissionStatus {
    didSet { save(notificationsPermission.rawValue, key: Keys.notificationsPermission) }
  }

  var popupsPermission: PermissionStatus {
    didSet { save(popupsPermission.rawValue, key: Keys.popupsPermission) }
  }

  var redactorEnabled: Bool {
    didSet { save(redactorEnabled, key: Keys.redactorEnabled) }
  }

  // MARK: - AI Settings

  var aiProvider: AIProvider {
    didSet { save(aiProvider.rawValue, key: Keys.aiProvider) }
  }

  var aiModel: String {
    didSet { save(aiModel, key: Keys.aiModel) }
  }

  var aiApiKey: String {
    didSet { save(aiApiKey, key: Keys.aiApiKey) }
  }

  var autoUrlEnabled: Bool {
    didSet { save(autoUrlEnabled, key: Keys.autoUrlEnabled) }
  }

  var autoUrlTrigger: String {
    didSet { save(autoUrlTrigger, key: Keys.autoUrlTrigger) }
  }

  var autoUrlFallback: Bool {
    didSet { save(autoUrlFallback, key: Keys.autoUrlFallback) }
  }

  // MARK: - Initialization

  init() {
    // Load defaults
    let defaults = UserDefaults.standard

    // General
    if let startupRaw = defaults.string(forKey: Keys.onStartup),
      let startup = StartupBehavior(rawValue: startupRaw)
    {
      self.onStartup = startup
    } else {
      self.onStartup = .newTab
    }

    self.downloadLocation = defaults.string(forKey: Keys.downloadLocation) ?? "~/Downloads"
    self.askDownloadSave = defaults.bool(forKey: Keys.askDownloadSave)

    // Search
    if let engineRaw = defaults.string(forKey: Keys.searchEngine),
      let engine = SearchEngine(rawValue: engineRaw)
    {
      self.searchEngine = engine
    } else {
      self.searchEngine = .google
    }
    self.customSearchUrl =
      defaults.string(forKey: Keys.customSearchUrl) ?? "https://www.google.com/search?q=%s"
    self.showSearchSuggestions =
      defaults.object(forKey: Keys.showSearchSuggestions) as? Bool ?? true

    let loadedHistoryMax = defaults.integer(forKey: Keys.historyMaxItems)
    self.historyMaxItems = loadedHistoryMax > 0 ? loadedHistoryMax : 50

    // Privacy
    if let cookieRaw = defaults.string(forKey: Keys.cookiePolicy),
      let policy = CookiePolicy(rawValue: cookieRaw)
    {
      self.cookiePolicy = policy
    } else {
      self.cookiePolicy = .allowAll
    }

    self.cameraPermission =
      PermissionStatus(rawValue: defaults.string(forKey: Keys.cameraPermission) ?? "") ?? .ask
    self.microphonePermission =
      PermissionStatus(rawValue: defaults.string(forKey: Keys.microphonePermission) ?? "") ?? .ask
    self.locationPermission =
      PermissionStatus(rawValue: defaults.string(forKey: Keys.locationPermission) ?? "") ?? .ask
    self.notificationsPermission =
      PermissionStatus(rawValue: defaults.string(forKey: Keys.notificationsPermission) ?? "")
      ?? .ask
    self.popupsPermission =
      PermissionStatus(rawValue: defaults.string(forKey: Keys.popupsPermission) ?? "") ?? .block
    
    self.redactorEnabled = defaults.object(forKey: Keys.redactorEnabled) as? Bool ?? false

    // AI
    if let providerRaw = defaults.string(forKey: Keys.aiProvider),
      let provider = AIProvider(rawValue: providerRaw)
    {
      self.aiProvider = provider
    } else {
      self.aiProvider = .openai
    }

    self.aiModel = defaults.string(forKey: Keys.aiModel) ?? "gpt-4o"
    self.aiApiKey = defaults.string(forKey: Keys.aiApiKey) ?? ""
    self.autoUrlEnabled = defaults.object(forKey: Keys.autoUrlEnabled) as? Bool ?? true
    self.autoUrlTrigger = defaults.string(forKey: Keys.autoUrlTrigger) ?? "/autourl"
    self.autoUrlFallback = defaults.object(forKey: Keys.autoUrlFallback) as? Bool ?? true

    // Sync history limits (deferred until after initialization)
    Task {
      SearchHistoryStore.shared.maxHistoryItems = self.historyMaxItems
    }
  }

  // MARK: - Persistence Helper

  private func save(_ value: Any, key: String) {
    UserDefaults.standard.set(value, forKey: key)
  }

  /// Construct a search URL for a given query based on selected engine
  func searchURL(for query: String) -> URL {
    let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

    let urlString: String
    switch searchEngine {
    case .google:
      urlString = "https://www.google.com/search?q=\(encodedQuery)"
    case .duckduckgo:
      urlString = "https://duckduckgo.com/?q=\(encodedQuery)"
    case .bing:
      urlString = "https://www.bing.com/search?q=\(encodedQuery)"
    case .brave:
      urlString = "https://search.brave.com/search?q=\(encodedQuery)"
    case .custom:
      urlString = customSearchUrl.replacingOccurrences(of: "%s", with: encodedQuery)
    }

    return URL(string: urlString) ?? URL(string: "https://www.google.com/search?q=\(encodedQuery)")!
  }

  /// Resolve input text to a URL, handling AutoURL triggers and search engine fallbacks
  func resolveInput(for input: String) async -> (url: URL, isAutoURL: Bool) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return (URL(string: "https://www.google.com")!, false)
    }

    // 1. Check for AutoURL trigger if enabled
    if autoUrlEnabled {
      let trigger = autoUrlTrigger
      if trimmed.hasPrefix(trigger) {
        let query = String(trimmed.dropFirst(trigger.count)).trimmingCharacters(
          in: .whitespacesAndNewlines)
        if !query.isEmpty {
          do {
            let resolved = try await AIService.shared.resolveURL(query: query, model: aiModel)
            if let url = URL(string: resolved) {
              return (url, true)
            }
          } catch {
            print("[SettingsManager] AutoURL resolution failed: \(error.localizedDescription)")
          }
        }
      }
    }

    // 2. Heuristic for direct URL
    if looksLikeURL(trimmed) {
      if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        || trimmed.hasPrefix("file://") || trimmed.hasPrefix("about:")
        || trimmed.hasPrefix("localhost")
      {
        if let url = URL(string: trimmed) {
          return (url, false)
        }
      } else {
        if let url = URL(string: "https://\(trimmed)") {
          return (url, false)
        }
      }
    }

    // 3. Fallback to search
    return (searchURL(for: trimmed), false)
  }

  private func looksLikeURL(_ input: String) -> Bool {
    // Contains no spaces and has a dot (domain-like)
    if !input.contains(" ") && input.contains(".") {
      return true
    }
    // Starts with common schemes
    let lowerSub = input.lowercased()
    if lowerSub.hasPrefix("http://") || lowerSub.hasPrefix("https://")
      || lowerSub.hasPrefix("file://") || lowerSub.hasPrefix("about:")
      || lowerSub.hasPrefix("localhost")
    {
      return true
    }
    return false
  }
}
