import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeReview
import QuillCodeTools

@MainActor
public extension QuillCodeWorkspaceModel {
    func presentCodeReview() {
        guard selectedProject != nil else {
            setLastError("Open a Git project before starting a code review.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return
        }
        codeReviewRequest = WorkspaceCodeReviewRequest(
            delivery: root.config.reviewDelivery,
            model: root.config.reviewModel
        )
        setLastError(nil)
    }

    func dismissCodeReview() {
        codeReviewRequest = nil
    }

    /// Runs a dedicated reviewer against the selected project's current execution root. The
    /// reviewer has a separate read-only tool catalog; only the normalized report is merged back
    /// into the durable task, so investigation output never bloats future agent context.
    @discardableResult
    func runCodeReview(
        _ rawRequest: WorkspaceCodeReviewRequest,
        workspaceRoot: URL,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async -> Bool {
        let request = WorkspaceCodeReviewRequest(
            scope: rawRequest.scope,
            reference: rawRequest.reference,
            instructions: rawRequest.instructions,
            title: rawRequest.title,
            delivery: rawRequest.delivery,
            model: rawRequest.model
        )
        guard let validationMessage = request.validationMessage else {
            return await runValidatedCodeReview(
                request,
                workspaceRoot: workspaceRoot,
                onProgressUpdated: onProgressUpdated
            )
        }
        setLastError(validationMessage)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
        return false
    }

    private func runValidatedCodeReview(
        _ request: WorkspaceCodeReviewRequest,
        workspaceRoot: URL,
        onProgressUpdated: (@MainActor @Sendable () -> Void)?
    ) async -> Bool {
        guard selectedProject != nil else {
            return failCodeReviewPreflight("Open a Git project before starting a code review.")
        }
        if request.delivery == .current,
           let selectedThreadID = selectedThread?.id,
           agentRuns.isRunning(selectedThreadID) {
            return failCodeReviewPreflight("This task already has an active run.")
        }
        let preflight = codeReviewGitStatus(workspaceRoot: workspaceRoot)
        guard preflight.ok else {
            return failCodeReviewPreflight(
                WorkspaceCodeReviewPreflightMessage.failure(from: preflight)
            )
        }

        let targetThreadID: UUID
        if request.delivery == .detached {
            targetThreadID = newChat(projectID: root.selectedProjectID)
            mutateThread(targetThreadID) { thread in
                thread.title = "Code review: \(request.scope.title)"
            }
        } else {
            targetThreadID = selectedThread?.id ?? newChat(projectID: root.selectedProjectID)
        }
        guard !agentRuns.isRunning(targetThreadID),
              var targetThread = root.threads.first(where: { $0.id == targetThreadID })
        else {
            setLastError("This task already has an active run.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }

        refreshProjectMetadata(targetThread.projectID)
        _ = WorkspaceThreadContextPreparer.syncThreadContext(
            &targetThread,
            fallbackProjectID: targetThread.projectID,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
        let reviewModel = request.model ?? root.config.reviewModel ?? targetThread.model
        appendStartedCodeReview(request, to: targetThreadID)
        codeReviewRequest = nil
        beginAgentRun(
            threadID: targetThreadID,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: composer)
        )
        onProgressUpdated?()

        let collector = WorkspaceCodeReviewReportCollector()
        let runProject = targetThread.projectID.flatMap(project(id:))
        let reviewRunner = agentSendSessionFactory(
            workspaceRoot: workspaceRoot,
            runProject: runProject
        ).configuredCodeReviewRunner(
            modelID: reviewModel,
            threadID: targetThreadID,
            reportCollector: collector,
            threadIsIncognito: targetThread.runtimeContext.isIncognito
        )
        let reviewThread = scratchReviewThread(from: targetThread, model: reviewModel)
        let prompt = WorkspaceCodeReviewPromptBuilder(request: request).prompt()

        do {
            let result = try await AgentRunRetryScope.$threadID.withValue(targetThreadID) {
                try await reviewRunner.send(
                    prompt,
                    in: reviewThread,
                    workspaceRoot: workspaceRoot
                ) { [weak self] progress in
                    guard let self else { return }
                    await self.updateAgentRun(
                        threadID: targetThreadID,
                        status: WorkspaceAgentStatusBuilder.status(for: progress)
                    )
                    await onProgressUpdated?()
                }
            }
            guard result.stopReason == .finished else {
                throw WorkspaceCodeReviewRunError.incomplete(result.stopReason)
            }
            guard let report = await collector.report else {
                throw WorkspaceCodeReviewRunError.missingReport
            }
            finishCodeReview(report, request: request, threadID: targetThreadID, workspaceRoot: workspaceRoot)
            finishAgentRun(
                threadID: targetThreadID,
                lifecycle: WorkspaceComposerSendLifecycle.completed(from: composer)
            )
            onProgressUpdated?()
            return true
        } catch is CancellationError {
            appendCodeReviewFailure("Code review stopped.", to: targetThreadID)
            finishAgentRun(
                threadID: targetThreadID,
                lifecycle: WorkspaceComposerSendLifecycle.cancelled(from: composer)
            )
            onProgressUpdated?()
            return false
        } catch {
            appendCodeReviewFailure("Code review failed: \(error)", to: targetThreadID)
            finishAgentRun(
                threadID: targetThreadID,
                lifecycle: WorkspaceComposerSendLifecycle.failed(error, from: composer)
            )
            onProgressUpdated?()
            return false
        }
    }

    private func appendStartedCodeReview(_ request: WorkspaceCodeReviewRequest, to threadID: UUID) {
        mutateThread(threadID) { thread in
            let message = ChatMessage(role: .user, content: request.transcriptPrompt)
            thread.messages.append(message)
            thread.events.append(ThreadEvent(kind: .message, summary: request.transcriptPrompt))
            if thread.title == "New chat" {
                thread.title = "Code review: \(request.scope.title)"
            }
        }
    }

    private func scratchReviewThread(from source: ChatThread, model: String) -> ChatThread {
        ChatThread(
            id: source.id,
            title: source.title,
            projectID: source.projectID,
            mode: .readOnly,
            model: model,
            instructions: source.instructions,
            memories: source.memories,
            worktree: source.worktree,
            pullRequest: source.pullRequest
        )
    }

    private func finishCodeReview(
        _ report: WorkspaceCodeReviewReport,
        request: WorkspaceCodeReviewRequest,
        threadID: UUID,
        workspaceRoot: URL
    ) {
        mutateThread(threadID) { thread in
            let markdown = report.transcriptMarkdown
            thread.messages.append(ChatMessage(role: .assistant, content: markdown))
            thread.events.append(ThreadEvent(kind: .message, summary: report.summary))
            thread.events.append(contentsOf: report.findings.map {
                WorkspaceReviewCommentPlanner.event(for: $0)
            })
        }
        guard root.selectedThreadID == threadID else { return }
        runReviewScopeChange(request.reviewSelection, workspaceRoot: workspaceRoot)
    }

    private func appendCodeReviewFailure(_ message: String, to threadID: UUID) {
        mutateThread(threadID) { thread in
            WorkspaceThreadNoticeAppender.appendAssistantNotice(message, to: &thread)
        }
    }

    private func codeReviewGitStatus(workspaceRoot: URL) -> ToolResult {
        let call = ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}")
        if let project = selectedProject, project.isRemote {
            return WorkspaceRemoteProjectToolExecutor.execute(
                call,
                project: project,
                executor: sshRemoteShellExecutor
            )
        }
        return ToolRouter(workspaceRoot: workspaceRoot, editGuard: uiEditSessionGuard).execute(call)
    }

    private func failCodeReviewPreflight(_ message: String) -> Bool {
        setLastError(message)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
        return false
    }
}

private enum WorkspaceCodeReviewPreflightMessage {
    static func failure(from result: ToolResult) -> String {
        let detail = [result.error, result.stderr]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let detail else {
            return "Code review requires a reachable Git repository."
        }
        return "Code review requires a reachable Git repository. \(detail)"
    }
}

private extension WorkspaceCodeReviewRequest {
    var reviewSelection: WorkspaceReviewSelection {
        switch scope {
        case .uncommitted, .custom:
            .unstaged
        case .baseBranch:
            .branch(reference ?? "HEAD")
        case .commit:
            .commit(reference ?? "HEAD")
        }
    }
}

private enum WorkspaceCodeReviewRunError: Error, CustomStringConvertible {
    case incomplete(AgentRunStopReason)
    case missingReport

    var description: String {
        switch self {
        case .incomplete(let reason):
            "The reviewer stopped before completing its report (\(reason))."
        case .missingReport:
            "The reviewer returned without submitting the required structured report."
        }
    }
}
