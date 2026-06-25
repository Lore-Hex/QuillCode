import SwiftUI
import QuillCodeCore

@MainActor
final class QuillCodeWorktreeDialogCoordinator: ObservableObject {
    @Published var sheet: QuillCodeWorktreeSheet?
    @Published var createDraft = QuillCodeWorktreeCreateDraft()
    @Published var openDraft = QuillCodeWorktreeOpenDraft()
    @Published var removeDraft = QuillCodeWorktreeRemoveDraft()
    @Published var pruneDraft = QuillCodeWorktreePruneDraft()

    private var choiceLoadTask: Task<Void, Never>?
    private var prunePreviewTask: Task<Void, Never>?

    deinit {
        choiceLoadTask?.cancel()
        prunePreviewTask?.cancel()
    }

    func presentCreate() {
        choiceLoadTask?.cancel()
        prunePreviewTask?.cancel()
        createDraft = QuillCodeWorktreeCreateDraft()
        sheet = .create
    }

    func presentOpen(loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad) {
        prunePreviewTask?.cancel()
        openDraft = QuillCodeWorktreeOpenDraft(choiceLoad: .loading)
        sheet = .open
        startChoiceLoad(for: .open, loadChoices: loadChoices)
    }

    func presentRemove(loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad) {
        prunePreviewTask?.cancel()
        removeDraft = QuillCodeWorktreeRemoveDraft(choiceLoad: .loading)
        sheet = .remove
        startChoiceLoad(for: .remove, loadChoices: loadChoices)
    }

    func presentPrune(loadPreview: @escaping () async -> WorkspaceWorktreePrunePreview) {
        choiceLoadTask?.cancel()
        pruneDraft = QuillCodeWorktreePruneDraft(preview: .loading)
        sheet = .prune
        loadPrunePreview(loadPreview: loadPreview)
    }

    func retryChoices(for sheet: QuillCodeWorktreeSheet, loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad) {
        guard self.sheet == sheet else { return }
        switch sheet {
        case .open:
            openDraft.choiceLoad = .loading
            startChoiceLoad(for: .open, loadChoices: loadChoices)
        case .remove:
            removeDraft.choiceLoad = .loading
            startChoiceLoad(for: .remove, loadChoices: loadChoices)
        case .create, .prune:
            break
        }
    }

    func retryPrunePreview(loadPreview: @escaping () async -> WorkspaceWorktreePrunePreview) {
        guard sheet == .prune else { return }
        pruneDraft.preview = .loading
        loadPrunePreview(loadPreview: loadPreview)
    }

    private func startChoiceLoad(
        for sheet: QuillCodeWorktreeSheet,
        loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad
    ) {
        choiceLoadTask?.cancel()
        choiceLoadTask = Task { [weak self] in
            let load = await loadChoices()
            guard !Task.isCancelled else { return }
            self?.applyChoiceLoad(load, to: sheet)
        }
    }

    private func applyChoiceLoad(_ load: WorkspaceWorktreeChoiceLoad, to sheet: QuillCodeWorktreeSheet) {
        guard self.sheet == sheet else { return }
        switch sheet {
        case .open:
            openDraft.choiceLoad = .loaded(load)
        case .remove:
            removeDraft.choiceLoad = .loaded(load)
        case .create, .prune:
            break
        }
    }

    private func loadPrunePreview(loadPreview: @escaping () async -> WorkspaceWorktreePrunePreview) {
        prunePreviewTask?.cancel()
        prunePreviewTask = Task { [weak self] in
            let preview = await loadPreview()
            guard !Task.isCancelled else { return }
            self?.applyPrunePreview(preview)
        }
    }

    private func applyPrunePreview(_ preview: WorkspaceWorktreePrunePreview) {
        guard sheet == .prune else { return }
        pruneDraft.preview = .loaded(preview)
    }
}
