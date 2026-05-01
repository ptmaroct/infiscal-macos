import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var onboarding = OnboardingViewModel()
    let onDismiss: () -> Void

    @State private var appeared = false

    private var stepIndex: Int {
        switch onboarding.currentStep {
        case .welcome: return 0
        case .cliCheck: return 1
        case .configure: return 2
        case .done: return 3
        }
    }

    var body: some View {
        ZStack {
            WindowBackground()

            VStack(spacing: 0) {
                // Step indicator
                StepIndicator(totalSteps: 4, currentStep: stepIndex)
                    .padding(.top, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -8)

                // Content
                ZStack {
                    switch onboarding.currentStep {
                    case .welcome:
                        welcomeStep
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.combined(with: .offset(x: -30))
                            ))
                    case .cliCheck:
                        cliCheckStep
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 30)),
                                removal: .opacity.combined(with: .offset(x: -30))
                            ))
                    case .configure:
                        configureStep
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 30)),
                                removal: .opacity.combined(with: .offset(x: -30))
                            ))
                    case .done:
                        doneStep
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                            ))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: onboarding.currentStep)
            }
        }
        .frame(width: 500, height: 460)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            PulsingKeyIcon()
                .padding(.bottom, 28)

            Text("Kubera")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color.vault.text)
                .padding(.bottom, 8)

            Text("Your secrets, one keystroke away.")
                .font(.system(size: 14))
                .foregroundColor(Color.vault.textSecondary)
                .padding(.bottom, 6)

            Text("Powered by the Infisical CLI")
                .font(.system(size: 11))
                .foregroundColor(Color.vault.textTertiary)

            Spacer()

            VaultButton(title: "Get Started", style: .primary) {
                withAnimation {
                    onboarding.currentStep = .cliCheck
                }
                Task { await onboarding.checkCLI() }
            }
            .padding(.bottom, 16)

            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 9))
                Text("Secrets never touch disk")
                    .font(.system(size: 10))
            }
            .foregroundColor(Color.vault.textTertiary)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - CLI Check

    private var cliCheckStep: some View {
        VStack(spacing: 0) {
            Spacer()

            switch onboarding.cliStatus {
            case .checking, .installed:
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.vault.accent.opacity(0.08))
                            .frame(width: 64, height: 64)

                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Text(onboarding.cliStatus == .checking ? "Detecting CLI..." : "Loading projects...")
                        .font(.system(size: 14))
                        .foregroundColor(Color.vault.textSecondary)
                }

            case .notInstalled:
                cliErrorState(
                    icon: "terminal",
                    title: "CLI Not Found",
                    subtitle: "Install the Infisical CLI to continue",
                    command: "brew install infisical",
                    linkLabel: "Don't have Homebrew?",
                    linkURL: "https://brew.sh"
                )

            case .notLoggedIn:
                cliErrorState(
                    icon: "person.crop.circle.badge.xmark",
                    title: "Not Logged In",
                    subtitle: "Authenticate with Infisical first",
                    command: "infisical login",
                    linkLabel: "Need an account? Sign up →",
                    linkURL: "https://infisical.com/"
                )
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func cliErrorState(icon: String, title: String, subtitle: String, command: String, linkLabel: String? = nil, linkURL: String? = nil) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.vault.warning.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(Color.vault.warning)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.vault.text)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color.vault.textSecondary)
            }

            VaultCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RUN IN TERMINAL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.vault.textTertiary)
                        .tracking(1.5)

                    CLICommandBlock(command: command)
                }
            }
            .padding(.horizontal, 20)

            if let label = linkLabel, let urlString = linkURL, let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.vault.accent)
                }
                .buttonStyle(.plain)
            }

            VaultButton(title: "Re-check", style: .secondary) {
                Task { await onboarding.checkCLI() }
            }
        }
    }

    // MARK: - Configure

    private var configureStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Select Project")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.vault.text)

                Text("Choose where to pull secrets from")
                    .font(.system(size: 12))
                    .foregroundColor(Color.vault.textSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 22)

            if onboarding.isLoadingData {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                VStack(spacing: 16) {
                    // Org picker (if multiple)
                    if onboarding.organizations.count > 1 {
                        VaultPicker(
                            label: "Organization",
                            selection: $onboarding.selectedOrg,
                            options: onboarding.organizations,
                            displayName: { $0.name },
                            icon: "building.2.fill"
                        )
                        .onChange(of: onboarding.selectedOrg) { _ in
                            Task { await onboarding.fetchProjects() }
                        }
                    }

                    VaultPicker(
                        label: "Project",
                        selection: $onboarding.selectedProject,
                        options: onboarding.projects,
                        displayName: { $0.name },
                        icon: "folder.fill"
                    )
                    .onChange(of: onboarding.selectedProject) { _ in
                        onboarding.onProjectSelected()
                    }

                    if !onboarding.environments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ENVIRONMENT")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.vault.textSecondary)
                                .tracking(1.2)

                            HStack(spacing: 6) {
                                ForEach(onboarding.environments) { env in
                                    envPill(env)
                                }
                            }
                        }
                    }

                    VaultTextField(label: "Secret Path", text: $onboarding.secretPath, isMonospaced: true)
                }
                .padding(.horizontal, 32)

                if let error = onboarding.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(Color.vault.error)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .lineLimit(2)
                }

                Spacer()

                HStack {
                    VaultButton(title: "Back", style: .ghost) {
                        withAnimation { onboarding.currentStep = .cliCheck }
                    }

                    Spacer()

                    VaultButton(
                        title: "Connect",
                        style: .primary,
                        isLoading: onboarding.isSaving,
                        isDisabled: onboarding.selectedProject == nil || onboarding.selectedEnvironment == nil
                    ) {
                        Task {
                            let success = await onboarding.save()
                            if success {
                                viewModel.configurationSaved()
                                withAnimation { onboarding.currentStep = .done }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
        }
    }

    private func envPill(_ env: InfisicalEnvironment) -> some View {
        let isSelected = onboarding.selectedEnvironment?.id == env.id
        return Button {
            withAnimation(.spring(response: 0.3)) {
                onboarding.selectedEnvironment = env
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSelected ? Color.vault.bg : Color.vault.accent.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text(env.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Color.vault.bg : Color.vault.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.vault.accent : Color.vault.bg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.vault.accent : Color.vault.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.vault.success.opacity(0.1))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(Color.vault.success.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.vault.success)
            }
            .padding(.bottom, 24)

            Text("You're all set")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color.vault.text)
                .padding(.bottom, 8)

            if let project = onboarding.selectedProject,
               let env = onboarding.selectedEnvironment {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Text("/")
                        .foregroundColor(Color.vault.textTertiary)
                    Text(env.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Color.vault.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.vault.accentSoft)
                .cornerRadius(6)
                .padding(.bottom, 16)
            }

            VaultCard {
                HStack(spacing: 12) {
                    Image(systemName: "menubar.arrow.up.rectangle")
                        .font(.system(size: 16))
                        .foregroundColor(Color.vault.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Click the key icon in your menubar")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.vault.text)
                        Text("or press Cmd + Shift + K")
                            .font(.system(size: 11))
                            .foregroundColor(Color.vault.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 60)

            Spacer()

            VaultButton(title: "Done", style: .primary) {
                onDismiss()
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 40)
    }
}
