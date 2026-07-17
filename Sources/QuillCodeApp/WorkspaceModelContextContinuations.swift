import Foundation
import QuillCodeAgent
import QuillCodeCore

private enum ContextContinuationAction {
    case fork(strategy: WorkspaceThreadForkStrategy)
    case compact

    var purpose: WorkspaceContextSummaryPurpose {
        switch self {
        case .fork: .forkSummary
        case .compact: .compact
        }
    }

    var agentStatus: String {
        switch self {
        case .fork: "Summarizing context"
        case .compact: "Compacting context"
        }
    }
}

private struct ContextContinuationPreparation {
    let source: ChatThread
    let projectID: UUID?
    let summary: WorkspaceContextSummaryOutcome
}

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    func startForkThread(strategy: WorkspaceThreadForkStrategy) -> Bool {
        // The model-backed branch would send the transcript to an auxiliary summary model AND write
        // a durable continuation — both forbidden for ephemeral threads. The synchronous forkThread
        // fallback carries its own guard; this covers the async path.
        if let source = selectedThread, refuseDurableContinuation(of: source, action: "fork") {
            return false
        }
        guard strategy == .summarizedContext, contextSummaryGenerator.isModelBacked else {
            return forkThread(strategy: strategy) != nil
        }
        return startContextContinuation(.fork(strategy: strategy))
    }

    @discardableResult
    func forkThreadWithConfiguredSummary(
        sourceID: UUID,
        strategy: WorkspaceThreadForkStrategy
    ) async -> UUID? {
        guard strategy == .summarizedContext else { return forkThread(strategy: strategy) }
        guard let preparation = await preparedContextContinuation(
            sourceID: sourceID,
            purpose: .forkSummary
        ) else {
            return forkThread(strategy: strategy)
        }

        var fork = WorkspaceThreadCreationEngine.forkThread(
            from: preparation.source,
            projectID: preparation.projectID,
            strategy: strategy,
            summaryOverride: preparation.summary.summaryOverride
        )
        appendContextSummaryContinuation(to: &fork, preparation: preparation, purpose: .forkSummary)
        return insertCreatedThread(fork, selectedProjectID: preparation.projectID, saveThread: true)
    }

    @discardableResult
    func startCompactContext(workspaceRoot: URL) -> Bool {
        guard let sourceID = selectedContextSummarySourceID(),
              let source = contextSummarySourceThread(sourceID)
        else { return false }
        if refuseDurableContinuation(of: source, action: "compact") {
            return false
        }
        let hooks = pluginCompactionHookExecutor(for: source)
        guard contextSummaryGenerator.isModelBacked || hooks.hasExecutableHooks else {
            return compactContext() != nil
        }
        setAgentStatus(ContextContinuationAction.compact.agentStatus)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.compactContext(
                sourceID: sourceID,
                workspaceRoot: workspaceRoot,
                hooks: hooks
            )
            self.refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        }
        return true
    }

    @discardableResult
    func compactContextWithConfiguredSummary(sourceID: UUID) async -> UUID? {
        guard let preparation = await preparedContextContinuation(
            sourceID: sourceID,
            purpose: .compact
        ) else { return nil }

        var compacted = WorkspaceThreadCreationEngine.compactThread(
            from: preparation.source,
            projectID: preparation.projectID,
            summaryOverride: preparation.summary.summaryOverride
        )
        appendContextSummaryContinuation(to: &compacted, preparation: preparation, purpose: .compact)
        return insertCreatedThread(
            compacted,
            selectedProjectID: preparation.projectID,
            saveThread: true,
            sessionStartSource: .compact
        )
    }

    private func compactContext(
        sourceID: UUID,
        workspaceRoot: URL,
        hooks: ProjectPluginCompactionHookExecutor
    ) async -> UUID? {
        guard let source = contextSummarySourceThread(sourceID) else { return nil }
        let pre = await hooks.run(
            event: .preCompact,
            trigger: .manual,
            thread: source,
            workspaceRoot: workspaceRoot
        )
        appendCompactionHookNotices(pre.notices, to: sourceID)
        guard pre.continues else {
            recordContextSummarySourceNotice(
                sourceID: sourceID,
                summary: "Compaction stopped: \(pre.stopReason ?? "A trusted hook stopped this operation.")"
            )
            return nil
        }

        let projectID = knownProjectID(source.projectID)
        let compacted: ChatThread
        if contextSummaryGenerator.isModelBacked {
            recordContextSummaryStart(sourceID: sourceID, purpose: .compact)
            guard let preparation = await preparedContextContinuation(
                sourceID: sourceID,
                purpose: .compact
            ) else { return nil }
            var prepared = WorkspaceThreadCreationEngine.compactThread(
                from: preparation.source,
                projectID: preparation.projectID,
                summaryOverride: preparation.summary.summaryOverride
            )
            appendContextSummaryContinuation(
                to: &prepared,
                preparation: preparation,
                purpose: .compact
            )
            compacted = prepared
        } else {
            compacted = WorkspaceThreadCreationEngine.compactThread(
                from: source,
                projectID: projectID
            )
        }

        let post = await hooks.run(
            event: .postCompact,
            trigger: .manual,
            thread: source,
            workspaceRoot: workspaceRoot
        )
        var final = compacted
        for notice in post.notices {
            WorkspaceThreadNoticeAppender.appendNotice(notice, to: &final)
        }
        if !post.continues {
            WorkspaceThreadNoticeAppender.appendNotice(
                "Post-compaction hook stopped further continuation: "
                    + (post.stopReason ?? "A trusted hook requested a stop."),
                to: &final
            )
        }
        return insertCreatedThread(
            final,
            selectedProjectID: projectID,
            saveThread: true,
            sessionStartSource: .compact
        )
    }

    private func pluginCompactionHookExecutor(
        for source: ChatThread
    ) -> ProjectPluginCompactionHookExecutor {
        let project = source.projectID.flatMap { projectID in
            root.projects.first { $0.id == projectID }
        }
        return ProjectPluginCompactionHookExecutor(
            hooks: effectiveHookDefinitions(for: project),
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: project,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    private func appendCompactionHookNotices(_ notices: [String], to sourceID: UUID) {
        for notice in notices {
            recordContextSummarySourceNotice(sourceID: sourceID, summary: notice)
        }
    }

    private func startContextContinuation(_ action: ContextContinuationAction) -> Bool {
        guard let sourceID = selectedContextSummarySourceID() else { return false }
        setAgentStatus(action.agentStatus)
        recordContextSummaryStart(sourceID: sourceID, purpose: action.purpose)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch action {
            case .fork(let strategy):
                _ = await self.forkThreadWithConfiguredSummary(sourceID: sourceID, strategy: strategy)
            case .compact:
                _ = await self.compactContextWithConfiguredSummary(sourceID: sourceID)
            }
        }
        return true
    }

    private func selectedContextSummarySourceID() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        return source.id
    }

    private func preparedContextContinuation(
        sourceID: UUID,
        purpose: WorkspaceContextSummaryPurpose
    ) async -> ContextContinuationPreparation? {
        guard let source = contextSummarySourceThread(sourceID) else { return nil }
        // Belt to the entry guards: NO path may ship an ephemeral transcript to the auxiliary
        // summary model or mint a durable continuation from it.
        guard !source.runtimeContext.isEphemeral else { return nil }
        let projectID = knownProjectID(source.projectID)
        let summary = await configuredSummary(for: source, purpose: purpose)
        recordContextSummaryFinished(sourceID: sourceID, summary: summary, purpose: purpose)
        return ContextContinuationPreparation(source: source, projectID: projectID, summary: summary)
    }

    private func contextSummarySourceThread(_ sourceID: UUID) -> ChatThread? {
        guard let source = root.threads.first(where: { $0.id == sourceID }),
              !source.messages.isEmpty
        else { return nil }
        return source
    }

    private func configuredSummary(
        for source: ChatThread,
        purpose: WorkspaceContextSummaryPurpose
    ) async -> WorkspaceContextSummaryOutcome {
        // Summaries/compaction are auxiliary housekeeping: route them to a cheap catalog model
        // instead of the thread's flagship model. The thread's own model is never touched here.
        // BUT a thread routed to the E2E-encrypted model must keep this auxiliary traffic on the E2E
        // route too — the cheap catalog aux model is never E2E, so summarize DETERMINISTICALLY (no
        // egress) rather than shipping the transcript to it. This mirrors `requiresE2EOnlyTraffic` in
        // WorkspaceAgentRunContextBuilder, which the standalone /compact and /fork summary path never
        // goes through. Incognito threads never reach here (the isEphemeral belt guard in
        // preparedContextContinuation returns first), so this covers a REGULAR thread that selected
        // "E2E Encrypted" from the Private category or via `/model e2e`.
        let routesE2EOnly = TrustedRouterDefaults.canonicalModelID(source.model)
            == TrustedRouterDefaults.e2eModel
        let generator: any WorkspaceContextSummaryGenerating = routesE2EOnly
            ? DeterministicWorkspaceContextSummaryGenerator()
            : contextSummaryGenerator
        let selection = generator.isModelBacked
            ? AuxiliaryModelSelector.selection(models: root.modelCatalog, sessionModelID: source.model)
            : nil
        let request = WorkspaceContextSummaryRequest(
            sourceTitle: source.title,
            context: WorkspaceThreadSeedBuilder.summaryContext(from: source),
            purpose: purpose,
            modelID: selection?.modelID
        )
        // An E2E-routed summary is local BY DESIGN, not a failure — record it as its own source so the
        // notice says so, instead of the misleading "model summary unavailable; used deterministic
        // fallback". A genuine generator failure still lands in the catch below as .deterministicFallback.
        let outcomeSource: WorkspaceContextSummaryOutcomeSource = if routesE2EOnly {
            .e2eDeterministic
        } else if generator.isModelBacked {
            .model
        } else {
            .deterministicFallback
        }
        do {
            return WorkspaceContextSummaryOutcome(
                summaryOverride: try await generator.summary(for: request),
                source: outcomeSource,
                modelSelection: selection
            )
        } catch {
            return WorkspaceContextSummaryOutcome(
                summaryOverride: nil,
                source: .deterministicFallback,
                errorDescription: WorkspaceContextSummarySanitizer.diagnostic(from: error.localizedDescription),
                modelSelection: selection
            )
        }
    }

    private func appendContextSummaryContinuation(
        to thread: inout ChatThread,
        preparation: ContextContinuationPreparation,
        purpose: WorkspaceContextSummaryPurpose
    ) {
        thread.events.append(
            WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
                outcome: preparation.summary,
                sourceTitle: preparation.source.title,
                purpose: purpose
            )
        )
    }

    private func recordContextSummaryStart(sourceID: UUID, purpose: WorkspaceContextSummaryPurpose) {
        recordContextSummarySourceNotice(
            sourceID: sourceID,
            summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: purpose)
        )
    }

    private func recordContextSummaryFinished(
        sourceID: UUID,
        summary: WorkspaceContextSummaryOutcome,
        purpose: WorkspaceContextSummaryPurpose
    ) {
        recordContextSummarySourceNotice(
            sourceID: sourceID,
            summary: WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: summary,
                purpose: purpose
            )
        )
    }

    private func recordContextSummarySourceNotice(sourceID: UUID, summary: String) {
        _ = mutateThread(sourceID) { thread in
            WorkspaceThreadNoticeAppender.appendNotice(summary, to: &thread)
        }
    }
}
