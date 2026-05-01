import Foundation

/// Controls whether Kubera shows in the Dock while a settings or onboarding
/// window is open. When false (or no window open), the app stays a menubar
/// accessory and stays out of the Dock + ⌘-Tab switcher.
enum DockVisibilityPreference {
    private static let key = "kubera.showInDockWhenWindowsOpen"

    /// Defaults to true so newcomers see Kubera in the Dock the first time they
    /// open Settings — discoverable, but easy to opt out of.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
