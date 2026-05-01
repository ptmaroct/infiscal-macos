import Foundation

/// In-memory cache for projects, tags, and org data.
/// Shows cached data instantly, refreshes silently in background.
@MainActor
final class ProjectCache {
    static let shared = ProjectCache()

    private(set) var projects: [InfisicalProject] = []
    private(set) var lastProjectsFetchedAt: Date?
    private var isFetchingProjects = false

    /// Tags cached per project ID
    private var tagsCache: [String: [InfisicalTag]] = [:]
    private var tagsLastFetchedAt: [String: Date] = [:]
    private var isFetchingTags: Set<String> = []

    private init() {}

    // MARK: - Projects

    var cachedProjects: [InfisicalProject] {
        if projects.isEmpty || isProjectsStale {
            Task { await fetchProjects() }
        }
        return projects
    }

    private var isProjectsStale: Bool {
        guard let last = lastProjectsFetchedAt else { return true }
        return Date().timeIntervalSince(last) > 60
    }

    @discardableResult
    func fetchProjects() async -> [InfisicalProject] {
        guard !isFetchingProjects else { return projects }
        isFetchingProjects = true
        defer { isFetchingProjects = false }

        do {
            let orgs = try await InfisicalCLIService.fetchOrganizations()
            guard let org = orgs.first else { return projects }
            let fetched = try await InfisicalCLIService.fetchProjects(orgId: org.id)
            projects = fetched
            lastProjectsFetchedAt = Date()
        } catch {
            // Keep stale data on failure
        }
        return projects
    }

    // MARK: - Tags

    /// Get cached tags for a project. Returns cached instantly, refreshes in background if stale.
    func cachedTags(for projectId: String) -> [InfisicalTag] {
        let cached = tagsCache[projectId] ?? []
        if cached.isEmpty || isTagsStale(for: projectId) {
            Task { await fetchTags(for: projectId) }
        }
        return cached
    }

    private func isTagsStale(for projectId: String) -> Bool {
        guard let last = tagsLastFetchedAt[projectId] else { return true }
        return Date().timeIntervalSince(last) > 60
    }

    @discardableResult
    func fetchTags(for projectId: String) async -> [InfisicalTag] {
        guard !isFetchingTags.contains(projectId) else { return tagsCache[projectId] ?? [] }
        isFetchingTags.insert(projectId)
        defer { isFetchingTags.remove(projectId) }

        do {
            let baseURL = AppConfiguration.load()?.baseURL ?? AppConfiguration.defaultBaseURL
            let fetched = try await InfisicalCLIService.fetchTags(projectId: projectId, baseURL: baseURL)
            tagsCache[projectId] = fetched
            tagsLastFetchedAt[projectId] = Date()
        } catch {
            // Keep stale data
        }
        return tagsCache[projectId] ?? []
    }

    /// Add a newly created tag to the cache
    func addTag(_ tag: InfisicalTag, for projectId: String) {
        tagsCache[projectId, default: []].append(tag)
    }

    // MARK: - Clear

    func clear() {
        projects = []
        lastProjectsFetchedAt = nil
        tagsCache = [:]
        tagsLastFetchedAt = [:]
    }
}
