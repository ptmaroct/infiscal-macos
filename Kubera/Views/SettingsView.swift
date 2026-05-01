import SwiftUI
import KuberaCore
import Carbon

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    let onDismiss: () -> Void

    @State private var projects: [InfisicalProject] = []
    @State private var selectedProject: InfisicalProject?
    @State private var selectedEnvironment: InfisicalEnvironment?
    @State private var allEnvironmentsSelected: Bool = false
    @State private var allProjectsSelected: Bool = false
    @State private var defaultAddEnvSlug: String?

    /// Save button enabled when either: all-projects mode is on (env is locked
    /// to all-envs), or a single project + an env / all-envs is selected.
    private var isSaveable: Bool {
        if allProjectsSelected { return true }
        guard selectedProject != nil else { return false }
        return allEnvironmentsSelected || selectedEnvironment != nil
    }

    /// Envs available to the "Default for Add" picker. In all-projects mode
    /// we union envs across every project (de-dup by slug); otherwise we use
    /// the selected project's envs.
    private var defaultAddEnvOptions: [InfisicalEnvironment] {
        if allProjectsSelected {
            var seen: Set<String> = []
            var out: [InfisicalEnvironment] = []
            for project in projects {
                for env in project.environments where !seen.contains(env.slug) {
                    seen.insert(env.slug)
                    out.append(env)
                }
            }
            return out.sorted { $0.name < $1.name }
        }
        return selectedProject?.environments ?? []
    }
    @State private var secretPath: String = "/"
    @State private var isLoading = true
    @State private var statusMessage: String?

    // Shortcut state
    @State private var shortcutKeyCode: UInt32 = AppConfiguration.defaultShortcutKeyCode
    @State private var shortcutModifiers: UInt32 = AppConfiguration.defaultShortcutModifiers
    @State private var isRecordingShortcut = false
    @State private var shortcutConflict: String?
    @State private var shortcutMonitor: Any?

    // Touch ID state
    @State private var touchIDEnabled: Bool = false
    @State private var touchIDTimeout: TimeoutPreset = .fifteenMinutes
    @State private var touchIDAvailable: Bool = false

    // Expiry notification state
    @State private var expiryNotificationsEnabled: Bool = false
    @State private var expiryNotify7Days: Bool = true
    @State private var expiryNotify1Day: Bool = true
    @State private var expiryNotifyAtExpiry: Bool = true

    // Dock visibility state
    @State private var showInDockWhenWindowsOpen: Bool = DockVisibilityPreference.enabled

    var body: some View {
        ZStack {
            // Glass background
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header — relies on the standard window close button for dismiss.
                // Version + GitHub + handle chips live here so the right column
                // doesn't need an About card eating vertical space.
                HStack(spacing: 10) {
                    Text("Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    Text("v1.4.0")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    headerLink(text: "Star on GitHub", icon: "star.fill", url: "https://github.com/ptmaroct/kubera")
                    headerLink(text: "@waahbete", icon: nil, url: "https://x.com/waahbete")
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 8)
                    Spacer()
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            // Project & Environment card
                            glassCard {
                                VStack(spacing: 14) {
                                    settingsRow(
                                        icon: "folder.fill",
                                        label: "Project"
                                    ) {
                                        Menu {
                                            Button {
                                                allProjectsSelected = true
                                                selectedProject = nil
                                                selectedEnvironment = nil
                                                allEnvironmentsSelected = true
                                                // Pre-populate defaultAddEnvSlug from the union if not already valid.
                                                if defaultAddEnvSlug == nil
                                                    || !defaultAddEnvOptions.contains(where: { $0.slug == defaultAddEnvSlug }) {
                                                    defaultAddEnvSlug = defaultAddEnvOptions.first?.slug
                                                }
                                            } label: {
                                                HStack {
                                                    Text("All Projects")
                                                    if allProjectsSelected {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                            Divider()
                                            ForEach(projects) { project in
                                                Button {
                                                    allProjectsSelected = false
                                                    selectedProject = project
                                                    selectedEnvironment = project.environments.first
                                                    allEnvironmentsSelected = false
                                                } label: {
                                                    HStack {
                                                        Text(project.name)
                                                        if !allProjectsSelected && selectedProject?.id == project.id {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            dropdownPill(text: allProjectsSelected
                                                         ? "All Projects"
                                                         : (selectedProject?.name ?? "Select..."))
                                        }
                                        .buttonStyle(.plain)
                                        .menuIndicator(.hidden)
                                        .fixedSize()
                                    }

                                    if !allProjectsSelected {
                                        Divider().opacity(0.2)

                                        settingsRow(
                                            icon: "leaf.fill",
                                            label: "Environment"
                                        ) {
                                            if let envs = selectedProject?.environments, !envs.isEmpty {
                                            Menu {
                                                Button {
                                                    allEnvironmentsSelected = true
                                                    selectedEnvironment = nil
                                                } label: {
                                                    HStack {
                                                        Text("All Environments")
                                                        if allEnvironmentsSelected {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                                Divider()
                                                ForEach(envs) { env in
                                                    Button {
                                                        allEnvironmentsSelected = false
                                                        selectedEnvironment = env
                                                    } label: {
                                                        HStack {
                                                            Text(env.name)
                                                            if !allEnvironmentsSelected && selectedEnvironment?.id == env.id {
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }
                                            } label: {
                                                dropdownPill(text: allEnvironmentsSelected
                                                             ? "All Environments"
                                                             : (selectedEnvironment?.name ?? "Select..."))
                                            }
                                            .buttonStyle(.plain)
                                            .menuIndicator(.hidden)
                                            .fixedSize()
                                        }
                                        }
                                    }

                                    Divider().opacity(0.2)

                                    settingsRow(
                                        icon: "plus.square.on.square",
                                        label: "Default for Add"
                                    ) {
                                        if defaultAddEnvOptions.isEmpty {
                                            dropdownPill(text: "—").opacity(0.4)
                                        } else {
                                            Menu {
                                                ForEach(defaultAddEnvOptions) { env in
                                                    Button {
                                                        defaultAddEnvSlug = env.slug
                                                    } label: {
                                                        HStack {
                                                            Text(env.name)
                                                            if defaultAddEnvSlug == env.slug {
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }
                                            } label: {
                                                dropdownPill(text: defaultAddEnvOptions.first(where: { $0.slug == defaultAddEnvSlug })?.name
                                                             ?? defaultAddEnvOptions.first?.name ?? "Select...")
                                            }
                                            .buttonStyle(.plain)
                                            .menuIndicator(.hidden)
                                            .fixedSize()
                                        }
                                    }
                                }
                            }

                            // Keyboard Shortcut card
                            glassCard {
                                VStack(spacing: 12) {
                                    settingsRow(
                                        icon: "keyboard",
                                        label: "Shortcut"
                                    ) {
                                        HStack(spacing: 8) {
                                            if isRecordingShortcut {
                                                Text("Press keys...")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Color.vault.accent)
                                            } else {
                                                Text(ShortcutHelper.displayString(keyCode: shortcutKeyCode, modifiers: shortcutModifiers))
                                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.85))
                                            }

                                            Button {
                                                if isRecordingShortcut {
                                                    stopRecording()
                                                } else {
                                                    startRecording()
                                                }
                                            } label: {
                                                Text(isRecordingShortcut ? "Stop" : "Set")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(isRecordingShortcut ? Color.vault.bg : .white.opacity(0.7))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(isRecordingShortcut ? Color.vault.accent : .white.opacity(0.1))
                                                    .cornerRadius(5)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    if let conflict = shortcutConflict {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 9))
                                            Text(conflict)
                                                .font(.system(size: 10))
                                        }
                                        .foregroundColor(Color.vault.warning)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 28)
                                    }

                                    let isDefault = shortcutKeyCode == AppConfiguration.defaultShortcutKeyCode
                                        && shortcutModifiers == AppConfiguration.defaultShortcutModifiers
                                    if !isDefault {
                                        Button {
                                            shortcutKeyCode = AppConfiguration.defaultShortcutKeyCode
                                            shortcutModifiers = AppConfiguration.defaultShortcutModifiers
                                            shortcutConflict = nil
                                        } label: {
                                            Text("Reset to ⌘ ⇧ K")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.35))
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                            }

                            // Touch ID card
                            if touchIDAvailable {
                                glassCard {
                                    VStack(spacing: 12) {
                                        settingsRow(
                                            icon: "touchid",
                                            label: "Touch ID"
                                        ) {
                                            Toggle("", isOn: $touchIDEnabled)
                                                .toggleStyle(.switch)
                                                .controlSize(.small)
                                                .tint(Color.vault.accent)
                                        }

                                        if touchIDEnabled {
                                            Divider().opacity(0.2)

                                            settingsRow(
                                                icon: "timer",
                                                label: "Require After"
                                            ) {
                                                Menu {
                                                    ForEach(TimeoutPreset.allCases) { preset in
                                                        Button {
                                                            touchIDTimeout = preset
                                                        } label: {
                                                            HStack {
                                                                Text(preset.displayName)
                                                                if touchIDTimeout == preset {
                                                                    Image(systemName: "checkmark")
                                                                }
                                                            }
                                                        }
                                                    }
                                                } label: {
                                                    dropdownPill(text: touchIDTimeout.displayName)
                                                }
                                                .buttonStyle(.plain)
                                                .menuIndicator(.hidden)
                                                .fixedSize()
                                            }

                                            HStack(spacing: 4) {
                                                Image(systemName: "info.circle")
                                                    .font(.system(size: 9))
                                                Text(touchIDTimeout == .immediately
                                                    ? "Touch ID required every time you open the menu"
                                                    : "Touch ID required \(touchIDTimeout.displayName.lowercased()) of inactivity")
                                                    .font(.system(size: 10))
                                            }
                                            .foregroundColor(.white.opacity(0.35))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 28)
                                        }
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }

                        VStack(spacing: 14) {
                            // Expiry reminders card
                            glassCard {
                                VStack(spacing: 12) {
                                    settingsRow(
                                        icon: "bell.badge",
                                        label: "Expiry Reminders"
                                    ) {
                                        Toggle("", isOn: $expiryNotificationsEnabled)
                                            .toggleStyle(.switch)
                                            .controlSize(.small)
                                            .tint(Color.vault.accent)
                                    }

                                    if expiryNotificationsEnabled {
                                        Divider().opacity(0.2)

                                        settingsRow(
                                            icon: "calendar.badge.clock",
                                            label: "7 days before"
                                        ) {
                                            Toggle("", isOn: $expiryNotify7Days)
                                                .toggleStyle(.switch)
                                                .controlSize(.small)
                                                .tint(Color.vault.accent)
                                        }

                                        settingsRow(
                                            icon: "calendar",
                                            label: "1 day before"
                                        ) {
                                            Toggle("", isOn: $expiryNotify1Day)
                                                .toggleStyle(.switch)
                                                .controlSize(.small)
                                                .tint(Color.vault.accent)
                                        }

                                        settingsRow(
                                            icon: "exclamationmark.circle",
                                            label: "On expiry day"
                                        ) {
                                            Toggle("", isOn: $expiryNotifyAtExpiry)
                                                .toggleStyle(.switch)
                                                .controlSize(.small)
                                                .tint(Color.vault.accent)
                                        }

                                        HStack(spacing: 4) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 9))
                                            Text("Local macOS notifications fire at 9am for secrets with an expiry date.")
                                                .font(.system(size: 10))
                                        }
                                        .foregroundColor(.white.opacity(0.35))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 28)
                                    }
                                }
                            }

                            // App behavior card
                            glassCard {
                                VStack(spacing: 12) {
                                    settingsRow(
                                        icon: "dock.rectangle",
                                        label: "Show in Dock"
                                    ) {
                                        Toggle("", isOn: $showInDockWhenWindowsOpen)
                                            .toggleStyle(.switch)
                                            .labelsHidden()
                                            .controlSize(.small)
                                    }

                                    HStack(spacing: 4) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 9))
                                        Text("Show Kubera in the Dock while Settings or Onboarding is open. Off keeps it menubar-only.")
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(.white.opacity(0.35))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 28)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 8)
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(msg.contains("Saved") ? Color.vault.success : Color.vault.error)
                        .padding(.bottom, 4)
                }

                // Save button
                Button {
                    stopRecording()
                    save()
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.vault.accent)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!isSaveable)
                .opacity(isSaveable ? 1 : 0.4)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 820, height: 430)
        .preferredColorScheme(.dark)
        .onAppear {
            loadData()
            loadShortcut()
            loadTouchIDSettings()
            loadExpiryNotificationSettings()
        }
        .onChange(of: expiryNotificationsEnabled) { _ in saveExpiryNotificationSettings() }
        .onChange(of: expiryNotify7Days) { _ in saveExpiryNotificationSettings() }
        .onChange(of: expiryNotify1Day) { _ in saveExpiryNotificationSettings() }
        .onChange(of: expiryNotifyAtExpiry) { _ in saveExpiryNotificationSettings() }
        .onChange(of: showInDockWhenWindowsOpen) { newValue in
            DockVisibilityPreference.enabled = newValue
            NotificationCenter.default.post(name: AppDelegate.dockVisibilityChangedNotification, object: nil)
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Glass Card

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
    }

    // MARK: - Settings Row

    /// Compact link chip used in the Settings header. Replaces the old "About"
    /// card (Version / Enjoying Kubera? / @waahbete) so the right column can
    /// breathe without padding.
    @ViewBuilder
    private func headerLink(text: String, icon: String?, url: String) -> some View {
        Button {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundColor(Color.vault.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.vault.accent.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.vault.accent.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Pill-shaped trigger label for Menus, used by every dropdown in this view
    /// so the project / env / default-add / Touch-ID timeout selectors all read
    /// as one consistent control.
    @ViewBuilder
    private func dropdownPill(text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.vault.accent.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func settingsRow<Content: View>(icon: String, label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color.vault.accent)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            trailing()
        }
    }

    // MARK: - Shortcut Recording

    private func loadShortcut() {
        if let config = AppConfiguration.load() {
            shortcutKeyCode = config.resolvedKeyCode
            shortcutModifiers = config.resolvedModifiers
        }
    }

    private func startRecording() {
        isRecordingShortcut = true
        shortcutConflict = nil

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let carbonMods = ShortcutHelper.carbonModifiers(from: event.modifierFlags)
            guard carbonMods != 0 else { return event }

            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard !modifierKeyCodes.contains(event.keyCode) else { return event }

            shortcutKeyCode = UInt32(event.keyCode)
            shortcutModifiers = carbonMods

            let conflict = GlobalShortcutManager.shared.checkConflict(
                keyCode: UInt32(event.keyCode),
                modifiers: carbonMods
            )
            shortcutConflict = conflict
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecordingShortcut = false
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }
    }

    // MARK: - Data

    private func loadData() {
        // Show cached data SYNCHRONOUSLY — no async needed
        let cached = ProjectCache.shared.projects
        if !cached.isEmpty {
            projects = cached
            applyConfig()
            isLoading = false
        }

        // Then refresh in background
        Task {
            let fresh = await ProjectCache.shared.fetchProjects()
            if projects.isEmpty || fresh != projects {
                projects = fresh
                applyConfig()
            }
            isLoading = false
        }
    }

    private func applyConfig() {
        if let config = AppConfiguration.load() {
            if config.isAllProjects {
                allProjectsSelected = true
                selectedProject = nil
                selectedEnvironment = nil
                allEnvironmentsSelected = true
            } else {
                allProjectsSelected = false
                selectedProject = projects.first(where: { $0.id == config.projectId })
            }
            if let project = selectedProject {
                if config.isAllEnvironments {
                    allEnvironmentsSelected = true
                    selectedEnvironment = nil
                } else {
                    allEnvironmentsSelected = false
                    selectedEnvironment = project.environments.first(where: { $0.slug == config.environment })
                }
            }
            secretPath = config.secretPath
            defaultAddEnvSlug = config.defaultAddEnvironment ?? selectedProject?.environments.first?.slug
        }
    }

    // MARK: - Touch ID

    private func loadTouchIDSettings() {
        touchIDAvailable = TouchIDService.shared.isAvailable
        let settings = TouchIDSettings.load()
        touchIDEnabled = settings.isEnabled
        touchIDTimeout = settings.timeoutPreset
    }

    // MARK: - Expiry Notifications

    private func loadExpiryNotificationSettings() {
        let settings = ExpiryNotificationSettings.load()
        expiryNotificationsEnabled = settings.enabled
        expiryNotify7Days = settings.notify7Days
        expiryNotify1Day = settings.notify1Day
        expiryNotifyAtExpiry = settings.notifyAtExpiry
    }

    private func saveExpiryNotificationSettings() {
        let settings = ExpiryNotificationSettings(
            enabled: expiryNotificationsEnabled,
            notify7Days: expiryNotify7Days,
            notify1Day: expiryNotify1Day,
            notifyAtExpiry: expiryNotifyAtExpiry
        )
        settings.save()

        // Reconcile pending notifications immediately so toggles take effect.
        // Group secrets by their attached env so each env reconciles its own slice.
        let secrets = viewModel.secrets
        let configEnv = AppConfiguration.load()?.environment ?? AppConfiguration.defaultEnvironment
        let envBuckets: [String: [SecretItem]] = Dictionary(grouping: secrets) {
            $0.environment ?? configEnv
        }
        if settings.enabled {
            Task {
                await ExpiryNotificationScheduler.shared.requestAuthorizationIfNeeded()
                for (env, items) in envBuckets {
                    ExpiryNotificationScheduler.shared.reconcile(secrets: items, environment: env)
                }
            }
        } else {
            ExpiryNotificationScheduler.shared.cancelAll()
        }
    }

    // MARK: - Save

    private func save() {
        let projectId: String
        let projectName: String?
        if allProjectsSelected {
            projectId = AppConfiguration.allProjectsSentinel
            projectName = "All Projects"
        } else {
            guard let project = selectedProject else { return }
            guard allEnvironmentsSelected || selectedEnvironment != nil else { return }
            projectId = project.id
            projectName = project.name
        }

        let envSlug: String = allEnvironmentsSelected
            ? AppConfiguration.allEnvironmentsSentinel
            : (selectedEnvironment?.slug ?? AppConfiguration.defaultEnvironment)

        let existingConfig = AppConfiguration.load()
        let config = AppConfiguration(
            projectId: projectId,
            environment: envSlug,
            secretPath: secretPath,
            baseURL: existingConfig?.baseURL ?? AppConfiguration.defaultBaseURL,
            projectName: projectName,
            organizationId: existingConfig?.organizationId,
            shortcutKeyCode: shortcutKeyCode,
            shortcutModifiers: shortcutModifiers,
            defaultAddEnvironment: defaultAddEnvSlug
        )
        config.save()

        // Save Touch ID settings
        let touchIDSettings = TouchIDSettings(
            isEnabled: touchIDEnabled && touchIDAvailable,
            timeoutPreset: touchIDTimeout
        )
        touchIDSettings.save()

        // Clear auth timestamp when Touch ID is disabled
        if !touchIDEnabled {
            TouchIDService.shared.clearAuth()
        }

        GlobalShortcutManager.shared.updateShortcut(
            keyCode: shortcutKeyCode,
            modifiers: shortcutModifiers
        )

        viewModel.configurationSaved()
        withAnimation { statusMessage = "Saved!" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDismiss()
        }
    }
}

// MARK: - NSVisualEffectView wrapper for glass blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
