import Foundation
import QuillCodeCore

@MainActor
public struct QuillCodeAgentImportActions {
    public var discover: @MainActor () async -> AgentImportPreview
    public var perform: @MainActor (AgentImportSelection) async -> AgentImportOutcome

    public init(
        discover: @escaping @MainActor () async -> AgentImportPreview,
        perform: @escaping @MainActor (AgentImportSelection) async -> AgentImportOutcome
    ) {
        self.discover = discover
        self.perform = perform
    }
}

@MainActor
final class QuillCodeAgentImportDialogCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case review
        case importing
        case result
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var preview: AgentImportPreview?
    @Published private(set) var outcome: AgentImportOutcome?
    @Published var selectedCandidateIDs: Set<String> = []
    @Published var selectedProjectPaths: Set<String> = []

    private var generation = UUID()
    private var task: Task<Void, Never>?

    var isPresented: Bool { phase != .idle }

    var canImport: Bool {
        phase == .review
            && !selectedCandidateIDs.isEmpty
            && !selectedProjectPaths.isEmpty
    }

    func begin(using actions: QuillCodeAgentImportActions) {
        cancelTask()
        let requestID = UUID()
        generation = requestID
        preview = nil
        outcome = nil
        selectedCandidateIDs = []
        selectedProjectPaths = []
        phase = .loading
        task = Task { [weak self] in
            let preview = await actions.discover()
            guard let self, !Task.isCancelled, self.generation == requestID else { return }
            self.preview = preview
            self.selectedCandidateIDs = preview.defaultCandidateIDs
            self.selectedProjectPaths = preview.defaultProjectPaths
            self.phase = .review
            self.task = nil
        }
    }

    func perform(using actions: QuillCodeAgentImportActions) {
        guard canImport, let preview else { return }
        cancelTask()
        let requestID = UUID()
        generation = requestID
        phase = .importing
        let selection = AgentImportSelection(
            source: preview.source,
            candidateIDs: selectedCandidateIDs,
            projectPaths: selectedProjectPaths
        )
        task = Task { [weak self] in
            let outcome = await actions.perform(selection)
            guard let self, !Task.isCancelled, self.generation == requestID else { return }
            self.outcome = outcome
            self.phase = .result
            self.task = nil
        }
    }

    func dismiss() {
        cancelTask()
        generation = UUID()
        preview = nil
        outcome = nil
        selectedCandidateIDs = []
        selectedProjectPaths = []
        phase = .idle
    }

    func toggleCandidate(_ candidate: AgentImportCandidate) {
        guard phase == .review,
              !candidate.isPreviouslyImported,
              candidate.projectPath.map(selectedProjectPaths.contains) ?? true
        else { return }
        if selectedCandidateIDs.remove(candidate.id) == nil {
            selectedCandidateIDs.insert(candidate.id)
        }
    }

    func toggleProject(_ project: AgentImportProject) {
        guard phase == .review, let preview else { return }
        if selectedProjectPaths.remove(project.path) != nil {
            selectedCandidateIDs.subtract(
                preview.candidates.lazy
                    .filter { $0.projectPath == project.path }
                    .map(\.id)
            )
        } else {
            selectedProjectPaths.insert(project.path)
            selectedCandidateIDs.formUnion(
                preview.candidates.lazy
                    .filter { $0.projectPath == project.path && !$0.isPreviouslyImported }
                    .map(\.id)
            )
        }
    }

    func selectAllCandidates() {
        guard phase == .review, let preview else { return }
        selectedCandidateIDs = Set(preview.selectableCandidates.compactMap { candidate in
            candidate.projectPath.map(selectedProjectPaths.contains) ?? true ? candidate.id : nil
        })
    }

    func clearCandidateSelection() {
        guard phase == .review else { return }
        selectedCandidateIDs = []
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
    }
}
