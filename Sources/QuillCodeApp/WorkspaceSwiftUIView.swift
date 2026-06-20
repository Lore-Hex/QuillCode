import SwiftUI
import QuillCodeCore

public struct QuillCodeWorkspaceView: View {
    public var surface: WorkspaceSurface
    @Binding public var draft: String
    public var onSend: () -> Void
    public var onSelectThread: (UUID) -> Void
    public var onSelectProject: (UUID?) -> Void
    public var onSetMode: (AgentMode) -> Void
    public var onSetModel: (String) -> Void
    public var onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    public var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    public var onCommand: (WorkspaceCommandSurface) -> Void

    @State private var isSettingsPresented = false
    @State private var isSearchPresented = false
    @State private var searchQuery = ""
    @State private var settingsDraft = QuillCodeSettingsDraft()

    public init(
        surface: WorkspaceSurface,
        draft: Binding<String>,
        onSend: @escaping () -> Void,
        onSelectThread: @escaping (UUID) -> Void,
        onSelectProject: @escaping (UUID?) -> Void,
        onSetMode: @escaping (AgentMode) -> Void,
        onSetModel: @escaping (String) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onReviewAction: @escaping (WorkspaceReviewActionSurface) -> Void,
        onCommand: @escaping (WorkspaceCommandSurface) -> Void
    ) {
        self.surface = surface
        self._draft = draft
        self.onSend = onSend
        self.onSelectThread = onSelectThread
        self.onSelectProject = onSelectProject
        self.onSetMode = onSetMode
        self.onSetModel = onSetModel
        self.onSaveSettings = onSaveSettings
        self.onReviewAction = onReviewAction
        self.onCommand = onCommand
    }

    public var body: some View {
        VStack(spacing: 0) {
            QuillCodeTopBarView(
                topBar: surface.topBar,
                commands: surface.commands,
                onSetMode: onSetMode,
                onSetModel: onSetModel,
                onCommand: handleCommand
            )
            Divider()
            HStack(spacing: 0) {
                QuillCodeSidebarView(
                    projects: surface.projects,
                    sidebar: surface.sidebar,
                    commands: surface.commands,
                    onSelectProject: onSelectProject,
                    onSelectThread: onSelectThread,
                    onCommand: handleCommand
                )
                    .frame(width: 280)
                Divider()
                VStack(spacing: 0) {
                    QuillCodeTranscriptView(
                        transcript: surface.transcript,
                        review: surface.review,
                        onReviewAction: onReviewAction
                    )
                    Divider()
                    QuillCodeComposerView(
                        composer: surface.composer,
                        draft: $draft,
                        onSend: onSend
                    )
                }
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
        .sheet(isPresented: $isSettingsPresented) {
            QuillCodeSettingsView(
                settings: surface.settings,
                draft: $settingsDraft,
                onCancel: {
                    isSettingsPresented = false
                },
                onSave: {
                    onSaveSettings(settingsDraft.update)
                    isSettingsPresented = false
                }
            )
        }
        .sheet(isPresented: $isSearchPresented) {
            QuillCodeSearchView(
                sidebar: surface.sidebar,
                query: $searchQuery,
                onSelectThread: { threadID in
                    onSelectThread(threadID)
                    isSearchPresented = false
                },
                onClose: {
                    isSearchPresented = false
                }
            )
        }
    }

    private func handleCommand(_ command: WorkspaceCommandSurface) {
        if command.id == "settings" {
            settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
            isSettingsPresented = true
        } else if command.id == "search" {
            searchQuery = ""
            isSearchPresented = true
        } else {
            onCommand(command)
        }
    }
}

private struct QuillCodeSearchView: View {
    var sidebar: SidebarSurface
    @Binding var query: String
    var onSelectThread: (UUID) -> Void
    var onClose: () -> Void

    private var results: [SidebarItemSurface] {
        sidebar.filteredItems(matching: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search chats")
                        .font(.title2.weight(.semibold))
                    Text("Find a thread by title, model, or pinned state.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            TextField("Search chats", text: $query)
                .textFieldStyle(.roundedBorder)

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(QuillCodePalette.muted)
                    Text("No matching chats")
                        .font(.headline)
                    Text("Try a thread title, selected model, or pinned.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { item in
                            Button {
                                onSelectThread(item.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isPinned ? "pin.fill" : "text.bubble")
                                        .foregroundStyle(item.isSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Text(item.subtitle + (item.isPinned ? " - pinned" : ""))
                                            .font(.caption)
                                            .foregroundStyle(QuillCodePalette.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if item.isSelected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(QuillCodePalette.blue)
                                    }
                                }
                                .padding(12)
                                .background(item.isSelected ? QuillCodePalette.selection : QuillCodePalette.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(QuillCodePalette.background)
    }
}

private struct QuillCodeTopBarView: View {
    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    var onSetMode: (AgentMode) -> Void
    var onSetModel: (String) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(QuillCodePalette.blue.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(topBar.primaryTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(topBar.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                ForEach(topBar.modelCategories) { category in
                    Section(category.category) {
                        ForEach(category.models) { option in
                            Button {
                                onSetModel(option.id)
                            } label: {
                                HStack {
                                    Text("\(option.provider)/\(option.displayName)")
                                    if option.isSelected {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                QuillCodePill(text: topBar.modelLabel, systemImage: "cpu")
            }
            .buttonStyle(.borderless)
            Menu {
                ForEach(AgentMode.allCases, id: \.rawValue) { mode in
                    Button(mode.title) {
                        onSetMode(mode)
                    }
                }
            } label: {
                QuillCodePill(text: topBar.modeLabel, systemImage: "shield")
            }
            .buttonStyle(.borderless)
            QuillCodePill(text: topBar.agentStatus, systemImage: "waveform.path")
            Menu {
                ForEach(commands) { command in
                    Button(command.title) {
                        onCommand(command)
                    }
                    .disabled(!command.isEnabled)
                    if let shortcut = command.shortcut {
                        Text(shortcut)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .background(QuillCodePalette.panel)
    }
}

private struct QuillCodeSidebarView: View {
    var projects: ProjectListSurface
    var sidebar: SidebarSurface
    var commands: [WorkspaceCommandSurface]
    var onSelectProject: (UUID?) -> Void
    var onSelectThread: (UUID) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuillCodeSidebarActionsView(commands: commands, onCommand: onCommand)
            Divider()
            QuillCodeProjectListView(projects: projects, onSelectProject: onSelectProject)
            Divider()
            Text(sidebar.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            if sidebar.items.isEmpty {
                Text(sidebar.emptyTitle)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sidebar.items) { item in
                            Button {
                                onSelectThread(item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Text(item.subtitle + (item.isPinned ? " - pinned" : ""))
                                        .font(.caption)
                                        .foregroundStyle(QuillCodePalette.muted)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(item.isSelected ? QuillCodePalette.selection : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(QuillCodePalette.sidebar)
    }
}

private struct QuillCodeSidebarActionsView: View {
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    private var visibleCommands: [WorkspaceCommandSurface] {
        commands.filter { ["new-chat", "search"].contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(visibleCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    Label(command.title, systemImage: systemImage(for: command.id))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(QuillCodePalette.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!command.isEnabled)
            }
        }
    }

    private func systemImage(for commandID: String) -> String {
        switch commandID {
        case "new-chat":
            return "square.and.pencil"
        case "search":
            return "magnifyingglass"
        default:
            return "circle"
        }
    }
}

private struct QuillCodeProjectListView: View {
    var projects: ProjectListSurface
    var onSelectProject: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(projects.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
                Button {
                    onSelectProject(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(QuillCodePalette.muted)
                .help("Clear project")
            }
            if projects.items.isEmpty {
                Text(projects.emptyTitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            } else {
                ForEach(projects.items) { project in
                    Button {
                        onSelectProject(project.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(project.path)
                                .font(.caption)
                                .foregroundStyle(QuillCodePalette.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(project.isSelected ? QuillCodePalette.selection : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct QuillCodeTranscriptView: View {
    var transcript: TranscriptSurface
    var review: WorkspaceReviewSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if transcript.messages.isEmpty && transcript.toolCards.isEmpty && !review.isVisible {
                    VStack(spacing: 8) {
                        Text(transcript.emptyTitle)
                            .font(.title3.weight(.semibold))
                        Text(transcript.emptySubtitle)
                            .font(.callout)
                            .foregroundStyle(QuillCodePalette.muted)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                    .padding(.top, 180)
                } else {
                    if review.isVisible {
                        QuillCodeReviewPaneView(review: review, onReviewAction: onReviewAction)
                    }
                    ForEach(transcript.messages) { message in
                        QuillCodeMessageBubble(message: message)
                    }
                    ForEach(transcript.toolCards) { card in
                        QuillCodeToolCardView(card: card)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .background(QuillCodePalette.background)
    }
}

private struct QuillCodeReviewPaneView: View {
    var review: WorkspaceReviewSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(QuillCodePalette.blue)
                    .frame(width: 34, height: 34)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(review.title)
                        .font(.headline)
                    Text(review.subtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Text("\(review.totalHunks) hunk\(review.totalHunks == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .foregroundStyle(QuillCodePalette.blue)
                    .clipShape(Capsule())
            }

            VStack(spacing: 0) {
                ForEach(review.files) { file in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: file.isBinary ? "photo" : "doc.plaintext")
                                .foregroundStyle(QuillCodePalette.muted)
                                .frame(width: 20)
                            Text(file.path)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(file.changeLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(QuillCodePalette.muted)
                            HStack(spacing: 6) {
                                ForEach(file.actions) { action in
                                    QuillCodeReviewActionButton(action: action, path: file.path, onReviewAction: onReviewAction)
                                }
                            }
                        }

                        ForEach(file.hunkItems) { hunk in
                            HStack(spacing: 8) {
                                Text(hunk.header)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(1)
                                Text(hunk.changeLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(QuillCodePalette.muted)
                                Spacer()
                                ForEach(hunk.actions) { action in
                                    QuillCodeReviewActionButton(action: action, path: hunk.path, onReviewAction: onReviewAction)
                                }
                            }
                            .padding(.leading, 30)
                        }
                    }
                    .padding(.vertical, 8)
                    if file.id != review.files.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuillCodePalette.blue.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuillCodeReviewActionButton: View {
    var action: WorkspaceReviewActionSurface
    var path: String
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void

    var body: some View {
        Button {
            onReviewAction(action)
        } label: {
            Label(action.kind.title, systemImage: action.kind.systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("\(action.kind.title) \(path)")
        .foregroundStyle(action.kind == .restore || action.kind == .restoreHunk ? QuillCodePalette.yellow : QuillCodePalette.blue)
    }
}

private struct QuillCodeMessageBubble: View {
    var message: MessageSurface

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(message.accessibilityLabel)
            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
    }

    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(LinearGradient(colors: [QuillCodePalette.blue, QuillCodePalette.coral], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(QuillCodePalette.panel)
    }
}

private struct QuillCodeToolCardView: View {
    var card: ToolCardState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.headline)
                    Text(card.subtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Text(card.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.16))
                    .clipShape(Capsule())
            }
            if card.isExpanded || card.status == .failed || card.status == .done {
                if let inputJSON = card.inputJSON {
                    QuillCodeCodeBlock(title: "Input", text: inputJSON)
                }
                if let outputJSON = card.outputJSON {
                    QuillCodeCodeBlock(title: "Output", text: outputJSON)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        switch card.status {
        case .queued, .running:
            return QuillCodePalette.blue
        case .done:
            return QuillCodePalette.green
        case .failed:
            return QuillCodePalette.red
        case .review:
            return QuillCodePalette.yellow
        }
    }

    private var iconName: String {
        switch card.status {
        case .queued, .running:
            return "waveform.path"
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .review:
            return "shield.lefthalf.filled"
        }
    }
}

private struct QuillCodeCodeBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

private struct QuillCodeComposerView: View {
    var composer: ComposerSurface
    @Binding var draft: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(composer.placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(12)
                .background(Color.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(composer.isSending)
                .onSubmit(onSend)
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || composer.isSending)
        }
        .padding(14)
        .background(QuillCodePalette.panel)
    }
}

private struct QuillCodeSettingsView: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text(settings.loginStatusLabel)
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Text(settings.apiKeyStatusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow).opacity(0.16))
                    .foregroundStyle(settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow)
                    .clipShape(Capsule())
            }

            Toggle("Enable developer override", isOn: $draft.developerOverrideEnabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("TrustedRouter API base URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("https://api.quillrouter.com/v1", text: $draft.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Replace API key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                SecureField(settings.hasStoredAPIKey ? "Leave blank to keep saved key" : "Paste TrustedRouter key", text: $draft.replacementAPIKey)
                    .textFieldStyle(.roundedBorder)
                if draft.shouldClearAPIKey {
                    Text("Saved key will be cleared when you save.")
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.yellow)
                }
            }

            HStack {
                Button("Clear API key") {
                    draft.replacementAPIKey = ""
                    draft.shouldClearAPIKey = true
                }
                .disabled(!settings.hasStoredAPIKey)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct QuillCodeSettingsDraft: Equatable {
    var apiBaseURL: String = ""
    var developerOverrideEnabled: Bool = false
    var replacementAPIKey: String = ""
    var shouldClearAPIKey: Bool = false

    init() {}

    init(settings: WorkspaceSettingsSurface) {
        self.apiBaseURL = settings.apiBaseURL
        self.developerOverrideEnabled = settings.developerOverrideEnabled
    }

    var canSave: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var update: WorkspaceSettingsUpdate {
        WorkspaceSettingsUpdate(
            apiBaseURL: apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            developerOverrideEnabled: developerOverrideEnabled,
            replacementAPIKey: replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            shouldClearAPIKey: shouldClearAPIKey
        )
    }
}

private struct QuillCodePill: View {
    var text: String
    var systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(QuillCodePalette.blue.opacity(0.14))
            .foregroundStyle(QuillCodePalette.blue)
            .clipShape(Capsule())
    }
}

private extension AgentMode {
    var title: String {
        switch self {
        case .readOnly:
            return "Read-only"
        case .review:
            return "Review"
        case .auto:
            return "Auto"
        }
    }
}

private enum QuillCodePalette {
    static let background = Color(red: 0.03, green: 0.06, blue: 0.08)
    static let sidebar = Color(red: 0.07, green: 0.10, blue: 0.12)
    static let panel = Color(red: 0.10, green: 0.15, blue: 0.18)
    static let selection = Color.white.opacity(0.08)
    static let text = Color(red: 0.93, green: 0.97, blue: 0.98)
    static let muted = Color(red: 0.62, green: 0.69, blue: 0.72)
    static let blue = Color(red: 0.25, green: 0.72, blue: 0.91)
    static let green = Color(red: 0.32, green: 0.82, blue: 0.45)
    static let red = Color(red: 1.0, green: 0.36, blue: 0.32)
    static let yellow = Color(red: 0.97, green: 0.72, blue: 0.31)
    static let coral = Color(red: 0.82, green: 0.42, blue: 0.37)
}
