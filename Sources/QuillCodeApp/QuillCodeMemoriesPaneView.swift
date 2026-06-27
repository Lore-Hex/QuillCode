import SwiftUI

struct QuillCodeMemoriesPaneView: View {
    var memories: WorkspaceMemoriesSurface
    var onCommand: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if memories.items.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: memories.emptyTitle,
                    subtitle: memories.emptySubtitle
                )
            } else {
                memoryCards
            }
        }
        .padding(14)
        .frame(height: memories.items.isEmpty ? 170 : 220)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
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
            HStack(spacing: 6) {
                QuillCodePaneCountPill(label: "Global", count: memories.globalCount)
                QuillCodePaneCountPill(label: "Project", count: memories.projectCount)
            }
            Button {
                onCommand("memory-add")
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .quillCodeTextButtonTarget()
        }
    }

    private var memoryCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(memories.items) { item in
                    memoryCard(item)
                }
            }
        }
    }

    private func memoryCard(_ item: MemoryNoteSurface) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
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
                    HStack(spacing: 8) {
                        if let editCommandID = item.editCommandID {
                            Button {
                                onCommand(editCommandID)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .labelStyle(.iconOnly)
                            }
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
                            .quillCodeIconButtonTarget()
                            .help("Forget this memory")
                        }
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
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
