import SwiftUI
import QuillCodeCore

struct QuillCodeActivityPaneView: View {
    var activity: WorkspaceActivitySurface
    var onCommand: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            taskSummary

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(activity.sections) { section in
                        QuillCodeActivitySectionView(section: section, onCommand: onCommand)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.headline)
                Text(activity.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            Spacer()
            if let integrity = activity.integrityBadge {
                Text(integrity.badgeLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(integrityColor(integrity))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(integrityColor(integrity).opacity(0.14))
                    .clipShape(Capsule())
                    .help(activity.integrityDetail)
                    .accessibilityLabel("Run integrity: \(integrity.badgeLabel). \(activity.integrityDetail)")
            }
            Text(activity.statusLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(QuillCodePalette.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(QuillCodePalette.blue.opacity(0.14))
                .clipShape(Capsule())
        }
    }

    private func integrityColor(_ verdict: RunIntegrityVerdict) -> Color {
        switch verdict {
        case .verified: return QuillCodePalette.green
        case .unverified: return QuillCodePalette.yellow
        case .red: return QuillCodePalette.red
        }
    }

    private var taskSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.taskTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(3)
            Text(activity.taskSubtitle)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuillCodePalette.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}

private struct QuillCodeActivitySectionView: View {
    var section: ActivitySectionSurface
    var onCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { onCommand(section.toggleCommandID) }) {
                HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                    Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .frame(width: 10)
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    Spacer()
                    Text(section.countLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(QuillCodePalette.blue)
                }
            }
            .quillCodeFullRowButtonTarget()
            .buttonStyle(QuillCodePressableButtonStyle())
            .accessibilityLabel("\(section.isCollapsed ? "Expand" : "Collapse") \(section.title)")

            if !section.isCollapsed {
                sectionContent
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if let bodyText = section.bodyText {
            Text(bodyText)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(8)
        } else if !section.artifacts.isEmpty {
            ForEach(section.artifacts) { artifact in
                QuillCodeActivityArtifactView(artifact: artifact)
            }
        } else if !section.items.isEmpty {
            ForEach(section.items) { item in
                QuillCodeActivityItemView(item: item, onCommand: onCommand)
            }
        } else {
            Text(section.emptyTitle)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
    }

}

private struct QuillCodeActivityItemView: View {
    var item: ActivityItemSurface
    var onCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(color(for: item.statusLabel))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if !item.statusLabel.isEmpty {
                            Text(item.statusLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(color(for: item.statusLabel))
                        }
                    }
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundStyle(QuillCodePalette.muted)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !item.actions.isEmpty {
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    ForEach(item.actions) { action in
                        Button(action.title) {
                            onCommand(action.commandID)
                        }
                        .buttonStyle(QuillCodePressableButtonStyle())
                        .quillCodeCapsuleButtonTarget(minWidth: 58)
                        .accessibilityLabel("\(action.title) \(item.title)")
                    }
                }
                .padding(.leading, 15)
            }
            if !item.transcript.isEmpty {
                QuillCodeSubagentTranscriptView(entries: item.transcript)
                    .padding(.leading, 15)
            }
        }
    }

    private func color(for status: String) -> Color {
        switch status.lowercased() {
        case "done", "checked", "logged", "rules", "global", "project":
            return QuillCodePalette.green
        case "failed", "conflict":
            return QuillCodePalette.red
        case "review", "queued", "needs approval":
            return QuillCodePalette.yellow
        case "pending", "optional":
            return QuillCodePalette.muted
        default:
            return QuillCodePalette.blue
        }
    }
}

private struct QuillCodeSubagentTranscriptView: View {
    var entries: [SubagentTranscriptEntry]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    transcriptRow(entry)
                    if entry.id != entries.last?.id {
                        Divider()
                            .opacity(0.45)
                    }
                }
            }
            .padding(.horizontal, 10)
            .background(QuillCodePalette.background.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } label: {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: "text.alignleft")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                Text("Transcript")
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text("\(entries.count) step\(entries.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .monospacedDigit()
            }
            .quillCodeFullRowButtonTarget()
        }
        .tint(QuillCodePalette.muted)
        .accessibilityLabel("Subagent transcript, \(entries.count) steps")
    }

    private func transcriptRow(_ entry: SubagentTranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName(for: entry.kind))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color(for: entry.kind))
                .frame(width: 14, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    Text(entry.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    if !entry.statusLabel.isEmpty {
                        Text(entry.statusLabel)
                            .font(.caption2)
                            .foregroundStyle(QuillCodePalette.muted)
                    }
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private func iconName(for kind: SubagentTranscriptEntryKind) -> String {
        switch kind {
        case .assistant: return "text.bubble"
        case .tool: return "wrench.and.screwdriver"
        case .approval: return "checkmark.shield"
        }
    }

    private func color(for kind: SubagentTranscriptEntryKind) -> Color {
        switch kind {
        case .assistant: return QuillCodePalette.green
        case .tool: return QuillCodePalette.blue
        case .approval: return QuillCodePalette.yellow
        }
    }
}

private struct QuillCodeActivityArtifactView: View {
    var artifact: ToolArtifactState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(artifact.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(artifact.detail)
                .font(.caption2.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuillCodePalette.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
