import SwiftUI
import QuillCodeCore

struct QuillCodeActivityPaneView: View {
    var activity: WorkspaceActivitySurface

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            taskSummary

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    QuillCodeActivitySectionView(
                        title: "Recent",
                        emptyTitle: "No task events yet",
                        items: activity.recentSteps
                    )
                    QuillCodeActivitySectionView(
                        title: "Tools",
                        emptyTitle: "No tools used yet",
                        items: activity.tools
                    )
                    QuillCodeActivitySectionView(
                        title: "Sources",
                        emptyTitle: "No context sources attached",
                        items: activity.sources
                    )
                    QuillCodeActivityArtifactsView(artifacts: activity.artifacts)
                    latestAnswer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
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
            Text(activity.statusLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(QuillCodePalette.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(QuillCodePalette.blue.opacity(0.14))
                .clipShape(Capsule())
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

    @ViewBuilder
    private var latestAnswer: some View {
        if let finalAnswer = activity.finalAnswer {
            VStack(alignment: .leading, spacing: 6) {
                Text("Latest Answer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                Text(finalAnswer)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(8)
            }
        }
    }
}

private struct QuillCodeActivitySectionView: View {
    var title: String
    var emptyTitle: String
    var items: [ActivityItemSurface]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            if items.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            } else {
                ForEach(items) { item in
                    QuillCodeActivityItemView(item: item)
                }
            }
        }
    }
}

private struct QuillCodeActivityItemView: View {
    var item: ActivityItemSurface

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color(for: item.statusLabel))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
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
    }

    private func color(for status: String) -> Color {
        switch status.lowercased() {
        case "done", "checked", "logged", "rules", "global", "project":
            return QuillCodePalette.green
        case "failed":
            return QuillCodePalette.red
        case "review", "queued":
            return QuillCodePalette.yellow
        default:
            return QuillCodePalette.blue
        }
    }
}

private struct QuillCodeActivityArtifactsView: View {
    var artifacts: [ToolArtifactState]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Artifacts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            if artifacts.isEmpty {
                Text("No artifacts produced yet")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            } else {
                ForEach(artifacts) { artifact in
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
        }
    }
}
