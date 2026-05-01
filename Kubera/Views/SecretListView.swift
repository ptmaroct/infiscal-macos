import SwiftUI

struct SecretListView: View {
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
            WindowBackground()

            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                // Divider
                Rectangle()
                    .fill(Color.vault.border)
                    .frame(height: 1)

                // Secret list
                if appViewModel.isLoading && appViewModel.secrets.isEmpty {
                    loadingState
                } else if listVM.filteredSecrets.isEmpty {
                    emptyState
                } else {
                    secretList
                }
            }
        }
        .frame(minWidth: 620, minHeight: 400)
        .sheet(item: $listVM.editingSecret) { secret in
            EditSecretSheet(
                secret: secret,
                value: $listVM.editValue,
                comment: $listVM.editComment,
                expiryDate: $listVM.editExpiryDate,
                serviceURL: $listVM.editServiceURL,
                isUpdating: listVM.isUpdating,
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All Secrets")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.vault.text)

                    if let config = AppConfiguration.load() {
                        HStack(spacing: 6) {
                            Text(config.projectName ?? "Project")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.vault.textSecondary)

                            Text("/")
                                .font(.system(size: 11))
                                .foregroundColor(Color.vault.textTertiary)

                            Text(config.environment)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.vault.accent)

                            Text("·")
                                .font(.system(size: 11))
                                .foregroundColor(Color.vault.textTertiary)

                            Text("\(appViewModel.secrets.count) secrets")
                                .font(.system(size: 11))
                                .foregroundColor(Color.vault.textTertiary)
                        }
                    }
                }

                Spacer()

                // Refresh button
                Button {
                    Task { await appViewModel.loadSecrets() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.vault.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.vault.surface)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.vault.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            // Search bar
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
            .padding(.vertical, 8)
            .background(Color.vault.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.vault.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Secret List

    private var secretList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(listVM.filteredSecrets) { secret in
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
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.vault.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(isHovered ? Color.vault.surface : .clear)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

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
        .onHover { hovering in
            isHovered = hovering
        }
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
    @Binding var value: String
    @Binding var comment: String
    @Binding var expiryDate: Date?
    @Binding var serviceURL: String
    let isUpdating: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var parsedURL: URL? {
        let trimmed = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            Color.vault.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Secret")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.vault.text)

                    Text(secret.key)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.vault.accent)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Value field
                        VaultTextField(
                            label: "Value",
                            text: $value,
                            isMonospaced: true,
                            isSecure: true,
                            placeholder: "Secret value"
                        )

                        // Comment field
                        VaultTextEditor(
                            label: "Comment",
                            text: $comment,
                            placeholder: "Optional description...",
                            lineCount: 2
                        )

                        // Expiry
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EXPIRES")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.vault.textSecondary)
                                .tracking(1.2)

                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.vault.textTertiary)

                                if let date = expiryDate {
                                    DatePicker(
                                        "",
                                        selection: Binding(
                                            get: { date },
                                            set: { expiryDate = $0 }
                                        ),
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                    .datePickerStyle(.compact)

                                    Spacer()

                                    Button {
                                        expiryDate = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.vault.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Clear expiry")
                                } else {
                                    Button {
                                        expiryDate = Calendar.current.date(byAdding: .day, value: 90, to: Date())
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

                        // Service URL
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

                                TextField("https://platform.example.com/api-keys", text: $serviceURL)
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
                }

                // Actions
                HStack {
                    Spacer()

                    VaultButton(title: "Cancel", style: .secondary) {
                        onCancel()
                    }

                    VaultButton(
                        title: isUpdating ? "Saving..." : "Save Changes",
                        style: .primary,
                        isLoading: isUpdating,
                        isDisabled: value.isEmpty
                    ) {
                        onSave()
                    }
                }
            }
            .padding(28)
        }
        .frame(width: 460, height: 560)
    }
}
