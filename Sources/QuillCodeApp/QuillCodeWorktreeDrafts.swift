import Foundation
import QuillCodeCore

enum QuillCodeWorktreeSheet: String, Identifiable {
    case create
    case createBranch
    case open
    case remove
    case prune

    var id: String { rawValue }
}

struct QuillCodeWorktreeCreateBranchDraft: Equatable {
    var branch = ""

    var canCreate: Bool {
        !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeCreateBranchRequest {
        WorkspaceWorktreeCreateBranchRequest(
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct QuillCodeWorktreeCreateDraft: Equatable {
    var path = ""
    var branch = ""
    var base = ""

    var canCreate: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeCreateRequest {
        WorkspaceWorktreeCreateRequest(
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            base: base.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct QuillCodeWorktreeChoiceLoadState: Equatable {
    var choices: [WorkspaceWorktreeChoice] = []
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    static var loading: Self {
        Self(isLoading: true)
    }

    static func loaded(_ load: WorkspaceWorktreeChoiceLoad) -> Self {
        Self(
            choices: load.choices,
            hasLoaded: true,
            errorMessage: load.errorMessage
        )
    }
}

struct QuillCodeWorktreeOpenDraft: Equatable {
    var path = ""
    var choiceLoad = QuillCodeWorktreeChoiceLoadState()

    init(path: String = "", choiceLoad: QuillCodeWorktreeChoiceLoadState = QuillCodeWorktreeChoiceLoadState()) {
        self.path = path
        self.choiceLoad = choiceLoad
    }

    var canOpen: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeOpenRequest {
        WorkspaceWorktreeOpenRequest(path: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func select(_ choice: WorkspaceWorktreeChoice) {
        path = choice.path
    }
}

struct QuillCodeWorktreeRemoveDraft: Equatable {
    var path = ""
    var choiceLoad = QuillCodeWorktreeChoiceLoadState()
    var force = false

    init(
        path: String = "",
        choiceLoad: QuillCodeWorktreeChoiceLoadState = QuillCodeWorktreeChoiceLoadState(),
        force: Bool = false
    ) {
        self.path = path
        self.choiceLoad = choiceLoad
        self.force = force
    }

    var canRemove: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeRemoveRequest {
        WorkspaceWorktreeRemoveRequest(
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            force: force
        )
    }

    mutating func select(_ choice: WorkspaceWorktreeChoice) {
        path = choice.path
    }
}

struct QuillCodeWorktreePrunePreviewLoadState: Equatable {
    var records: [String] = []
    var output = ""
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    static var loading: Self {
        Self(isLoading: true)
    }

    static func loaded(_ preview: WorkspaceWorktreePrunePreview) -> Self {
        Self(
            records: preview.records,
            output: preview.output,
            hasLoaded: true,
            errorMessage: preview.errorMessage
        )
    }
}

struct QuillCodeWorktreePruneDraft: Equatable {
    var preview = QuillCodeWorktreePrunePreviewLoadState()

    var canPrune: Bool {
        preview.hasLoaded && !preview.isLoading && preview.errorMessage == nil && !preview.records.isEmpty
    }

    var confirmRequest: WorkspaceWorktreePruneRequest {
        WorkspaceWorktreePruneRequest(dryRun: false, verbose: true)
    }
}
