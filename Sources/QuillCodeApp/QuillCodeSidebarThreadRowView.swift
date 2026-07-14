import SwiftUI
import QuillCodeCore

struct QuillCodeSidebarThreadRowView: View {
    var item: SidebarItemSurface
    var isSelectionMode: Bool
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.sidebarControlSpacing) {
            selectionToggle
            threadButton
            actionsMenu
        }
        .padding(.vertical, 0)
    }

    @ViewBuilder
    private var selectionToggle: some View {
        if isSelectionMode {
            Button {
                toggleSelection()
            } label: {
                Image(systemName: item.isBulkSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.isBulkSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .quillCodeSidebarIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
            .accessibilityLabel(item.isBulkSelected ? "Deselect \(item.title)" : "Select \(item.title)")
        }
    }

    private var threadButton: some View {
        Button {
            if isSelectionMode {
                toggleSelection()
            } else {
                onSelectThread(item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(QuillCodePalette.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let runStatusLabel = item.runStatusLabel {
                        ProgressView()
                            .controlSize(.mini)
                            .help(runStatusLabel)
                            .accessibilityLabel("\(item.title) is \(runStatusLabel.lowercased())")
                    }
                }
                Text(item.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                if item.worktree != nil || item.pullRequest != nil {
                    HStack(spacing: 6) {
                        worktreeMetadata
                        pullRequestMetadata
                        Spacer(minLength: 0)
                    }
                }
            }
            .quillCodeSidebarRowChrome(background: item.isSelected ? QuillCodePalette.selection : Color.clear)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
        .accessibilityValue(item.runStatusLabel ?? "Idle")
    }

    @ViewBuilder
    private var worktreeMetadata: some View {
        if let worktree = item.worktree {
            if worktree.location == .local {
                metadataText(
                    worktree.isResolvable ? "Local" : "Local · worktree missing",
                    color: worktree.isResolvable ? QuillCodePalette.muted : QuillCodePalette.red,
                    monospaced: true
                )
            } else if worktree.isResolvable {
                metadataText("⑂ \(worktree.branchLeaf)", color: QuillCodePalette.blue, monospaced: true)
            } else if worktree.hasRestorableSnapshot {
                metadataText("↻ Worktree saved", color: QuillCodePalette.blue)
            } else {
                metadataText("⚠ Worktree missing", color: QuillCodePalette.red)
            }
        }
    }

    @ViewBuilder
    private var pullRequestMetadata: some View {
        if let pullRequest = item.pullRequest {
            metadataText(pullRequest.compactLabel, color: pullRequestColor(pullRequest.status))
                .help(pullRequest.title)
                .accessibilityLabel("Pull request \(pullRequest.number), \(pullRequest.status.label)")
        }
    }

    private func metadataText(_ text: String, color: Color, monospaced: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func pullRequestColor(_ status: PullRequestLifecycleStatus) -> Color {
        switch status {
        case .draft:
            return QuillCodePalette.muted
        case .open, .queued:
            return QuillCodePalette.blue
        case .merged:
            return QuillCodePalette.green
        case .closed:
            return QuillCodePalette.red
        }
    }

    private var actionsMenu: some View {
        Menu {
            ForEach(item.actions) { action in
                Button(role: action.kind == .delete ? .destructive : nil) {
                    onThreadAction(action)
                } label: {
                    Text(action.kind.title)
                }
                .quillCodePlatformMenuItemTarget(reason: "AppKit owns thread action menu row geometry; the ellipsis trigger carries the custom hit-target contract.")
            }
        } label: {
            Image(systemName: "ellipsis")
                .quillCodeSidebarIconButtonTarget()
                .foregroundStyle(QuillCodePalette.muted)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
        .help("Thread actions")
        .accessibilityLabel("Thread actions for \(item.title)")
    }

    private func toggleSelection() {
        onCommand(QuillCodeSidebarCommandAdapter.toggleSelectionCommand(for: item))
    }
}
