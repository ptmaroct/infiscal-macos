import Foundation
import LocalAuthentication

@MainActor
final class TouchIDService {
    static let shared = TouchIDService()

    private static let lastAuthKey = "infisical_touchid_last_auth"

    /// Whether the device supports biometric authentication
    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Whether Touch ID is enabled in settings AND the device actually supports
    /// it AND the timeout has elapsed. Hardware check first so a user who
    /// enables Touch ID on one Mac and migrates to a Mac without biometrics
    /// doesn't get locked out.
    var requiresAuthentication: Bool {
        guard isAvailable else { return false }
        let settings = TouchIDSettings.load()
        guard settings.isEnabled else { return false }

        let timeout = settings.timeoutInterval
        // 0 means require every time
        guard timeout > 0 else { return true }

        let lastAuth = UserDefaults.standard.double(forKey: Self.lastAuthKey)
        guard lastAuth > 0 else { return true }

        let elapsed = Date().timeIntervalSince1970 - lastAuth
        return elapsed >= timeout
    }

    /// Authenticate with Touch ID. Returns true on success, false if the
    /// device has no biometric hardware or the user cancels.
    func authenticate() async -> Bool {
        guard isAvailable else { return false }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access your secrets"
            )
            if success {
                recordSuccessfulAuth()
            }
            return success
        } catch {
            return false
        }
    }

    /// Record the current time as the last successful authentication
    func recordSuccessfulAuth() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastAuthKey)
    }

    /// Clear the last auth timestamp (forces re-authentication)
    func clearAuth() {
        UserDefaults.standard.removeObject(forKey: Self.lastAuthKey)
    }
}

// MARK: - Touch ID Settings

struct TouchIDSettings: Codable {
    var isEnabled: Bool
    var timeoutPreset: TimeoutPreset

    static let `default` = TouchIDSettings(isEnabled: false, timeoutPreset: .fifteenMinutes)
    private static let userDefaultsKey = "infisical_touchid_settings"

    /// Timeout interval in seconds
    var timeoutInterval: TimeInterval {
        timeoutPreset.seconds
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func load() -> TouchIDSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(TouchIDSettings.self, from: data) else {
            return .default
        }
        return settings
    }
}

// MARK: - Timeout Presets

enum TimeoutPreset: String, Codable, CaseIterable, Identifiable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case fourHours
    case eightHours
    case oneDay

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .immediately: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .oneHour: return 3600
        case .fourHours: return 14400
        case .eightHours: return 28800
        case .oneDay: return 86400
        }
    }

    var displayName: String {
        switch self {
        case .immediately: return "Immediately"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .thirtyMinutes: return "After 30 minutes"
        case .oneHour: return "After 1 hour"
        case .fourHours: return "After 4 hours"
        case .eightHours: return "After 8 hours"
        case .oneDay: return "After 1 day"
        }
    }
}
