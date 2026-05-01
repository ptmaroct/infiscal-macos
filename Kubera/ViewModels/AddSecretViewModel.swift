import Foundation
import KuberaCore

@MainActor
final class AddSecretViewModel: ObservableObject {

    // MARK: - Data from API

    @Published var projects: [InfisicalProject] = []
    @Published var environments: [InfisicalEnvironment] = []
    @Published var tags: [InfisicalTag] = []

    // MARK: - User Selections

    @Published var selectedProject: InfisicalProject?
    @Published var selectedEnvironmentIds: Set<String> = []
    @Published var selectedTagIds: Set<String> = []

    // MARK: - Form Fields

    @Published var key: String = ""
    @Published var value: String = ""
    @Published var comment: String = ""
    @Published var newTagName: String = ""

    /// Optional expiry date — nil = never expires.
    @Published var expiryDate: Date? = nil

    /// Optional URL to the issuing service's API-keys page.
    @Published var serviceURL: String = ""

    /// Tags typed by user that don't exist yet — created on submit
    @Published var pendingTagNames: [String] = []

    // MARK: - UI State

    @Published var isLoadingProjects: Bool = false
    @Published var isLoadingTags: Bool = false
    @Published var isCreating: Bool = false
    @Published var errorMessage: String?

    // MARK: - Computed

    var isValid: Bool {
        !key.isEmpty && !value.isEmpty && selectedProject != nil && !selectedEnvironmentIds.isEmpty
    }

    var selectedEnvironments: [InfisicalEnvironment] {
        environments.filter { selectedEnvironmentIds.contains($0.id) }
    }

    // MARK: - Load Initial Data (cache-first)

    func loadInitialData() async {
        errorMessage = nil

        // 1. Load projects — use cache synchronously, then refresh
        let cached = ProjectCache.shared.projects
        if !cached.isEmpty {
            projects = cached
            preSelectFromConfig()
        } else {
            isLoadingProjects = true
            let fetched = await ProjectCache.shared.fetchProjects()
            projects = fetched
            preSelectFromConfig()
            isLoadingProjects = false

            if projects.isEmpty {
                errorMessage = "No projects found"
                return
            }
        }

        // 2. Load tags — always fetch for the selected project
        if let projectId = selectedProject?.id {
            // Show cached tags immediately if available
            let cachedTags = ProjectCache.shared.cachedTags(for: projectId)
            tags = cachedTags
            if cachedTags.isEmpty { isLoadingTags = true }

            // Always fetch fresh
            let freshTags = await ProjectCache.shared.fetchTags(for: projectId)
            tags = freshTags
            isLoadingTags = false
        }

        // 3. Background refresh projects (non-blocking)
        if !cached.isEmpty {
            Task {
                let fresh = await ProjectCache.shared.fetchProjects()
                if fresh != projects {
                    projects = fresh
                    if selectedProject == nil || !projects.contains(where: { $0.id == selectedProject?.id }) {
                        preSelectFromConfig()
                    }
                }
            }
        }
    }

    private func preSelectFromConfig() {
        guard !projects.isEmpty else { return }

        guard let config = AppConfiguration.load() else {
            selectedProject = projects.first
            if let project = selectedProject {
                applyProjectDefaults(project: project, preferredEnvironmentSlug: nil)
            }
            return
        }

        if config.isAllProjects {
            selectedProject = projects.first
        } else {
            selectedProject = projects.first(where: { $0.id == config.projectId }) ?? projects.first
        }

        if let project = selectedProject {
            // Prefer the saved default-add env, then the configured menu env,
            // and fall back to the project's first env so the form is never
            // stuck without a selection (esp. in All-Environments mode).
            let preferred = config.defaultAddEnvironment ?? (config.isAllEnvironments ? nil : config.environment)
            applyProjectDefaults(project: project, preferredEnvironmentSlug: preferred)
        }
    }

    private func applyProjectDefaults(project: InfisicalProject, preferredEnvironmentSlug: String?) {
        environments = project.environments
        selectedEnvironmentIds = []

        if let preferredEnvironmentSlug,
           let env = environments.first(where: { $0.slug == preferredEnvironmentSlug }) {
            selectedEnvironmentIds = [env.id]
        } else if let first = environments.first {
            selectedEnvironmentIds = [first.id]
        }
    }

    // MARK: - Project Changed

    func onProjectSelected() {
        guard let project = selectedProject else {
            environments = []
            selectedEnvironmentIds = []
            tags = []
            selectedTagIds = []
            pendingTagNames = []
            return
        }

        let defaultSlug = AppConfiguration.load()?.defaultAddEnvironment
        applyProjectDefaults(project: project, preferredEnvironmentSlug: defaultSlug)
        selectedTagIds = []
        pendingTagNames = []

        let cachedTags = ProjectCache.shared.cachedTags(for: project.id)
        tags = cachedTags

        if cachedTags.isEmpty { isLoadingTags = true }
        Task {
            let fresh = await ProjectCache.shared.fetchTags(for: project.id)
            tags = fresh
            isLoadingTags = false
        }
    }

    // MARK: - Environment Toggle

    func toggleEnvironment(_ env: InfisicalEnvironment) {
        if selectedEnvironmentIds.contains(env.id) {
            if selectedEnvironmentIds.count > 1 {
                selectedEnvironmentIds.remove(env.id)
            }
        } else {
            selectedEnvironmentIds.insert(env.id)
        }
    }

    // MARK: - Tag Queueing (local only, no API)

    /// Queue a tag name locally. If it matches an existing tag, select it instead.
    func queueTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // If tag already exists in API tags, just select it
        if let existing = tags.first(where: { $0.displayName.lowercased() == name.lowercased() }) {
            selectedTagIds.insert(existing.id)
            newTagName = ""
            return
        }

        // If already in pending list, skip
        if pendingTagNames.contains(where: { $0.lowercased() == name.lowercased() }) {
            newTagName = ""
            return
        }

        pendingTagNames.append(name)
        newTagName = ""
    }

    /// Remove a pending tag by name
    func removePendingTag(_ name: String) {
        pendingTagNames.removeAll { $0 == name }
    }

    // MARK: - Create Secret (creates pending tags first, then secret)

    func createSecret() async -> Bool {
        guard let project = selectedProject,
              !selectedEnvironmentIds.isEmpty else {
            errorMessage = "Select a project and at least one environment"
            return false
        }

        guard !key.isEmpty, !value.isEmpty else {
            errorMessage = "Secret name and value are required"
            return false
        }

        isCreating = true
        errorMessage = nil

        let config = AppConfiguration.load() ?? AppConfiguration(projectId: project.id)
        let store = SecretStoreFactory.make(for: config)

        // 1. Create any pending tags in PARALLEL
        var allTagIds = selectedTagIds
        if !pendingTagNames.isEmpty {
            let tagNames = pendingTagNames
            let projectId = project.id

            await withTaskGroup(of: InfisicalTag?.self) { group in
                for tagName in tagNames {
                    group.addTask {
                        try? await store.createTag(
                            name: tagName,
                            color: "#F5A524",
                            projectId: projectId
                        )
                    }
                }
                for await result in group {
                    if let newTag = result {
                        allTagIds.insert(newTag.id)
                        tags.append(newTag)
                        ProjectCache.shared.addTag(newTag, for: projectId)
                    }
                }
            }
        }

        // 2. Create the secret in each selected environment in PARALLEL
        let envsToCreate = selectedEnvironments
        let secretKey = key
        let secretValue = value
        let secretComment = comment
        let tagIdArray = Array(allTagIds)
        let projectId = project.id
        let expiry = expiryDate
        let serviceURLValue = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let serviceURLArg: String? = serviceURLValue.isEmpty ? nil : serviceURLValue

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for env in envsToCreate {
                    group.addTask {
                        try await store.createSecret(
                            name: secretKey,
                            value: secretValue,
                            comment: secretComment,
                            tagIds: tagIdArray,
                            expiryDate: expiry,
                            serviceURL: serviceURLArg,
                            environment: env.slug,
                            projectId: projectId,
                            secretPath: "/"
                        )
                    }
                }
                try await group.waitForAll()
            }
            pendingTagNames = []
            isCreating = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
            return false
        }
    }
}
