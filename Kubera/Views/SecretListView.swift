import SwiftUI
import KuberaCore

struct SecretListView: View {
    static let windowWidth: CGFloat = 780
    static let windowHeight: CGFloat = 620

    @ObservedObject var appViewModel: AppViewModel
    @StateObject private var listVM: SecretListViewModel
    let onClose: () -> Void

    @State private var showDeleteAlert = false

    init(viewModel: AppViewModel, onClose: @escaping () -> Void) {
        self.appViewModel = viewModel
        self._listVM = StateObject(wrappedValue: SecretListViewModel(appViewModel: viewModel))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color.vault.bg.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 14)

                filterPanel
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                glassCard {
                    if appViewModel.isLoading && appViewModel.secrets.isEmpty {
                        loadingState
                    } else if listVM.filteredSecrets.isEmpty {
                        emptyState
                    } else {
                        secretList
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: Self.windowWidth, height: Self.windowHeight)
        .sheet(item: $listVM.editingSecret) { secret in
            EditSecretSheet(
                secret: secret,
                listVM: listVM,
                onSave: {
                    Task { await listVM.saveEdit() }
                },
                onCancel: {
                    listVM.editingSecret = nil
                }
            )
        }
        .alert("Delete Secret", isPresented: $showDeleteAlert, presenting: listVM.deletingSecret) { secret in
            Button("Cancel", role: .cancel) {
                listVM.deletingSecret = nil
            }
            Button("Delete", role: .destructive) {
                Task { await listVM.executeDelete() }
            }
        } message: { secret in
            Text("Permanently delete \"\(secret.key)\"? This cannot be undone.")
        }
        .onChange(of: listVM.deletingSecret) { newValue in
            showDeleteAlert = newValue != nil
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("All Secrets")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))

                HStack(spacing: 6) {
                    Text(summaryProjectText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.48))

                    Text("/")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.24))

                    Text(summaryEnvironmentText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.vault.accent)

                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.24))

                    Text("\(listVM.filteredCount) of \(listVM.totalCount) secrets")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.36))
                }
            }

            Spacer()

            Button {
                Task { await appViewModel.loadSecrets() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.vault.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }

    private var filterPanel: some View {
        glassCard {
            VStack(spacing: 10) {
                searchField

                Divider().opacity(0.2)

                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.vault.accent)
                        projectFilterMenu
                    }
                    .frame(width: 230, alignment: .leading)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 28)

                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.vault.accent)
                        environmentTabs
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    clearFilterButton
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.vault.textTertiary)

            TextField("Filter by name, comment, or tag...", text: $listVM.searchText)
                .font(.system(size: 13))
                .foregroundColor(Color.vault.text)
                .textFieldStyle(.plain)

            if !listVM.searchText.isEmpty {
                Button {
                    listVM.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.vault.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.vault.bg.opacity(0.7))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var projectFilterMenu: some View {
        Menu {
            Button {
                listVM.selectedProjectId = nil
            } label: {
                HStack {
                    Text("All Projects")
                    if listVM.selectedProjectId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !listVM.projectFilters.isEmpty {
                Divider()
            }

            ForEach(listVM.projectFilters) { project in
                Button {
                    listVM.selectedProjectId = project.id
                } label: {
                    HStack {
                        Text(project.name)
                        Text("(\(project.count))")
                        if listVM.selectedProjectId == project.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            dropdownPill(text: selectedProjectName)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var environmentTabs: some View {
        FlowLayout(spacing: 6, rowSpacing: 6) {
            filterChip(
                title: "All",
                count: listVM.environmentFilterTotalCount,
                isSelected: listVM.selectedEnvironment == nil,
                accent: Color.vault.accent
            ) {
                listVM.selectedEnvironment = nil
            }

            ForEach(listVM.environmentFilters) { env in
                filterChip(
                    title: env.slug.uppercased(),
                    count: env.count,
                    isSelected: listVM.selectedEnvironment == env.slug,
                    accent: EnvBadge.foreground(for: env.slug)
                ) {
                    listVM.selectedEnvironment = env.slug
                }
            }
        }
    }

    private var clearFilterButton: some View {
        Button {
            listVM.clearFilters()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.32))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Clear filters")
        .opacity(listVM.activeFilterCount > 0 || !listVM.searchText.isEmpty ? 1 : 0)
    }

    private var summaryProjectText: String {
        selectedProjectName == "All Projects" ? "All Projects" : selectedProjectName
    }

    private var summaryEnvironmentText: String {
        listVM.selectedEnvironment?.uppercased() ?? "ALL ENVS"
    }

    private var selectedProjectName: String {
        guard let selectedProjectId = listVM.selectedProjectId else { return "All Projects" }
        return listVM.projectFilters.first(where: { $0.id == selectedProjectId })?.name ?? "Project"
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Color.vault.surface.opacity(0.72))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func filterRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(Color.vault.accent)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.52))
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func dropdownPill(text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 120, maxWidth: 170, alignment: .leading)

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

    private func filterChip(title: String, count: Int, isSelected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.75)
            }
            .foregroundColor(isSelected ? Color.vault.bg : accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? accent : accent.opacity(0.14))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accent.opacity(isSelected ? 1 : 0.38), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secret List

    private var secretList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(listVM.filteredSecrets, id: \.stableListIdentity) { secret in
                    SecretRow(
                        secret: secret,
                        isCopied: listVM.copiedSecretId == secret.id,
                        onCopy: { listVM.copy(secret) },
                        onEdit: { listVM.beginEditing(secret) },
                        onDelete: { listVM.confirmDelete(secret) }
                    )

                    Rectangle()
                        .fill(Color.vault.border)
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading secrets...")
                .font(.system(size: 13))
                .foregroundColor(Color.vault.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color.vault.textTertiary)

            if listVM.searchText.isEmpty {
                Text("No secrets found")
                    .font(.system(size: 14))
                    .foregroundColor(Color.vault.textSecondary)
            } else {
                Text("No secrets match \"\(listVM.searchText)\"")
                    .font(.system(size: 14))
                    .foregroundColor(Color.vault.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Secret Row

struct SecretRow: View {
    let secret: SecretItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: key, comment, tags
            VStack(alignment: .leading, spacing: 6) {
                // Key name + env badge
                HStack(spacing: 6) {
                    Text(secret.key)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.vault.text)
                        .lineLimit(1)

                    if let projectName = secret.projectName, !projectName.isEmpty {
                        ProjectBadge(name: projectName)
                    }

                    if let env = secret.environment {
                        EnvBadge(slug: env)
                    }
                }

                // Comment + Tags row
                HStack(spacing: 8) {
                    if let comment = secret.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 11))
                            .foregroundColor(Color.vault.textSecondary)
                            .lineLimit(1)
                    }

                    if let tags = secret.tags, !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags) { tag in
                                TagChip(tag: tag)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            // Right: version + actions
            HStack(spacing: 6) {
                // Version badge
                if let version = secret.version {
                    Text("v\(version)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.vault.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.vault.border)
                        .cornerRadius(4)
                }

                // Copy
                Button(action: onCopy) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isCopied ? Color.vault.success : Color.vault.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(isHovered ? Color.vault.surface : .clear)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                // Edit
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.vault.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(isHovered ? Color.vault.surface : .clear)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Edit secret")

                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.vault.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(isHovered ? Color.vault.surface : .clear)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(isHovered ? Color.vault.surfaceHover.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        // Row click opens edit. Action buttons (Copy, Edit, Delete) consume their
        // own taps so they still trigger their dedicated handlers.
        .onTapGesture { onEdit() }
    }
}

// MARK: - Project Badge

struct ProjectBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.55))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.07))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

// MARK: - Environment Badge

struct EnvBadge: View {
    let slug: String

    var body: some View {
        Text(slug.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundColor(EnvBadge.foreground(for: slug))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(EnvBadge.background(for: slug))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(EnvBadge.foreground(for: slug).opacity(0.4), lineWidth: 1)
            )
    }

    /// Color derived from env slug. Well-known names get curated colors;
    /// anything else hashes to a stable hue so different envs stay distinguishable.
    static func foreground(for slug: String) -> Color {
        let s = slug.lowercased()
        switch s {
        case "prod", "production": return Color(red: 0.96, green: 0.42, blue: 0.42)
        case "staging", "stage", "stg": return Color(red: 0.95, green: 0.75, blue: 0.30)
        case "dev", "development": return Color(red: 0.40, green: 0.78, blue: 0.50)
        case "test", "testing", "qa": return Color(red: 0.55, green: 0.72, blue: 0.95)
        case "preview": return Color(red: 0.78, green: 0.55, blue: 0.95)
        default:
            let hue = Double(abs(s.hashValue) % 360) / 360.0
            return Color(hue: hue, saturation: 0.55, brightness: 0.85)
        }
    }

    static func background(for slug: String) -> Color {
        foreground(for: slug).opacity(0.18)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: SecretTag

    var body: some View {
        Text(tag.displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(Color.vault.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.vault.accent.opacity(0.12))
            .cornerRadius(4)
    }
}

// MARK: - Edit Secret Sheet

struct EditSecretSheet: View {
    let secret: SecretItem
    @ObservedObject var listVM: SecretListViewModel
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var isAddingTag = false

    private var parsedURL: URL? {
        let trimmed = listVM.editServiceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color.vault.bg.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 16)

                VStack(spacing: 12) {
                    VaultTextField(
                        label: "Value",
                        text: $listVM.editValue,
                        isMonospaced: true,
                        isSecure: true,
                        placeholder: "Secret value"
                    )

                    VaultTextEditor(
                        label: "Comment",
                        text: $listVM.editComment,
                        placeholder: "Optional description...",
                        lineCount: 3
                    )

                    HStack(alignment: .top, spacing: 10) {
                        expirySection
                        serviceURLSection
                    }

                    tagSection
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 16)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 460, height: 560)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        let projectName = secret.projectName ?? AppConfiguration.load()?.projectName ?? "Project"
        let envSlug = secret.environment ?? AppConfiguration.load()?.environment ?? AppConfiguration.defaultEnvironment
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Secret")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.vault.text)

                HStack(spacing: 6) {
                    Text(secret.key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.vault.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(Color.vault.textTertiary)
                    Text(projectName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.vault.textSecondary)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(Color.vault.textTertiary)
                    Text(envSlug)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.vault.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    // MARK: - Expiry & Service URL

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXPIRES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.vault.textSecondary)
                .tracking(1.2)

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(Color.vault.textTertiary)

                if let date = listVM.editExpiryDate {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { date },
                            set: { listVM.editExpiryDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)

                    Spacer()

                    Button {
                        listVM.editExpiryDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.vault.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear expiry")
                } else {
                    Button {
                        listVM.editExpiryDate = Calendar.current.date(byAdding: .day, value: 90, to: Date())
                    } label: {
                        Text("Set expiry date")
                            .font(.system(size: 12))
                            .foregroundColor(Color.vault.accent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.vault.bg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.vault.border, lineWidth: 1)
            )
        }
    }

    private var serviceURLSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SERVICE URL")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.vault.textSecondary)
                .tracking(1.2)

            HStack(spacing: 0) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(Color.vault.textTertiary)
                    .padding(.trailing, 8)

                TextField("https://platform.example.com/api-keys", text: $listVM.editServiceURL)
                    .font(.system(size: 13))
                    .foregroundColor(Color.vault.text)
                    .textFieldStyle(.plain)

                if let url = parsedURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                            .foregroundColor(Color.vault.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.vault.bg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.vault.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.vault.textSecondary)
                .tracking(1.2)

            if listVM.editIsLoadingTags && listVM.editTags.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    Text("Loading...")
                        .font(.system(size: 11))
                        .foregroundColor(Color.vault.textTertiary)
                }
            } else {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(listVM.editTags) { tag in
                        tagChip(tag)
                    }

                    ForEach(listVM.editPendingTagNames, id: \.self) { name in
                        pendingChip(name)
                    }

                    if isAddingTag {
                        addTagField
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.2)) {
                                isAddingTag = true
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Add")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color.vault.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.vault.surface)
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.vault.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var addTagField: some View {
        HStack(spacing: 4) {
            BackspaceTextField(
                text: $listVM.editNewTagName,
                placeholder: "Tag name...",
                onBackspaceEmpty: {
                    if !listVM.editPendingTagNames.isEmpty {
                        withAnimation(.spring(response: 0.2)) {
                            _ = listVM.editPendingTagNames.removeLast()
                        }
                    } else {
                        withAnimation(.spring(response: 0.2)) {
                            isAddingTag = false
                        }
                    }
                },
                onSubmit: {
                    listVM.queueEditTag()
                },
                onSeparator: {
                    listVM.queueEditTag()
                }
            )
            .frame(width: 90)

            Button {
                listVM.editNewTagName = ""
                withAnimation(.spring(response: 0.2)) {
                    isAddingTag = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.vault.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.vault.bg)
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.vault.accent.opacity(0.4), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
    }

    private func tagChip(_ tag: InfisicalTag) -> some View {
        let isSelected = listVM.editSelectedTagIds.contains(tag.id)
        return Button {
            withAnimation(.spring(response: 0.2)) {
                listVM.toggleEditTag(tag)
            }
        } label: {
            Text(tag.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? Color.vault.bg : Color.vault.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isSelected ? Color.vault.accent : Color.vault.surface)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.vault.accent : Color.vault.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func pendingChip(_ name: String) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.vault.accent)
            Button {
                withAnimation(.spring(response: 0.2)) {
                    listVM.removeEditPendingTag(name)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color.vault.accent.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.vault.accentSoft)
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(Color.vault.accent.opacity(0.3))
        )
    }

    // MARK: - Footer

    private var isDirty: Bool {
        let originalURL = secret.serviceURL?.absoluteString ?? ""
        let originalTagIds = Set((secret.tags ?? []).map(\.id))
        return listVM.editValue != secret.value
            || listVM.editComment != (secret.comment ?? "")
            || listVM.editExpiryDate != secret.expiryDate
            || listVM.editServiceURL.trimmingCharacters(in: .whitespacesAndNewlines) != originalURL
            || listVM.editSelectedTagIds != originalTagIds
            || !listVM.editPendingTagNames.isEmpty
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("⌘↵ to save")
                .font(.system(size: 10))
                .foregroundColor(Color.vault.textTertiary)

            Spacer()

            VaultButton(title: "Cancel", style: .ghost) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            VaultButton(
                title: listVM.isUpdating ? "Saving..." : "Save Changes",
                style: .primary,
                isLoading: listVM.isUpdating,
                isDisabled: listVM.editValue.isEmpty || !isDirty
            ) {
                onSave()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
