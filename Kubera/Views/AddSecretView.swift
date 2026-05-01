import SwiftUI
import AppKit

struct AddSecretView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var addVM = AddSecretViewModel()
    let onDismiss: () -> Void

    /// Button state: idle → creating → success → idle
    enum ButtonState {
        case idle, creating, success
    }
    @State private var buttonState: ButtonState = .idle

    var body: some View {
        ZStack {
            WindowBackground()
            formContent
        }
        .frame(width: 480, height: 660)
        .preferredColorScheme(.dark)
        .onAppear {
            Task { await addVM.loadInitialData() }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Secret")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.vault.text)
                Spacer()
                Image(systemName: "plus.square.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color.vault.accent.opacity(0.5))
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    contextRow

                    Rectangle()
                        .fill(Color.vault.border)
                        .frame(height: 1)
                        .padding(.vertical, 2)

                    VaultTextField(label: "Secret Name", text: $addVM.key, isMonospaced: true, placeholder: "e.g. API_KEY")
                    VaultTextField(label: "Secret Value", text: $addVM.value, isSecure: true, placeholder: "Enter value")

                    VaultTextEditor(
                        label: "Comment",
                        text: $addVM.comment,
                        placeholder: "Optional description...",
                        lineCount: 2
                    )

                    expirySection

                    serviceURLSection

                    tagSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            }

            if let error = addVM.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                .foregroundColor(Color.vault.error)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
                .transition(.opacity)
            }

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Context Row (Project left ← → Environment right)

    private var contextRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // Project
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.vault.textTertiary)
                    .tracking(1.2)

                if addVM.isLoadingProjects {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                        Text("Loading...")
                            .font(.system(size: 11))
                            .foregroundColor(Color.vault.textTertiary)
                    }
                } else {
                    Menu {
                        ForEach(addVM.projects) { project in
                            Button {
                                addVM.selectedProject = project
                                addVM.onProjectSelected()
                            } label: {
                                HStack {
                                    Text(project.name)
                                    if addVM.selectedProject?.id == project.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color.vault.accent)
                            Text(addVM.selectedProject?.name ?? "Select...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.vault.text)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Color.vault.textTertiary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            Spacer()

            // Environment — segmented button group
            if !addVM.environments.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ENVIRONMENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.vault.textTertiary)
                        .tracking(1.2)

                    HStack(spacing: 0) {
                        ForEach(Array(addVM.environments.enumerated()), id: \.element.id) { index, env in
                            let isSelected = addVM.selectedEnvironmentIds.contains(env.id)
                            Button {
                                withAnimation(.spring(response: 0.25)) {
                                    addVM.toggleEnvironment(env)
                                }
                            } label: {
                                Text(env.name)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? Color.vault.bg : Color.vault.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.vault.accent : Color.vault.surface)
                            }
                            .buttonStyle(.plain)

                            if index < addVM.environments.count - 1 {
                                Rectangle()
                                    .fill(Color.vault.border)
                                    .frame(width: 1)
                            }
                        }
                    }
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.vault.border, lineWidth: 1)
                    )
                }
            }
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

                if let date = addVM.expiryDate {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { date },
                            set: { addVM.expiryDate = $0 }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)

                    Spacer()

                    Button {
                        addVM.expiryDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.vault.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear expiry")
                } else {
                    Button {
                        let cal = Calendar.current
                        addVM.expiryDate = cal.date(byAdding: .day, value: 90, to: Date())
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

                TextField("https://platform.example.com/api-keys", text: $addVM.serviceURL)
                    .font(.system(size: 13))
                    .foregroundColor(Color.vault.text)
                    .textFieldStyle(.plain)

                if let url = parsedServiceURL {
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

    private var parsedServiceURL: URL? {
        let trimmed = addVM.serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    // MARK: - Tags

    @State private var isAddingTag = false

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.vault.textSecondary)
                .tracking(1.2)

            if addVM.isLoadingTags && addVM.tags.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    Text("Loading...")
                        .font(.system(size: 11))
                        .foregroundColor(Color.vault.textTertiary)
                }
            } else {
                // Single row: existing tags + pending tags + add button
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Existing API tags — click to toggle
                        ForEach(addVM.tags) { tag in
                            tagChip(tag)
                        }

                        // Pending new tags — shown with × to remove
                        ForEach(addVM.pendingTagNames, id: \.self) { name in
                            pendingChip(name)
                        }

                        // Inline add: either text field or + button
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
    }

    /// Inline text field for adding a new tag
    private var addTagField: some View {
        HStack(spacing: 4) {
            BackspaceTextField(
                text: $addVM.newTagName,
                placeholder: "Tag name...",
                onBackspaceEmpty: {
                    // If empty and backspace, close the field or remove last pending
                    if !addVM.pendingTagNames.isEmpty {
                        withAnimation(.spring(response: 0.2)) {
                            _ = addVM.pendingTagNames.removeLast()
                        }
                    } else {
                        withAnimation(.spring(response: 0.2)) {
                            isAddingTag = false
                        }
                    }
                },
                onSubmit: {
                    addVM.queueTag()
                },
                onSeparator: {
                    addVM.queueTag()
                }
            )
            .frame(width: 90)

            // Dismiss
            Button {
                addVM.newTagName = ""
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

    /// Existing tag chip — toggles selection
    private func tagChip(_ tag: InfisicalTag) -> some View {
        let isSelected = addVM.selectedTagIds.contains(tag.id)
        return Button {
            _ = withAnimation(.spring(response: 0.2)) {
                if isSelected {
                    addVM.selectedTagIds.remove(tag.id)
                } else {
                    addVM.selectedTagIds.insert(tag.id)
                }
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

    /// Pending tag chip — removable with ×
    private func pendingChip(_ name: String) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.vault.accent)
            Button {
                withAnimation(.spring(response: 0.2)) {
                    addVM.removePendingTag(name)
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

    private var footer: some View {
        HStack {
            VaultButton(title: "Cancel", style: .ghost) {
                onDismiss()
            }

            Spacer()

            // Animated create button: idle → creating → success ✓ → idle
            Button {
                guard buttonState == .idle else { return }
                Task {
                    withAnimation(.spring(response: 0.3)) { buttonState = .creating }
                    let success = await addVM.createSecret()
                    if success {
                        await viewModel.loadSecrets()

                        // Show success state
                        withAnimation(.spring(response: 0.3)) { buttonState = .success }

                        // Clear form
                        addVM.key = ""
                        addVM.value = ""
                        addVM.comment = ""
                        addVM.expiryDate = nil
                        addVM.serviceURL = ""
                        addVM.selectedTagIds = []
                        addVM.pendingTagNames = []

                        // Revert to idle after 1.5s
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.spring(response: 0.3)) { buttonState = .idle }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3)) { buttonState = .idle }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    switch buttonState {
                    case .idle:
                        Text("Create Secret")
                            .font(.system(size: 13, weight: .semibold))
                    case .creating:
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                        Text("Creating...")
                            .font(.system(size: 13, weight: .semibold))
                    case .success:
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Created!")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .foregroundColor(buttonState == .success ? .white : Color.vault.bg)
                .background(buttonState == .success ? Color.vault.success : Color.vault.accent)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(buttonState == .success ? Color.vault.success : Color.vault.accent, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(buttonState != .idle || !addVM.isValid)
            .opacity(!addVM.isValid && buttonState == .idle ? 0.4 : 1.0)
        }
    }
}

// MARK: - BackspaceTextField (NSTextField wrapper that detects backspace on empty)

struct BackspaceTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onBackspaceEmpty: () -> Void
    var onSubmit: () -> Void
    var onSeparator: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = BackspaceNSTextField()
        field.delegate = context.coordinator
        field.onBackspaceEmpty = onBackspaceEmpty
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = NSColor.white.withAlphaComponent(0.92)
        field.focusRingType = .none
        field.cell?.lineBreakMode = .byClipping
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        if let field = nsView as? BackspaceNSTextField {
            field.onBackspaceEmpty = onBackspaceEmpty
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: BackspaceTextField

        init(_ parent: BackspaceTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let val = field.stringValue
            if val.hasSuffix(",") || val.hasSuffix(";") {
                DispatchQueue.main.async {
                    self.parent.text = String(val.dropLast()).trimmingCharacters(in: .whitespaces)
                    self.parent.onSeparator()
                }
            } else {
                parent.text = val
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// NSTextField subclass that intercepts backspace when empty
class BackspaceNSTextField: NSTextField {
    var onBackspaceEmpty: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // keyCode 51 = backspace
        if event.keyCode == 51 && stringValue.isEmpty {
            onBackspaceEmpty?()
            return
        }
        super.keyDown(with: event)
    }
}
