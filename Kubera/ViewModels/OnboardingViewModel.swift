import Foundation
import KuberaCore

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step {
        case welcome
        case backendChoice    // pick local vs Infisical
        case cliCheck
        case configure
        case done
    }

    enum CLIStatus {
        case checking
        case installed
        case notInstalled
        case notLoggedIn
    }

    enum Backend { case local, infisical }

    @Published var currentStep: Step = .welcome
    @Published var cliStatus: CLIStatus = .checking
    @Published var selectedBackend: Backend = .local

    // Data fetched from API
    @Published var organizations: [InfisicalOrg] = []
    @Published var projects: [InfisicalProject] = []
    @Published var environments: [InfisicalEnvironment] = []

    // User selections
    @Published var selectedOrg: InfisicalOrg?
    @Published var selectedProject: InfisicalProject?
    @Published var selectedEnvironment: InfisicalEnvironment?
    @Published var secretPath: String = AppConfiguration.defaultSecretPath

    @Published var isLoadingData: Bool = false
    @Published var errorMessage: String?
    @Published var isSaving: Bool = false

    func checkCLI() async {
        cliStatus = .checking

        guard InfisicalCLIService.isInstalled() else {
            cliStatus = .notInstalled
            return
        }

        let loggedIn = await InfisicalCLIService.isLoggedIn()
        if loggedIn {
            cliStatus = .installed
            // Auto-advance: fetch orgs and go to configure
            await fetchOrganizations()
            currentStep = .configure
        } else {
            cliStatus = .notLoggedIn
        }
    }

    func fetchOrganizations() async {
        isLoadingData = true
        errorMessage = nil
        do {
            organizations = try await InfisicalCLIService.fetchOrganizations()
            // Auto-select if only one org
            if organizations.count == 1 {
                selectedOrg = organizations.first
                await fetchProjects()
            }
        } catch {
            errorMessage = "Failed to load organizations: \(error.localizedDescription)"
        }
        isLoadingData = false
    }

    func fetchProjects() async {
        guard let org = selectedOrg else { return }
        isLoadingData = true
        errorMessage = nil
        do {
            projects = try await InfisicalCLIService.fetchProjects(orgId: org.id)
            selectedProject = nil
            selectedEnvironment = nil
            environments = []
        } catch {
            errorMessage = "Failed to load projects: \(error.localizedDescription)"
        }
        isLoadingData = false
    }

    func onProjectSelected() {
        guard let project = selectedProject else {
            environments = []
            selectedEnvironment = nil
            return
        }
        environments = project.environments
        // Auto-select first environment
        selectedEnvironment = environments.first
    }

    func save() async -> Bool {
        guard let project = selectedProject,
              let env = selectedEnvironment else {
            errorMessage = "Select a project and environment"
            return false
        }

        isSaving = true
        errorMessage = nil

        // Verify it works
        do {
            _ = try await InfisicalCLIService.listSecretsViaAPI(
                environment: env.slug,
                projectId: project.id,
                secretPath: secretPath
            )
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }

        let config = AppConfiguration(
            projectId: project.id,
            environment: env.slug,
            secretPath: secretPath,
            baseURL: AppConfiguration.defaultBaseURL,
            projectName: project.name,
            organizationId: selectedOrg?.id,
            storeBackend: SecretStoreBackendID.infisical
        )
        config.save()
        isSaving = false
        return true
    }

    /// One-tap commit for the local backend: bootstraps `KeychainSecretStore`
    /// (creates the encrypted file + master key on first use), then writes a
    /// matching `AppConfiguration`. Skips the project/env picker because the
    /// local store ships a fixed `Local` project with `dev`/`stg`/`prod` envs.
    func saveLocalBackend() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let store = KeychainSecretStore()
        do {
            // Force initialisation — listProjects() loads (or creates) the file
            // and validates that the Keychain master key works.
            _ = try await store.listProjects()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        AppConfiguration.defaultLocal().save()
        return true
    }
}
