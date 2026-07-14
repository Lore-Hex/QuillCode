import SwiftUI
import QuillCodeCore

struct QuillCodeAgentImportView: View {
    @ObservedObject var coordinator: QuillCodeAgentImportDialogCoordinator
    var onClose: () -> Void
    var onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            Divider().opacity(0.5)
            content
            Divider().opacity(0.5)
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 640)
        .frame(maxHeight: 720)
        .background(QuillCodePalette.background)
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(QuillCodePalette.blue)
                .frame(width: 38, height: 38)
                .background(QuillCodePalette.blue.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .quillCodeIconButtonTarget(size: 36, radius: 9)
                    .background(QuillCodePalette.selection.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close import")
            .accessibilityLabel("Close import")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .idle:
            EmptyView()
        case .loading:
            progressState(title: "Looking for supported setup", detail: "Scanning local agent data safely…")
        case .importing:
            progressState(title: "Importing selected items", detail: "QuillCode is adding data without replacing existing files…")
        case .review:
            reviewContent
        case .result:
            resultContent
        }
    }

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let preview = coordinator.preview {
                    sourceSummary(preview)
                    projectSection(preview)
                    candidateSection(preview)
                    diagnostics(preview.diagnostics)
                }
            }
            .padding(20)
        }
    }

    private func sourceSummary(_ preview: AgentImportPreview) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preview.source.displayName)
                    .font(.headline)
                Text("\(preview.selectableCandidates.count) available · \(preview.alreadyImportedCount) previously imported")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .monospacedDigit()
            }
            Spacer()
            selectionButtons
        }
    }

    private var selectionButtons: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Button("None", action: coordinator.clearCandidateSelection)
                .buttonStyle(QuillCodeActionButtonStyle())
                .quillCodeFormActionTarget(minWidth: 64)
            Button("All", action: coordinator.selectAllCandidates)
                .buttonStyle(QuillCodeActionButtonStyle())
                .quillCodeFormActionTarget(minWidth: 56)
        }
    }

    @ViewBuilder
    private func projectSection(_ preview: AgentImportPreview) -> some View {
        if !preview.projects.isEmpty {
            importSection(title: "Projects", detail: "Choose where project-scoped setup and chats should be added.") {
                ForEach(preview.projects) { project in
                    projectRow(project)
                    if project.id != preview.projects.last?.id { Divider().opacity(0.35) }
                }
            }
        }
    }

    private func projectRow(_ project: AgentImportProject) -> some View {
        let isSelected = coordinator.selectedProjectPaths.contains(project.path)
        return Button { coordinator.toggleProject(project) } label: {
            HStack(spacing: 11) {
                selectionIcon(isSelected: isSelected, isComplete: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(QuillCodePalette.text)
                    Text(project.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if project.isAlreadyRegistered {
                    statusLabel("In sidebar", tint: QuillCodePalette.green)
                }
            }
            .frame(minHeight: 42)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget()
        .accessibilityLabel("\(isSelected ? "Selected" : "Not selected") project \(project.name)")
    }

    private func candidateSection(_ preview: AgentImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(AgentImportItemKind.allCases, id: \.self) { kind in
                let candidates = preview.candidates.filter { $0.kind == kind && kind != .projects }
                if !candidates.isEmpty {
                    importSection(title: kind.displayName, detail: nil) {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                            if candidate.id != candidates.last?.id { Divider().opacity(0.35) }
                        }
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: AgentImportCandidate) -> some View {
        let projectEnabled = candidate.projectPath.map(coordinator.selectedProjectPaths.contains) ?? true
        let isEnabled = !candidate.isPreviouslyImported && projectEnabled
        let isSelected = coordinator.selectedCandidateIDs.contains(candidate.id) && isEnabled
        return Button { coordinator.toggleCandidate(candidate) } label: {
            HStack(spacing: 11) {
                selectionIcon(isSelected: isSelected, isComplete: candidate.isPreviouslyImported)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isEnabled ? QuillCodePalette.text : QuillCodePalette.muted)
                    Text(candidate.detail)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                if candidate.isPreviouslyImported {
                    statusLabel("Imported", tint: QuillCodePalette.green)
                } else if candidate.requiresSetup {
                    statusLabel("Review later", tint: QuillCodePalette.yellow)
                }
            }
            .frame(minHeight: 44)
            .opacity(projectEnabled ? 1 : 0.56)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget()
        .disabled(!isEnabled)
        .accessibilityLabel(candidateAccessibilityLabel(candidate, isSelected: isSelected, projectEnabled: projectEnabled))
    }

    private var resultContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let outcome = coordinator.outcome {
                    HStack(spacing: 12) {
                        Image(systemName: outcome.importedCount > 0 ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(outcome.importedCount > 0 ? QuillCodePalette.green : QuillCodePalette.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(outcome.importedCount > 0 ? "Import complete" : "Nothing new to import")
                                .font(.headline)
                            Text("\(outcome.importedCount) items added · \(outcome.skippedCount) skipped")
                                .font(.caption)
                                .foregroundStyle(QuillCodePalette.muted)
                                .monospacedDigit()
                        }
                    }
                    if !outcome.imported.isEmpty {
                        importSection(title: "Added", detail: nil) {
                            ForEach(outcome.imported) { count in
                                HStack {
                                    Text(count.kind.displayName)
                                    Spacer()
                                    Text("\(count.count)")
                                        .monospacedDigit()
                                        .foregroundStyle(QuillCodePalette.muted)
                                }
                                .font(.callout)
                                .frame(minHeight: 34)
                            }
                        }
                    }
                    if !outcome.setupFollowUps.isEmpty {
                        messageSection(title: "Needs your review", messages: outcome.setupFollowUps, tint: QuillCodePalette.yellow)
                    }
                    diagnostics(outcome.diagnostics)
                }
            }
            .padding(20)
        }
    }

    private func progressState(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private func diagnostics(_ messages: [String]) -> some View {
        if !messages.isEmpty {
            messageSection(title: "Details", messages: messages, tint: QuillCodePalette.muted)
        }
    }

    private func messageSection(title: String, messages: [String], tint: Color) -> some View {
        importSection(title: title, detail: nil) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(tint).frame(width: 5, height: 5).padding(.top, 6)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 28)
            }
        }
    }

    private func importSection<Content: View>(
        title: String,
        detail: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(QuillCodePalette.panel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func selectionIcon(isSelected: Bool, isComplete: Bool) -> some View {
        Image(systemName: isComplete ? "checkmark.circle.fill" : (isSelected ? "checkmark.square.fill" : "square"))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isComplete ? QuillCodePalette.green : (isSelected ? QuillCodePalette.blue : QuillCodePalette.muted))
            .frame(width: 24, height: 24)
    }

    private func statusLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
            .fixedSize()
    }

    private func candidateAccessibilityLabel(
        _ candidate: AgentImportCandidate,
        isSelected: Bool,
        projectEnabled: Bool
    ) -> String {
        if candidate.isPreviouslyImported { return "Imported \(candidate.kind.displayName): \(candidate.title)" }
        if !projectEnabled { return "Unavailable until its project is selected: \(candidate.title)" }
        return "\(isSelected ? "Selected" : "Not selected") \(candidate.kind.displayName): \(candidate.title)"
    }

    private var footer: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Text(footerStatus)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            Spacer()
            if coordinator.phase == .result {
                Button("Done", action: onClose)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    .quillCodeFormActionTarget()
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", action: onClose)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button("Import", action: onImport)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    .quillCodeFormActionTarget()
                    .disabled(!coordinator.canImport)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var headerTitle: String {
        switch coordinator.phase {
        case .loading: "Import from another agent"
        case .review: "Review import"
        case .importing: "Importing"
        case .result: "Import summary"
        case .idle: "Import"
        }
    }

    private var headerDetail: String {
        coordinator.preview?.source.displayName ?? "Add supported setup without changing existing files"
    }

    private var footerStatus: String {
        switch coordinator.phase {
        case .review: "\(coordinator.selectedCandidateIDs.count) items selected"
        case .importing: "This may take a moment for large chat histories."
        case .result: "Imported extensions remain disabled until reviewed."
        case .loading: "Scanning local files only."
        case .idle: ""
        }
    }
}
