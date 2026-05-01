import Foundation

/// User preferences for local secret-expiry notifications.
/// Stored in UserDefaults under `kubera_expiry_notifications`.
struct ExpiryNotificationSettings: Codable {
    var enabled: Bool
    var notify7Days: Bool
    var notify1Day: Bool
    var notifyAtExpiry: Bool

    static let `default` = ExpiryNotificationSettings(
        enabled: false,
        notify7Days: true,
        notify1Day: true,
        notifyAtExpiry: true
    )

    private static let userDefaultsKey = "kubera_expiry_notifications"

    /// Whether at least one offset is active. If `enabled == false`, returns false.
    var hasAnyActiveOffset: Bool {
        enabled && (notify7Days || notify1Day || notifyAtExpiry)
    }

    /// Active offsets in days-before-expiry. 0 = at expiry day.
    var activeOffsetsInDays: [Int] {
        guard enabled else { return [] }
        var out: [Int] = []
        if notify7Days { out.append(7) }
        if notify1Day { out.append(1) }
        if notifyAtExpiry { out.append(0) }
        return out
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func load() -> ExpiryNotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(ExpiryNotificationSettings.self, from: data) else {
            return .default
        }
        return settings
    }
}
