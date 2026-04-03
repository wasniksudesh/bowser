// FeatureFlagService.swift - Central feature flag configuration
// Edit Sources/Bowser/Config/feature_flags.json to toggle features.
// Falls back to all-enabled defaults if the file is missing or malformed.

import Foundation

// =============================================================================
// MARK: - Feature Flags
// =============================================================================

struct FeatureFlags: Codable, Sendable {
    /// When false, license verification is skipped and the app boots directly.
    let licenseCheckEnabled: Bool

    /// When true, the recording panel slides in over the browser while recording.
    /// When false, no panel is shown — recording still works and the note is saved
    /// and opened after stopping.
    let recordingPanelEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case licenseCheckEnabled  = "license_check_enabled"
        case recordingPanelEnabled = "recording_panel_enabled"
    }

    static let defaultFlags = FeatureFlags(licenseCheckEnabled: true, recordingPanelEnabled: false)
}

// =============================================================================
// MARK: - Feature Flag Service
// =============================================================================

final class FeatureFlagService: @unchecked Sendable {

    static let shared = FeatureFlagService()

    let flags: FeatureFlags

    private init() {
        // Bundle.module is the SPM-generated accessor for this target's resources.
        // Bundle.main does not contain the resources bundle, so using it causes
        // a silent fallback to defaultFlags (recordingPanelEnabled: false).
        guard
            let url = Bundle.module.url(forResource: "feature_flags", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FeatureFlags.self, from: data)
        else {
            print("[FeatureFlags] Could not load feature_flags.json — using safe defaults (all checks enabled)")
            self.flags = .defaultFlags
            return
        }
        self.flags = decoded
        print("[FeatureFlags] Loaded — licenseCheckEnabled: \(decoded.licenseCheckEnabled), recordingPanelEnabled: \(decoded.recordingPanelEnabled)")
    }
}
