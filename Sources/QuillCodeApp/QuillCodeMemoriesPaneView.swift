import SwiftUI

struct QuillCodeMemoriesPaneView: View {
    var memories: WorkspaceMemoriesSurface
    var onCommand: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if memories.items.isEmpty && memories.redactionReviews.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: memories.emptyTitle,
                    subtitle: memories.emptySubtitle
                )
            } else {
                if !memories.redactionReviews.isEmpty {
                    memoryRedactionReviews
                }
                if !memories.conflicts.isEmpty {
                    memoryConflicts
                }
                if !memories.items.isEmpty {
                    memoryCards
                }
            }
        }
        .padding(14)
        .frame(height: paneHeight)
        .background(QuillCodePalette.panel)
    }

    private var paneHeight: CGFloat {
        if memories.items.isEmpty && memories.redactionReviews.isEmpty { return 170 }
        let reviewRows = [
            !memories.redactionReviews.isEmpty,
            !memories.conflicts.isEmpty
        ].filter { $0 }.count
        return 220 + CGFloat(reviewRows) * 92
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(memories.title)
                    .font(.headline)
                Text(memories.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                QuillCodePaneCountPill(label: "Global", count: memories.globalCount)
                QuillCodePaneCountPill(label: "Project", count: memories.projectCount)
            }
            Button {
                onCommand("memory-add")
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(QuillCodeActionButtonStyle(.primary))
            .quillCodeFormActionTarget()
        }
    }

    private var memoryCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                ForEach(memories.items) { item in
                    memoryCard(item)
                }
            }
        }
    }

    private var memoryConflicts: some View {
        ScrollView(.horizontal) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                ForEach(memories.conflicts) { conflict in
                    memoryConflictCard(conflict)
                }
            }
        }
    }

    private var memoryRedactionReviews: some View {
        ScrollView(.horizontal) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                ForEach(memories.redactionReviews) { review in
                    memoryRedactionReviewCard(review)
                }
            }
        }
    }

    private func memoryRedactionReviewCard(_ review: MemoryRedactionReviewSurface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(QuillCodePalette.green)
                Text(review.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer()
                Button {
                    onCommand(review.addCommandID)
                } label: {
                    Label("Add safe memory", systemImage: "plus")
                }
                .buttonStyle(QuillCodeActionButtonStyle(.secondary))
                .quillCodeFormActionTarget()
                .help("Start a new memory without sensitive content")
            }
            Text(review.summary)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(2)
            Text(review.redactedInput)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.green)
                .lineLimit(2)
            Text(review.guidance)
                .font(.caption2)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(2)
        }
        .padding(12)
        .frame(width: 420, alignment: .topLeading)
        .background(QuillCodePalette.green.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(QuillCodePalette.green.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func memoryConflictCard(_ conflict: MemoryConflictSurface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(QuillCodePalette.yellow)
                Text(conflict.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer()
            }
            Text(conflict.summary)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(2)
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                memoryConflictSide(conflict.global)
                memoryConflictSide(conflict.project)
            }
        }
        .padding(12)
        .frame(width: 420, alignment: .topLeading)
        .background(QuillCodePalette.yellow.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(QuillCodePalette.yellow.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func memoryConflictSide(_ side: MemoryConflictSideSurface) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(side.scopeLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(QuillCodePalette.yellow)
            Text(side.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(side.relativePath)
                .font(.caption2.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            if let commandID = side.editCommandID {
                Button {
                    onCommand(commandID)
                } label: {
                    Label("Edit \(side.scopeLabel.lowercased())", systemImage: "pencil")
                }
                .buttonStyle(QuillCodeActionButtonStyle(.secondary))
                .quillCodeFormActionTarget()
                .help("Edit the \(side.scopeLabel.lowercased()) memory")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func memoryCard(_ item: MemoryNoteSurface) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Text(item.scopeLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .clipShape(Capsule())
                Text(item.byteCountLabel)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
                if item.canEdit || item.canDelete {
                    HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                        if let editCommandID = item.editCommandID {
                            Button {
                                onCommand(editCommandID)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(QuillCodePressableButtonStyle())
                            .quillCodeIconButtonTarget()
                            .help("Edit this memory")
                        }
                        if let deleteCommandID = item.deleteCommandID {
                            Button {
                                onCommand(deleteCommandID)
                            } label: {
                                Label("Forget", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(QuillCodePressableButtonStyle())
                            .quillCodeIconButtonTarget()
                            .help("Forget this memory")
                        }
                    }
                    .foregroundStyle(QuillCodePalette.muted)
                }
            }
            Text(item.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(item.preview)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(3)
            Text(item.relativePath)
                .font(.caption2.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 300, alignment: .topLeading)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
