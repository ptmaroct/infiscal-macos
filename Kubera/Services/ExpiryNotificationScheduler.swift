import Foundation
import UserNotifications
import AppKit

/// Schedules local macOS banners ahead of secret expiry dates.
///
/// Notifications are deterministic per `(secretId, environment, offsetInDays)`:
/// `kubera.expiry.<id>.<env>.<offset>`. That lets `reconcile(...)` cheaply
/// dedupe against `getPendingNotificationRequests` and remove stale entries.
///
/// All scheduling happens on the main actor so we can safely read settings and
/// touch UNUserNotificationCenter without races.
@MainActor
final class ExpiryNotificationScheduler: NSObject {
    static let shared = ExpiryNotificationScheduler()

    private let identifierPrefix = "kubera.expiry."
    private var didRequestAuth = false

    private override init() {
        super.init()
    }

    /// Install ourselves as the notification delegate so taps can open Service URLs.
    func installDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask for notification permission once per launch. Safe to call many times.
    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Cancel all pending kubera-expiry notifications (e.g. when settings disabled).
    func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [identifierPrefix] requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    /// Cancel the three-offset set for a specific (secret, env).
    func cancel(secretId: String, environment: String) {
        let ids = [7, 1, 0].map { identifier(secretId: secretId, environment: environment, offset: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Reconcile pending notifications to match the given secret list for an environment.
    /// - Adds new requests for secrets that have an expiry date and missing offsets.
    /// - Removes stale requests for secrets no longer in the list, or whose expiry was cleared.
    /// - Removes everything if settings are disabled.
    func reconcile(secrets: [SecretItem], environment: String) {
        let settings = ExpiryNotificationSettings.load()
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { [weak self] existing in
            guard let self else { return }
            Task { @MainActor in
                let envScopedExisting = existing.filter {
                    $0.identifier.hasPrefix("\(self.identifierPrefix)")
                        && $0.identifier.contains(".\(environment).")
                }

                guard settings.hasAnyActiveOffset else {
                    let stale = envScopedExisting.map(\.identifier)
                    if !stale.isEmpty {
                        center.removePendingNotificationRequests(withIdentifiers: stale)
                    }
                    return
                }

                var desiredIds = Set<String>()
                for secret in secrets {
                    guard let expiry = secret.expiryDate else { continue }
                    for offset in settings.activeOffsetsInDays {
                        guard let fireDate = self.fireDate(expiry: expiry, offsetDays: offset),
                              fireDate > Date() else { continue }
                        let id = self.identifier(secretId: secret.id, environment: environment, offset: offset)
                        desiredIds.insert(id)
                        if !envScopedExisting.contains(where: { $0.identifier == id }) {
                            self.add(
                                identifier: id,
                                secret: secret,
                                fireDate: fireDate,
                                offsetDays: offset
                            )
                        }
                    }
                }

                let stale = envScopedExisting
                    .map(\.identifier)
                    .filter { !desiredIds.contains($0) }
                if !stale.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: stale)
                }
            }
        }
    }

    /// Schedule (or refresh) notifications for a single secret. Used after create/update.
    func schedule(secret: SecretItem, environment: String) {
        cancel(secretId: secret.id, environment: environment)
        let settings = ExpiryNotificationSettings.load()
        guard settings.hasAnyActiveOffset, let expiry = secret.expiryDate else { return }
        for offset in settings.activeOffsetsInDays {
            guard let fireDate = fireDate(expiry: expiry, offsetDays: offset),
                  fireDate > Date() else { continue }
            let id = identifier(secretId: secret.id, environment: environment, offset: offset)
            add(identifier: id, secret: secret, fireDate: fireDate, offsetDays: offset)
        }
    }

    // MARK: - Private

    private func identifier(secretId: String, environment: String, offset: Int) -> String {
        "\(identifierPrefix)\(secretId).\(environment).\(offset)"
    }

    /// Fire moment: 9:00am local time on the day that is `offsetDays` before expiry.
    /// (For offset 0 the fire is 9am of the expiry day itself.)
    private func fireDate(expiry: Date, offsetDays: Int) -> Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: -offsetDays, to: expiry) else { return nil }
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = 9
        comps.minute = 0
        return cal.date(from: comps)
    }

    private func add(identifier: String, secret: SecretItem, fireDate: Date, offsetDays: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Secret expiring: \(secret.key)"
        content.body = bodyText(for: offsetDays)
        content.sound = .default
        var info: [String: String] = [
            "secretId": secret.id,
            "secretKey": secret.key
        ]
        if let url = secret.serviceURL { info["serviceURL"] = url.absoluteString }
        content.userInfo = info

        let triggerComps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func bodyText(for offsetDays: Int) -> String {
        switch offsetDays {
        case 0: return "Expires today. Rotate it now."
        case 1: return "Expires tomorrow."
        default: return "Expires in \(offsetDays) days."
        }
    }
}

extension ExpiryNotificationScheduler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banners even when the app is in the foreground.
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let urlString = info["serviceURL"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
