import SwiftUI
import KuberaCore
import Carbon

struct SettingsView: View {
    static let windowWidth: CGFloat = 760
    static let windowHeight: CGFloat = 640

    @ObservedObject var viewModel: AppViewModel
    let onDismiss: () -> Void

    @State private var projects: [InfisicalProject] = []
    @State private var selectedProject: InfisicalProject?
    @State private var selectedEnvironment: InfisicalEnvironment?
    @State private var allEnvironmentsSelected: Bool = false
    @State private var allProjectsSelected: Bool = false
    @State private var defaultAddEnvSlug: String?

    /// Debounce holder for auto-save. Each field change cancels the prior task
    /// and schedules a fresh 1s-deadline persist; users get instant feedback
    /// without us thrashing the config file on every keystroke.
    @State private var pendingSave: Task<Void, Never>?

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

    // Backup/restore state
    @State private var isBackupRunning: Bool = false
    @State private var isRestoreRunning: Bool = false
    @State private var backupStatusMessage: String?
    @State private var restoreOverwrite: Bool = false

    // New project / env prompts
    @State private var showNewProjectPrompt: Bool = false
    @State private var newProjectName: String = ""
    @State private var showNewEnvPrompt: Bool = false
    @State private var newEnvName: String = ""
    @State private var newEnvSlug: String = ""
    @State private var creationError: String?

    // Backend switching
    @State private var showBackendSwitchPrompt: Bool = false
    @State private var pendingSwitchTarget: String = ""

    private let horizontalPadding: CGFloat = 22
    private let columnSpacing: CGFloat = 14
    private var columnWidth: CGFloat {
        (Self.windowWidth - (horizontalPadding * 2) - columnSpacing) / 2
    }

    var body: some View {
        ZStack {
            // Glass background
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header — relies on the standard window close button for dismiss.
                HStack {
                    Text("Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
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
                    // Compact two-column settings panel. Cards size to content
                    // and notes wrap so sparse cards do not stretch unevenly.
                    // No outer ScrollView — the window auto-sizes to content
                    // height so nothing gets clipped or padded with empty space.
                    HStack(alignment: .top, spacing: columnSpacing) {
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
                                            Divider()
                                            Button {
                                                newProjectName = ""
                                                showNewProjectPrompt = true
                                            } label: {
                                                Label("New Project…", systemImage: "plus")
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
                                                Divider()
                                                Button {
                                                    newEnvName = ""
                                                    newEnvSlug = ""
                                                    showNewEnvPrompt = true
                                                } label: {
                                                    Label("New Environment…", systemImage: "plus")
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
                                                .labelsHidden()
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

                                            settingNote(touchIDTimeout == .immediately
                                                ? "Touch ID required every time you open the menu"
                                                : "Touch ID required \(touchIDTimeout.displayName.lowercased()) of inactivity")
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: columnWidth, alignment: .top)

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
                                                .labelsHidden()
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
                                                .labelsHidden()
                                                .controlSize(.small)
                                                .tint(Color.vault.accent)
                                        }

                                        settingsRow(
                                            icon: "calendar",
                                            label: "1 day before"
                                        ) {
                                            Toggle("", isOn: $expiryNotify1Day)
                                                .toggleStyle(.switch)
                                                .labelsHidden()
                                                .controlSize(.small)
                                                .tint(Color.vault.accent)
                                        }

                                        settingsRow(
                                            icon: "exclamationmark.circle",
                                            label: "On expiry day"
                                        ) {
                                            Toggle("", isOn: $expiryNotifyAtExpiry)
                                                .toggleStyle(.switch)
                                                .labelsHidden()
                                                .controlSize(.small)
                                                .tint(Color.vault.accent)
                                        }

                                        settingNote("Local macOS notifications fire at 9am for secrets with an expiry date.")
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
                                            .tint(Color.vault.accent)
                                    }

                                    settingNote("Show Kubera in the Dock while Settings or Onboarding is open. Off keeps it menubar-only.")
                                }
                            }

                            // Storage backend + backup/restore card
                            storageCard()
                        }
                        .frame(width: columnWidth, alignment: .top)
                    }
                    .padding(.horizontal, horizontalPadding)

                    creditsFooter()
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                }
            }
        }
        .frame(width: Self.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
        .alert("New Project", isPresented: $showNewProjectPrompt) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) { }
            Button("Create") { Task { await createProject() } }
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text((AppConfiguration.load()?.isLocalBackend ?? true)
                 ? "Add a new local project. Default envs (Development, Staging, Production) are created."
                 : "Projects must be created in the Infisical dashboard. This dialog only affects local backend.")
        }
        .alert("New Environment", isPresented: $showNewEnvPrompt) {
            TextField("Display name (e.g. QA)", text: $newEnvName)
            TextField("Slug (e.g. qa)", text: $newEnvSlug)
            Button("Cancel", role: .cancel) { }
            Button("Create") { Task { await createEnvironment() } }
                .disabled(newEnvName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Add a new environment to \(selectedProject?.name ?? "this project").")
        }
        .alert("Switch Backend", isPresented: $showBackendSwitchPrompt) {
            Button("Cancel", role: .cancel) { }
            Button(pendingSwitchTarget == SecretStoreBackendID.local ? "Switch to Local" : "Connect Infisical") {
                applyBackendSwitch()
            }
        } message: {
            Text(pendingSwitchTarget == SecretStoreBackendID.local
                 ? "Switch to local-only mode. Existing local secrets remain. Infisical secrets are not deleted on the server but stop showing here."
                 : "Connect this Mac to an Infisical workspace. The current local secrets stay encrypted on disk.")
        }
        .alert("Error", isPresented: Binding(
            get: { creationError != nil },
            set: { if !$0 { creationError = nil } }
        )) {
            Button("OK", role: .cancel) { creationError = nil }
        } message: {
            Text(creationError ?? "")
        }
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
        // Auto-save Project / Environment / Default-for-Add / Path / Shortcut
        // 1s after the last change. Touch ID + Expiry + Dock toggles already
        // persist immediately via their own onChange handlers above.
        .onChange(of: selectedProject) { _ in scheduleSave() }
        .onChange(of: selectedEnvironment) { _ in scheduleSave() }
        .onChange(of: allEnvironmentsSelected) { _ in scheduleSave() }
        .onChange(of: allProjectsSelected) { _ in scheduleSave() }
        .onChange(of: secretPath) { _ in scheduleSave() }
        .onChange(of: defaultAddEnvSlug) { _ in scheduleSave() }
        .onChange(of: shortcutKeyCode) { _ in scheduleSave() }
        .onChange(of: shortcutModifiers) { _ in scheduleSave() }
        .onChange(of: touchIDEnabled) { _ in scheduleSave() }
        .onChange(of: touchIDTimeout) { _ in scheduleSave() }
        .onDisappear {
            stopRecording()
            // Flush any pending debounce immediately so the user can't lose
            // an in-flight change by closing the window.
            pendingSave?.cancel()
            if isSaveable { save() }
        }
    }

    /// Cancel any in-flight debounce and re-arm a 1s deadline. Save runs on the
    /// MainActor; cancellation is checked after the sleep to skip stale writes.
    private func scheduleSave() {
        guard !isLoading else { return }
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, isSaveable else { return }
            save()
        }
    }

    // MARK: - Glass Card

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
    }

    // MARK: - Settings Row

    @ViewBuilder
    private func settingNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.white.opacity(0.35))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28)
    }

    /// Storage backend card. Shows which backend is active and exposes encrypted
    /// backup / restore. Backend switching itself happens through Onboarding —
    /// this card just surfaces what's running and the export tools.
    @ViewBuilder
    private func storageCard() -> some View {
        let isLocal = AppConfiguration.load()?.isLocalBackend ?? false
        let backendLabel = isLocal ? "On this Mac" : "Infisical"
        glassCard {
            VStack(spacing: 12) {
                settingsRow(icon: "lock.shield", label: "Storage") {
                    Text(backendLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }

                Divider().opacity(0.2)

                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        pendingSwitchTarget = isLocal
                            ? SecretStoreBackendID.infisical
                            : SecretStoreBackendID.local
                        showBackendSwitchPrompt = true
                    } label: {
                        Label(isLocal ? "Connect to Infisical…" : "Switch to Local Mode",
                              systemImage: isLocal ? "icloud.and.arrow.up" : "internaldrive")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08))
                    .cornerRadius(5)
                    .foregroundColor(.white.opacity(0.9))
                }

                Divider().opacity(0.2)

                HStack(spacing: 10) {
                    Toggle("Overwrite on restore", isOn: $restoreOverwrite)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 28)

                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        Task { await runBackup() }
                    } label: {
                        Label("Backup…", systemImage: "arrow.down.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBackupRunning || isRestoreRunning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08))
                    .cornerRadius(5)

                    Button {
                        Task { await runRestore() }
                    } label: {
                        Label("Restore…", systemImage: "arrow.up.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBackupRunning || isRestoreRunning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08))
                    .cornerRadius(5)
                }
                .foregroundColor(.white.opacity(0.9))

                if let msg = backupStatusMessage {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 28)
                }

                settingNote("Encrypted .kubera archive — AES-256-GCM, PBKDF2-SHA256 (524,288 rounds).")
            }
        }
    }

    private func createProject() async {
        guard let cfg = AppConfiguration.load() else { return }
        let store = SecretStoreFactory.make(for: cfg)
        do {
            let project = try await store.createProject(name: newProjectName)
            await reloadProjectsAndSelect(projectId: project.id)
        } catch {
            creationError = error.localizedDescription
        }
    }

    private func createEnvironment() async {
        guard let cfg = AppConfiguration.load(), let project = selectedProject else { return }
        let store = SecretStoreFactory.make(for: cfg)
        do {
            let env = try await store.createEnvironment(
                name: newEnvName,
                slug: newEnvSlug.isEmpty ? newEnvName : newEnvSlug,
                projectId: project.id
            )
            await reloadProjectsAndSelect(projectId: project.id, envSlug: env.slug)
        } catch {
            creationError = error.localizedDescription
        }
    }

    private func reloadProjectsAndSelect(projectId: String, envSlug: String? = nil) async {
        ProjectCache.shared.invalidateProjects()
        let fresh = await ProjectCache.shared.fetchProjects()
        projects = fresh
        if let project = fresh.first(where: { $0.id == projectId }) {
            allProjectsSelected = false
            selectedProject = project
            allEnvironmentsSelected = false
            if let envSlug, let env = project.environments.first(where: { $0.slug == envSlug }) {
                selectedEnvironment = env
            } else if selectedEnvironment == nil {
                selectedEnvironment = project.environments.first
            }
        }
        scheduleSave()
    }

    private func applyBackendSwitch() {
        if pendingSwitchTarget == SecretStoreBackendID.local {
            // Switch to Local: stamp config + reload.
            AppConfiguration.defaultLocal().save()
            ProjectCache.shared.invalidateProjects()
            viewModel.configurationSaved()
            Task { await reloadProjectsAndSelect(projectId: KeychainSecretStore.localProjectId) }
        } else {
            // Connect Infisical: hand off to Onboarding.
            NotificationCenter.default.post(name: .kuberaConnectInfisicalRequested, object: nil)
            onDismiss()
        }
    }

    private func runBackup() async {
        isBackupRunning = true
        backupStatusMessage = nil
        let result = await BackupCoordinator.runBackup(viewModel: viewModel)
        isBackupRunning = false
        switch result {
        case .cancelled: backupStatusMessage = nil
        case .success(let count, let url):
            backupStatusMessage = "Backed up \(count) secrets → \(url.lastPathComponent)"
        case .failed(let msg):
            backupStatusMessage = "Backup failed: \(msg)"
        }
    }

    private func runRestore() async {
        isRestoreRunning = true
        backupStatusMessage = nil
        let result = await BackupCoordinator.runRestore(
            viewModel: viewModel, overwrite: restoreOverwrite
        )
        isRestoreRunning = false
        switch result {
        case .cancelled: backupStatusMessage = nil
        case .success(let count, let url):
            backupStatusMessage = "Restored \(count) secrets from \(url.lastPathComponent)"
        case .failed(let msg):
            backupStatusMessage = "Restore failed: \(msg)"
        }
    }

    /// Footer block that fills the right column. Two short lines: a personal
    /// credit + Infisical thanks, then version + Star CTA. Centered, accent
    /// colors on links so it reads warm rather than corporate.
    @ViewBuilder
    private func creditsFooter() -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("Crafted by")
                    .foregroundColor(.white.opacity(0.4))
                inlineLink("Anuj", url: "https://x.com/waahbete")
                Text("·")
                    .foregroundColor(.white.opacity(0.2))
                Text("Powered by")
                    .foregroundColor(.white.opacity(0.4))
                inlineLink("Infisical", url: "https://infisical.com")
            }
            HStack(spacing: 4) {
                Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
                    .foregroundColor(.white.opacity(0.3))
                Text("·")
                    .foregroundColor(.white.opacity(0.2))
                Button {
                    if let url = URL(string: "https://github.com/ptmaroct/kubera") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("Star on GitHub")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.6)
                    }
                    .foregroundColor(Color.vault.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func inlineLink(_ text: String, url: String) -> some View {
        Button {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        } label: {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.vault.accent)
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
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 110, maxWidth: 180, alignment: .trailing)
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
                .lineLimit(1)

            Spacer(minLength: 12)

            trailing()
                .layoutPriority(1)
        }
        .frame(minHeight: 32)
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
            defaultAddEnvironment: defaultAddEnvSlug,
            storeBackend: existingConfig?.storeBackend ?? SecretStoreBackendID.infisical,
            iCloudSyncEnabled: existingConfig?.iCloudSyncEnabled ?? false
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
