// LicenseService.swift - License verification against AWS Lambda
// Ed25519 signed-response protocol with Keychain persistence

import CryptoKit
import Foundation
import IOKit

// =============================================================================
// MARK: - License Types
// =============================================================================

enum LicenseCheckState: Sendable {
    case checking
    case needsLicense
    case verified
}

enum LicenseError: Error, LocalizedError {
    case invalidKeyFormat
    case networkError(String)
    case signatureInvalid
    case nonceMismatch
    case licenseInvalid(reason: String, message: String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidKeyFormat:
            return "Invalid license key format. Expected: ORGID-XXXX-XXXX-XXXX"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .signatureInvalid:
            return "Server response failed signature verification."
        case .nonceMismatch:
            return "Server response nonce mismatch — possible replay attack."
        case .licenseInvalid(_, let message):
            return message
        case .decodingError(let msg):
            return "Failed to decode server response: \(msg)"
        }
    }
}

struct LicensePayload: Codable, Sendable {
    let valid: Bool
    let orgId: String?
    let expiry: Int?
    let nonce: String?
    let issuedAt: Int?
    let machineMatch: Bool?
    let reason: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case valid
        case orgId = "org_id"
        case expiry
        case nonce
        case issuedAt = "issued_at"
        case machineMatch = "machine_match"
        case reason
        case message
    }
}

struct LicenseResponse: Codable, Sendable {
    let payload: String
    let signature: String
}

// =============================================================================
// MARK: - License Service
// =============================================================================

@MainActor
final class LicenseService {

    static let shared = LicenseService()

    // MARK: - Configuration

    private let lambdaURL = "https://f2kanwumt4wz4xrxfistvimi6y0ndplb.lambda-url.us-west-2.on.aws/"

    // Replace with your actual Ed25519 public key bytes (32 bytes, hex-encoded).
    // Generate with: openssl pkey -in public.pem -pubin -outform DER | tail -c 32 | xxd -p
    private let publicKeyHex = "38b64bdd4a9c7cf5bc65acb8ad852450cde30c7e706986c93504f04401929d21"

    private let gracePeriodSeconds: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    // MARK: - Keychain Constants

    private enum KeychainKey {
        static let service = "com.bowser.license"
        static let licenseKey = "license-key"
        static let lastVerified = "last-verified"
        static let cachedExpiry = "cached-expiry"
    }

    // MARK: - Public API

    /// Full verification flow: call Lambda, verify signature, return decoded payload.
    func verifyLicense(key: String) async throws -> LicensePayload {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parts = trimmed.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw LicenseError.invalidKeyFormat
        }

        let nonce = UUID().uuidString
        let machineId = getMachineID() ?? "unknown"

        let requestBody: [String: String] = [
            "license_key": trimmed,
            "machine_id": machineId,
            "nonce": nonce,
        ]

        guard let url = URL(string: lambdaURL) else {
            throw LicenseError.networkError("Invalid Lambda URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.networkError(error.localizedDescription)
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LicenseError.networkError("HTTP \((urlResponse as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let response = try JSONDecoder().decode(LicenseResponse.self, from: data)

        guard let payloadData = Data(base64Encoded: response.payload),
              let signatureData = Data(base64Encoded: response.signature) else {
            throw LicenseError.decodingError("Invalid base64 in response")
        }

        try verifySignature(payloadBytes: payloadData, signatureBytes: signatureData)

        let payload = try JSONDecoder().decode(LicensePayload.self, from: payloadData)

        if payload.valid {
            guard payload.nonce == nonce else {
                throw LicenseError.nonceMismatch
            }
        }

        if !payload.valid {
            throw LicenseError.licenseInvalid(
                reason: payload.reason ?? "unknown",
                message: payload.message ?? "License validation failed."
            )
        }

        storeLicenseKey(trimmed)
        storeLastVerified(Date())
        if let expiry = payload.expiry {
            storeCachedExpiry(expiry)
        }

        return payload
    }

    /// Check the stored license in background. Returns true if still valid.
    func checkStoredLicense() async -> Bool {
        guard let key = loadLicenseKey() else { return false }

        do {
            //TODO-License
            // _ = try await verifyLicense(key: key)
            return true
        } catch is LicenseError {
            return isWithinGracePeriod()
        } catch {
            return isWithinGracePeriod()
        }
    }

    /// Determine initial state on startup without blocking.
    func initialCheckState() async -> LicenseCheckState {
        // guard let key = loadLicenseKey() else {
        //     return .needsLicense
        // }

        do {
            //TODO-License-Enable
            // _ = try await verifyLicense(key: key)
            return .verified
        } catch {
            if isWithinGracePeriod() {
                return .verified
            }
            // return .needsLicense
            return .verified
        }
    }

    /// Remove stored license data (for logout / re-entry).
    func clearLicense() {
        deleteKeychainItem(account: KeychainKey.licenseKey)
        deleteKeychainItem(account: KeychainKey.lastVerified)
        deleteKeychainItem(account: KeychainKey.cachedExpiry)
    }

    // MARK: - Signature Verification

    private func verifySignature(payloadBytes: Data, signatureBytes: Data) throws {
        let pubKeyData = Data(hexString: publicKeyHex)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)

        guard publicKey.isValidSignature(signatureBytes, for: payloadBytes) else {
            throw LicenseError.signatureInvalid
        }
    }

    // MARK: - Machine ID

    nonisolated func getMachineID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        let uuidCF = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )
        return uuidCF?.takeRetainedValue() as? String
    }

    // MARK: - Grace Period

    private func isWithinGracePeriod() -> Bool {
        guard let lastVerified = loadLastVerified(),
              let cachedExpiry = loadCachedExpiry() else {
            return false
        }

        let now = Date()
        let graceDeadline = lastVerified.addingTimeInterval(gracePeriodSeconds)
        let expiryDate = Date(timeIntervalSince1970: TimeInterval(cachedExpiry))

        return now < graceDeadline && now < expiryDate
    }

    // MARK: - Keychain Helpers

    func loadLicenseKey() -> String? {
        return loadKeychainString(account: KeychainKey.licenseKey)
    }

    private func storeLicenseKey(_ key: String) {
        saveKeychainString(key, account: KeychainKey.licenseKey)
    }

    private func storeLastVerified(_ date: Date) {
        let timestamp = String(Int(date.timeIntervalSince1970))
        saveKeychainString(timestamp, account: KeychainKey.lastVerified)
    }

    private func loadLastVerified() -> Date? {
        guard let str = loadKeychainString(account: KeychainKey.lastVerified),
              let ts = Int(str) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    private func storeCachedExpiry(_ epoch: Int) {
        saveKeychainString(String(epoch), account: KeychainKey.cachedExpiry)
    }

    private func loadCachedExpiry() -> Int? {
        guard let str = loadKeychainString(account: KeychainKey.cachedExpiry) else { return nil }
        return Int(str)
    }

    private func loadKeychainString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func saveKeychainString(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        deleteKeychainItem(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// =============================================================================
// MARK: - Data Hex Initializer
// =============================================================================

private extension Data {
    init(hexString: String) {
        self.init()
        var hex = hexString
        while hex.count >= 2 {
            let pair = String(hex.prefix(2))
            hex = String(hex.dropFirst(2))
            if let byte = UInt8(pair, radix: 16) {
                append(byte)
            }
        }
    }
}
