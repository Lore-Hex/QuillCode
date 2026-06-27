import SwiftUI
import QuillCodeCore

struct QuillCodeWorktreeChoiceSection: View {
    var state: QuillCodeWorktreeChoiceLoadState
    var selectedPath: String
    var iconName: String
    var iconColor: Color
    var emptyMessage: String
    var onSelect: (WorkspaceWorktreeChoice) -> Void
    var onRetry: () -> Void

    var body: some View {
        if shouldShowSection {
            content
        }
    }

    private var shouldShowSection: Bool {
        state.isLoading || state.hasLoaded || state.errorMessage != nil || !state.choices.isEmpty
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Known Worktrees")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .textCase(.uppercase)
            VStack(spacing: 6) {
                if state.isLoading {
                    QuillCodeWorktreeChoiceStatusRow(
                        systemImage: "clock.arrow.circlepath",
                        message: "Loading registered worktrees...",
                        color: QuillCodePalette.blue,
                        showsSpinner: true
                    )
                } else if let errorMessage = state.errorMessage {
                    QuillCodeWorktreeChoiceStatusRow(
                        systemImage: "exclamationmark.triangle",
                        message: "\(errorMessage) You can still paste a worktree path.",
                        color: QuillCodePalette.yellow,
                        actionTitle: "Retry",
                        action: onRetry
                    )
                } else if state.hasLoaded && state.choices.isEmpty {
                    QuillCodeWorktreeChoiceStatusRow(
                        systemImage: "rectangle.stack.badge.questionmark",
                        message: "\(emptyMessage) You can still paste a path.",
                        color: QuillCodePalette.muted
                    )
                }
                ForEach(state.choices) { choice in
                    QuillCodeWorktreeChoiceRow(
                        choice: choice,
                        selectedPath: selectedPath,
                        iconName: iconName,
                        iconColor: iconColor,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

struct QuillCodeWorktreePruneRecordRow: View {
    var record: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(QuillCodePalette.yellow)
                .accessibilityHidden(true)
            Text(record)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(QuillCodePalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(QuillCodePalette.yellow.opacity(0.25))
        )
    }
}

struct QuillCodeWorktreeChoiceStatusRow: View {
    var systemImage: String
    var message: String
    var color: Color
    var showsSpinner = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading")
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
                    .quillCodeHitTarget(minWidth: 56)
                    .accessibilityIdentifier("quillcode-worktree-choice-retry")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(QuillCodePalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08))
        )
    }
}

struct QuillCodeWorktreeChoiceRow: View {
    var choice: WorkspaceWorktreeChoice
    var selectedPath: String
    var iconName: String
    var iconColor: Color
    var onSelect: (WorkspaceWorktreeChoice) -> Void

    var body: some View {
        Button {
            onSelect(choice)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(choice.detail)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                    Text(choice.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(QuillCodePalette.muted.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if choice.path == selectedPath {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(QuillCodePalette.green)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
            .padding(10)
            .frame(minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(choice.path == selectedPath
                        ? QuillCodePalette.blue.opacity(0.14)
                        : QuillCodePalette.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(choice.path == selectedPath
                        ? QuillCodePalette.blue.opacity(0.45)
                        : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(QuillCodePressableButtonStyle())
    }
}

struct QuillCodeWorktreeDialogFrame<Content: View, Footer: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var iconColor: Color
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }

            content
            footer
        }
        .padding(24)
        .frame(width: 520)
        .background(QuillCodePalette.background)
    }
}
