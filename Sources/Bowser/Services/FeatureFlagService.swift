// FeatureFlagService.swift - Central feature flag configuration
// Edit Sources/Bowser/Config/feature_flags.json to toggle features.
// Falls back to all-enabled defaults if the file is missing or malformed.

import Foundation

// =============================================================================
// MARK: - Feature Flags
// =============================================================================

struct FeatureFlags: Codable, Sendable {
    /// When false, license verification is skipped and the app boots directly.
    /// Set to true before shipping a release build.
    let licenseCheckEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case licenseCheckEnabled = "license_check_enabled"
    }

    static let defaultFlags = FeatureFlags(licenseCheckEnabled: true)
}

// =============================================================================
// MARK: - Feature Flag Service
// =============================================================================

final class FeatureFlagService: @unchecked Sendable {

    static let shared = FeatureFlagService()

    let flags: FeatureFlags

    private init() {
        guard
            let url = Bundle.main.url(forResource: "feature_flags", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FeatureFlags.self, from: data)
        else {
            print("[FeatureFlags] Could not load feature_flags.json — using safe defaults (all checks enabled)")
            self.flags = .defaultFlags
            return
        }
        self.flags = decoded
        print("[FeatureFlags] Loaded — licenseCheckEnabled: \(decoded.licenseCheckEnabled)")
    }
}
