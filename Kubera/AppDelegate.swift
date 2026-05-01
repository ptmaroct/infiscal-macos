import AppKit
import KuberaCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private let viewModel = AppViewModel()
    private var searchField: NSSearchField!
    private var onboardingWindow: NSWindow?
    private var addSecretWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var secretListWindow: NSWindow?
    private var secretMenuItems: [NSMenuItem] = []

    /// Tracks where secret items start/end in the menu for incremental updates
    private var secretsRangeStart: Int = 0
    private var secretsRangeEnd: Int = 0

    /// Whether the current menu session is unlocked via Touch ID
    private var isUnlocked: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        setupKeyboardShortcut()
        setupDockVisibilityObservers()

        // Local notification scheduler — install delegate, request auth lazily
        // when the user actually enables expiry reminders in Settings.
        ExpiryNotificationScheduler.shared.installDelegate()
        if ExpiryNotificationSettings.load().enabled {
            Task {
                await ExpiryNotificationScheduler.shared.requestAuthorizationIfNeeded()
            }
        }

        if !viewModel.isConfigured {
            showOnboarding()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Infisical")
            button.image?.size = NSSize(width: 16, height: 16)
            button.image?.isTemplate = true
        }
    }

    // MARK: - Menu

    private func setupMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // Check if Touch ID gate is needed
        if TouchIDService.shared.requiresAuthentication && !isUnlocked {
            rebuildLockedMenu()
            return
        }

        // Search field
        let searchItem = NSMenuItem()
        searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        searchField.placeholderString = "Search secrets..."
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        // delegate fires controlTextDidChange synchronously per keystroke,
        // bypassing NSSearchField's internal action throttle so the result
        // list updates without the ~500ms lag.
        searchField.delegate = self
        searchField.focusRingType = .none

        let searchContainer = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
        searchField.frame = NSRect(x: 10, y: 4, width: 240, height: 28)
        searchContainer.addSubview(searchField)
        searchItem.view = searchContainer
        menu.addItem(searchItem)
        menu.addItem(NSMenuItem.separator())

        // Mark where secrets start
        secretsRangeStart = menu.items.count

        // Secret items
        insertSecretItems()

        menu.addItem(NSMenuItem.separator())

        // View All Secrets
        let viewAllItem = NSMenuItem(title: "View All Secrets...", action: #selector(openSecretList), keyEquivalent: "l")
        viewAllItem.target = self
        menu.addItem(viewAllItem)

        // Add New Secret
        let addItem = NSMenuItem(title: "Add New Secret...", action: #selector(openAddSecret), keyEquivalent: "n")
        addItem.target = self
        menu.addItem(addItem)

        // Open Dashboard
        let dashboardItem = NSMenuItem(title: "Open Infisical Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        // Lock Now (only when Touch ID is enabled)
        if TouchIDSettings.load().isEnabled && TouchIDService.shared.isAvailable {
            let lockItem = NSMenuItem(title: "Lock Now", action: #selector(lockNow), keyEquivalent: "l")
            lockItem.target = self
            if let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Lock") {
                lockImage.isTemplate = true
                lockItem.image = lockImage
            }
            menu.addItem(lockItem)
        }

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit Kubera", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Build a locked menu that only shows Touch ID unlock option
    private func rebuildLockedMenu() {
        // Lock icon header
        let headerItem = NSMenuItem(title: "Vault Locked", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]
        headerItem.attributedTitle = NSAttributedString(string: "  Vault Locked", attributes: attrs)
        if let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked") {
            lockImage.isTemplate = true
            headerItem.image = lockImage
        }
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // Unlock with Touch ID
        let unlockItem = NSMenuItem(title: "Unlock with Touch ID", action: #selector(unlockWithTouchID), keyEquivalent: "")
        unlockItem.target = self
        if let touchIDImage = NSImage(systemSymbolName: "touchid", accessibilityDescription: "Touch ID") {
            touchIDImage.isTemplate = true
            unlockItem.image = touchIDImage
        }
        menu.addItem(unlockItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Kubera", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Insert secret items at the current secretsRangeStart position and track the end
    private func insertSecretItems() {
        secretMenuItems.removeAll()
        let displaySecrets = viewModel.menubarSecrets

        if viewModel.isLoading && viewModel.secrets.isEmpty {
            let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.insertItem(loadingItem, at: secretsRangeStart)
        } else if !viewModel.isConfigured {
            let notConfiguredItem = NSMenuItem(title: "Not configured — open Settings", action: #selector(openSettings), keyEquivalent: "")
            notConfiguredItem.target = self
            menu.insertItem(notConfiguredItem, at: secretsRangeStart)
        } else if displaySecrets.isEmpty {
            let emptyTitle = viewModel.searchText.isEmpty ? "No secrets found" : "No results for \"\(viewModel.searchText)\""
            let emptyItem = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.insertItem(emptyItem, at: secretsRangeStart)
        } else {
            let isAllEnvs = AppConfiguration.load()?.isAllEnvironments ?? false
            for (index, secret) in displaySecrets.enumerated() {
                let item = NSMenuItem(title: secret.key, action: #selector(copySecret(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                if isAllEnvs, let env = secret.environment {
                    item.attributedTitle = makeMenuTitle(key: secret.key, env: env)
                    item.toolTip = "Copy \(secret.key) (\(env))"
                } else {
                    item.toolTip = "Click to copy value"
                }
                secretMenuItems.append(item)
                menu.insertItem(item, at: secretsRangeStart + index)
            }

            // Show "N more secrets — search to find" when limited
            if viewModel.searchText.isEmpty && viewModel.hiddenCount > 0 {
                let moreItem = NSMenuItem(title: "\(viewModel.hiddenCount) more — type to search", action: nil, keyEquivalent: "")
                moreItem.isEnabled = false
                menu.insertItem(moreItem, at: secretsRangeStart + displaySecrets.count)
            }
        }

        // Track where secrets end (everything from secretsRangeStart to the separator before "View All")
        secretsRangeEnd = menu.items.count
        // Find the separator that follows our secret items
        for i in secretsRangeStart..<menu.items.count {
            if menu.items[i].isSeparatorItem {
                secretsRangeEnd = i
                break
            }
        }
    }

    /// Only update the secret items section — no flicker, search field keeps focus
    private func updateSecretItems() {
        // Remove existing secret items (from end to start to preserve indices)
        for i in stride(from: secretsRangeEnd - 1, through: secretsRangeStart, by: -1) {
            menu.removeItem(at: i)
        }
        // Insert fresh items
        insertSecretItems()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        viewModel.searchText = ""

        // Reset unlock state for each menu open — re-evaluate timeout
        isUnlocked = !TouchIDService.shared.requiresAuthentication
        rebuildMenu()

        // Only set up normal menu behavior if unlocked
        if isUnlocked || !TouchIDSettings.load().isEnabled {
            // Focus search field
            DispatchQueue.main.async { [weak self] in
                self?.searchField?.becomeFirstResponder()
            }

            // Refresh silently in background
            if viewModel.isConfigured {
                Task {
                    await viewModel.loadSecrets()
                    await MainActor.run {
                        self.updateSecretItems()
                    }
                }
            }
        }
    }

    /// Build a menu item title that shows the secret key followed by a small
    /// colored env tag — used in all-envs mode to disambiguate the same key
    /// across environments.
    private func makeMenuTitle(key: String, env: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0)
        ]
        result.append(NSAttributedString(string: key, attributes: keyAttrs))
        result.append(NSAttributedString(string: "  ", attributes: keyAttrs))

        let envAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: envColor(for: env)
        ]
        result.append(NSAttributedString(string: env.uppercased(), attributes: envAttrs))
        return result
    }

    /// Stable color per env slug, mirroring EnvBadge's palette.
    private func envColor(for slug: String) -> NSColor {
        switch slug.lowercased() {
        case "prod", "production": return NSColor(red: 0.96, green: 0.42, blue: 0.42, alpha: 1)
        case "staging", "stage", "stg": return NSColor(red: 0.95, green: 0.75, blue: 0.30, alpha: 1)
        case "dev", "development": return NSColor(red: 0.40, green: 0.78, blue: 0.50, alpha: 1)
        case "test", "testing", "qa": return NSColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1)
        case "preview": return NSColor(red: 0.78, green: 0.55, blue: 0.95, alpha: 1)
        default:
            let hue = CGFloat(abs(slug.lowercased().hashValue) % 360) / 360.0
            return NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1)
        }
    }

    // MARK: - Actions

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        viewModel.searchText = sender.stringValue
        updateSecretItems()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        viewModel.searchText = field.stringValue
        updateSecretItems()
    }

    @objc private func copySecret(_ sender: NSMenuItem) {
        let index = sender.tag
        let displaySecrets = viewModel.menubarSecrets
        guard index >= 0, index < displaySecrets.count else { return }
        let secret = displaySecrets[index]
        viewModel.copySecret(secret)

        // Brief visual feedback — flash the menubar icon
        if let button = statusItem.button {
            let original = button.image
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
            button.image?.isTemplate = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                button.image = original
            }
        }
    }

    @objc private func lockNow() {
        isUnlocked = false
        TouchIDService.shared.clearAuth()
    }

    @objc private func unlockWithTouchID() {
        menu.cancelTracking()
        Task {
            let success = await TouchIDService.shared.authenticate()
            if success {
                isUnlocked = true
                // Re-open the menu unlocked
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, let button = self.statusItem.button else { return }
                    button.performClick(nil)
                }
            }
        }
    }

    @objc private func openSecretList() {
        if secretListWindow == nil || !secretListWindow!.isVisible {
            let view = SecretListView(viewModel: viewModel) { [weak self] in
                self?.secretListWindow?.close()
            }
            secretListWindow = makeStyledWindow(view: view, width: 660, height: 540)
        }
        secretListWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAddSecret() {
        if addSecretWindow == nil || !addSecretWindow!.isVisible {
            let view = AddSecretView(viewModel: viewModel) { [weak self] in
                self?.addSecretWindow?.close()
            }
            addSecretWindow = makeStyledWindow(view: view, width: 480, height: 540)
        }
        addSecretWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDashboard() {
        let config = AppConfiguration.load()
        let dashboardURL = config?.dashboardURL ?? "https://app.infisical.com"
        if let url = URL(string: dashboardURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil || !settingsWindow!.isVisible {
            let view = SettingsView(viewModel: viewModel) { [weak self] in
                self?.settingsWindow?.close()
            }
            settingsWindow = makeStyledWindow(view: view, width: 820, height: 430)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyDockVisibility()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Onboarding

    func showOnboarding() {
        if onboardingWindow == nil || !onboardingWindow!.isVisible {
            let view = OnboardingView(viewModel: viewModel) { [weak self] in
                self?.onboardingWindow?.close()
            }
            onboardingWindow = makeStyledWindow(view: view, width: 500, height: 460)
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyDockVisibility()
    }

    // MARK: - Dock Visibility

    static let dockVisibilityChangedNotification = Notification.Name("kubera.dockVisibilityChanged")

    private func setupDockVisibilityObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillCloseNotification(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyDockVisibility),
            name: AppDelegate.dockVisibilityChangedNotification,
            object: nil
        )
    }

    @objc private func windowWillCloseNotification(_ notification: Notification) {
        // Treat the closing window as no longer visible when computing policy.
        let closing = notification.object as? NSWindow
        let othersVisible = [settingsWindow, onboardingWindow]
            .compactMap { $0 }
            .contains { $0 !== closing && $0.isVisible }
        let shouldShow = othersVisible && DockVisibilityPreference.enabled
        NSApp.setActivationPolicy(shouldShow ? .regular : .accessory)
    }

    @objc private func applyDockVisibility() {
        let anyVisible = (settingsWindow?.isVisible ?? false) || (onboardingWindow?.isVisible ?? false)
        let shouldShow = anyVisible && DockVisibilityPreference.enabled
        NSApp.setActivationPolicy(shouldShow ? .regular : .accessory)
    }

    // MARK: - Window Factory

    private func makeStyledWindow<V: View>(view: V, width: CGFloat, height: CGFloat) -> NSWindow {
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        return window
    }

    // MARK: - Keyboard Shortcut

    private func setupKeyboardShortcut() {
        let config = AppConfiguration.load()
        let keyCode = config?.resolvedKeyCode ?? AppConfiguration.defaultShortcutKeyCode
        let modifiers = config?.resolvedModifiers ?? AppConfiguration.defaultShortcutModifiers

        GlobalShortcutManager.shared.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            DispatchQueue.main.async {
                button.performClick(nil)
            }
        }
    }
}
