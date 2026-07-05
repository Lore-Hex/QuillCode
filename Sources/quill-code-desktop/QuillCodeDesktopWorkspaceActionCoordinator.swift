import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
struct QuillCodeDesktopWorkspaceActionCoordinator {
    private let sourceOpener: any QuillCodeDesktopSourceOpening

    init(sourceOpener: any QuillCodeDesktopSourceOpening = MacSourceOpener()) {
        self.sourceOpener = sourceOpener
    }

    func runToolCardAction(
        _ action: ToolCardActionSurface,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        let workspaceRoot = activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        guard action.kind.decidesGate else {
            // `edit` only seeds a composer draft (it leaves the gate undecided) — immediate, local,
            // and unaffected by any in-flight send.
            _ = model.runToolCardAction(action, workspaceRoot: workspaceRoot)
            return
        }

        guard action.kind.approvesHeldTool else {
            // DENY / skip is a REFUSAL — you must always be able to refuse a held tool, so record the
            // decision UNCONDITIONALLY (it runs no held tool and no resume, so it needs no `.send`
            // slot and is never dropped by an in-flight send). Then drain any queued follow-ups
            // through the `.send` slot; the drain self-gates via `canDrainAfter`. If the slot is busy
            // running ANOTHER thread, this drain is skipped — the decided thread's queue is then
            // recovered by `recoverFollowUpQueueIfIdle` when that thread is next selected or when the
            // slot frees (both wired in the controller), so a cross-thread deny never strands it.
            _ = model.runToolCardAction(action, workspaceRoot: workspaceRoot)
            let decidedThreadID = model.selectedThread?.id
            tasks.startIfIdle(.send) { [weak model] in
                await model?.drainFollowUpQueueAfterGateDecision(
                    threadID: decidedThreadID,
                    workspaceRoot: workspaceRoot
                )
            } onFinish: {
                refresh()
            }
            refresh()
            return
        }

        // APPROVE runs the held tool AND resumes the plan — route the WHOLE thing through the same
        // `.send` slot a composer send uses (gated up front, mirroring the composer), so the held
        // tool + resume + follow-up drain are atomic, Stop cancels them, and they never interleave
        // with another send. `approveToolCardAndResume` is the single async choke point the tests
        // drive: it resolves the gate and then drains any queued follow-ups.
        guard !tasks.isRunning(.send) else { return }
        tasks.startIfIdle(.send) { [weak model] in
            _ = await model?.approveToolCardAndResume(action, workspaceRoot: workspaceRoot)
        } onFinish: {
            refresh()
        }
    }

    func runReviewAction(
        _ action: WorkspaceReviewActionSurface,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runReviewAction(
            action,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func runTurnRevert(
        turnMessageID: UUID,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runTurnRevert(
            turnMessageID: turnMessageID,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func runPullRequestReviewThreadAction(
        _ action: WorkspacePullRequestReviewThreadActionSurface,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runPullRequestReviewThreadAction(
            action,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func runPullRequestReviewThreadReply(
        _ request: WorkspacePullRequestReviewThreadReplyRequest,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runPullRequestReviewThreadReply(
            request,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func updatePullRequestReviewDraft(
        _ draft: WorkspacePullRequestReviewDraftSurface,
        model: QuillCodeWorkspaceModel
    ) {
        model.updatePullRequestReviewDraft(draft)
    }

    func cancelPullRequestReviewDraft(model: QuillCodeWorkspaceModel) {
        model.cancelPullRequestReviewDraft()
    }

    func submitPullRequestReviewDraft(
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        _ = model.submitPullRequestReviewDraft(
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func useComposerDraft(_ draft: String, model: QuillCodeWorkspaceModel) {
        model.setDraft(draft)
    }

    func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int?,
        lineKind: WorkspaceReviewLineKind?,
        text: String,
        model: QuillCodeWorkspaceModel
    ) {
        _ = model.addReviewComment(
            path: path,
            lineNumber: lineNumber,
            endLineNumber: endLineNumber,
            lineKind: lineKind,
            text: text
        )
    }

    @discardableResult
    func runWorkspaceCommand(
        _ commandID: String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) -> Bool {
        if let sourceCommand = WorkspaceActivitySourceCommand(commandID: commandID),
           let workspaceRoot = sourceWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot),
           let request = sourceOpenRequest(for: sourceCommand, workspaceRoot: workspaceRoot),
           sourceOpener.openSource(request) {
            return true
        }

        return model.runWorkspaceCommand(
            commandID,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    private func activeWorkspaceRoot(for model: QuillCodeWorkspaceModel, fallback: URL) -> URL {
        model.activeWorkspaceRoot ?? fallback
    }

    private func sourceWorkspaceRoot(for model: QuillCodeWorkspaceModel, fallback: URL) -> URL? {
        if let selectedProject = model.selectedProject {
            return selectedProject.isRemote ? nil : URL(fileURLWithPath: selectedProject.path)
        }
        if let projectID = model.selectedThread?.projectID,
           let project = model.root.projects.first(where: { $0.id == projectID }) {
            return project.isRemote ? nil : URL(fileURLWithPath: project.path)
        }
        return fallback
    }

    private func sourceOpenRequest(
        for command: WorkspaceActivitySourceCommand,
        workspaceRoot: URL
    ) -> QuillCodeDesktopSourceOpenRequest? {
        guard !NSString(string: command.path).isAbsolutePath else { return nil }
        let rootURL = workspaceRoot.standardizedFileURL
        let fileURL = rootURL.appendingPathComponent(command.path).standardizedFileURL
        guard fileIsReadableRegularFile(fileURL),
              fileURL.isDescendant(of: rootURL)
        else {
            return nil
        }
        return QuillCodeDesktopSourceOpenRequest(fileURL: fileURL, lineNumber: command.lineNumber)
    }

    private func fileIsReadableRegularFile(_ fileURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
}

private extension URL {
    func isDescendant(of rootURL: URL) -> Bool {
        let rootPath = rootURL.resolvingSymlinksInPath().path
        let filePath = resolvingSymlinksInPath().path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }
}
