import SwiftUI
import QuillCodeCore

@MainActor
final class QuillCodeWorktreeDialogCoordinator: ObservableObject {
    @Published var sheet: QuillCodeWorktreeSheet?
    @Published var newTaskDraft = QuillCodeNewWorktreeTaskDraft()
    @Published var createDraft = QuillCodeWorktreeCreateDraft()
    @Published var createBranchDraft = QuillCodeWorktreeCreateBranchDraft()
    @Published var openDraft = QuillCodeWorktreeOpenDraft()
    @Published var removeDraft = QuillCodeWorktreeRemoveDraft()
    @Published var pruneDraft = QuillCodeWorktreePruneDraft()

    private let tasks = QuillCodeWorktreeDialogTasks()

    func presentNewTask(environments: WorkspaceWorktreeEnvironmentSurface) {
        tasks.cancelPending()
        newTaskDraft = QuillCodeNewWorktreeTaskDraft(environments: environments)
        sheet = .newTask
    }

    func presentCreate() {
        tasks.cancelPending()
        createDraft = QuillCodeWorktreeCreateDraft()
        sheet = .create
    }

    func presentCreateBranch() {
        tasks.cancelPending()
        createBranchDraft = QuillCodeWorktreeCreateBranchDraft()
        sheet = .createBranch
    }

    func presentOpen(loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad) {
        presentChoice(.open, loadChoices: loadChoices)
    }

    func presentRemove(loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad) {
        presentChoice(.remove, loadChoices: loadChoices)
    }

    func presentPrune(loadPreview: @escaping () async -> WorkspaceWorktreePrunePreview) {
        tasks.cancelChoiceLoad()
        pruneDraft = QuillCodeWorktreePruneDraft(preview: .loading)
        sheet = .prune
        loadPrunePreview(loadPreview: loadPreview)
    }

    func retryChoices(
        for sheet: QuillCodeWorktreeSheet,
        loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad
    ) {
        guard self.sheet == sheet else { return }
        guard let choice = QuillCodeWorktreeChoiceSheet(sheet) else { return }
        choice.updateChoiceLoad(.loading, on: self)
        startChoiceLoad(for: choice, loadChoices: loadChoices)
    }

    func retryPrunePreview(loadPreview: @escaping () async -> WorkspaceWorktreePrunePreview) {
        guard sheet == .prune else { return }
        pruneDraft.preview = .loading
        loadPrunePreview(loadPreview: loadPreview)
    }

    private func presentChoice(
        _ choice: QuillCodeWorktreeChoiceSheet,
        loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad
    ) {
        tasks.cancelPrunePreview()
        choice.resetDraft(on: self)
        sheet = choice.sheet
        startChoiceLoad(for: choice, loadChoices: loadChoices)
    }

    private func startChoiceLoad(
        for choice: QuillCodeWorktreeChoiceSheet,
        loadChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad
    ) {
        tasks.runChoiceLoad { [weak self] in
            let load = await loadChoices()
            guard !Task.isCancelled else { return }
            self?.applyChoiceLoad(load, to: choice)
        }
    }

    private func applyChoiceLoad(_ load: WorkspaceWorktreeChoiceLoad, to choice: QuillCodeWorktreeChoiceSheet) {
        guard sheet == choice.sheet else { return }
        choice.updateChoiceLoad(.loaded(load), on: self)
    }

    private func loadPrunePreview(loadPreview: @escaping () async -> WorkspaceWorktreePrunePreview) {
        tasks.runPrunePreview { [weak self] in
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

@MainActor
private enum QuillCodeWorktreeChoiceSheet {
    case open
    case remove

    init?(_ sheet: QuillCodeWorktreeSheet) {
        switch sheet {
        case .open:
            self = .open
        case .remove:
            self = .remove
        case .newTask, .create, .createBranch, .prune:
            return nil
        }
    }

    var sheet: QuillCodeWorktreeSheet {
        switch self {
        case .open:
            return .open
        case .remove:
            return .remove
        }
    }

    func resetDraft(on coordinator: QuillCodeWorktreeDialogCoordinator) {
        switch self {
        case .open:
            coordinator.openDraft = QuillCodeWorktreeOpenDraft(choiceLoad: .loading)
        case .remove:
            coordinator.removeDraft = QuillCodeWorktreeRemoveDraft(choiceLoad: .loading)
        }
    }

    func updateChoiceLoad(
        _ state: QuillCodeWorktreeChoiceLoadState,
        on coordinator: QuillCodeWorktreeDialogCoordinator
    ) {
        switch self {
        case .open:
            coordinator.openDraft.choiceLoad = state
        case .remove:
            coordinator.removeDraft.choiceLoad = state
        }
    }
}
