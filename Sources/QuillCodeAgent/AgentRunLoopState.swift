import Foundation
import QuillCodeCore

struct AgentRunLoopState: Sendable {
    private(set) var toolResults: [ToolResult] = []
    private(set) var lastExecutedCall: ToolCall?
    private(set) var lastCompletion: AgentToolStepCompletion?
    /// True once any tool action was DENIED this run. The deliverable gate (F23) skips
    /// enforcement then: a blocked write is a legitimate reason for a missing file.
    private(set) var hadDeniedStep = false
    /// F29 grounded-provenance state. `groundedURLs` holds the normalized URL of every page this
    /// run verifiably encountered: requested + final URLs of successful fetches, plus every URL
    /// appearing in successful tool output EXCEPT `host.web.search` (search snippets are exactly
    /// the ungrounded source the citation gate exists to reject). `didFetchSuccessfully` arms the
    /// gate; `writtenWorkspacePaths` limits deliverable scanning to files this run itself wrote.
    private(set) var groundedURLs: Set<String> = []
    private(set) var didFetchSuccessfully = false
    private(set) var writtenWorkspacePaths: Set<String> = []
    /// A successful write remains here until a LATER successful read of the same path. Rewrites
    /// re-arm verification, preventing an early read from blessing a subsequently changed file.
    private(set) var unverifiedWrittenWorkspacePaths: Set<String> = []
    /// Workspace files successfully read this run. Empty-response recovery uses this to advance
    /// only the finite set of source reads the user explicitly requested and has not completed.
    private(set) var successfullyReadWorkspacePaths: Set<String> = []
    /// Task-named deliverables that must be read after their latest write. Shell tools can create
    /// rich artifacts that do not appear in ToolResult.artifacts, so successful shell steps use
    /// this bounded set to discover those outputs on disk and arm the normal readback gate.
    private var requiredReadbackWorkspacePaths: Set<String> = []
    /// Task-named text deliverables whose latest write predates a successful live-page fetch.
    /// Terminal completion is gated until a later write incorporates or dispositions that evidence;
    /// the ordinary readback gate then verifies the refreshed artifact.
    private(set) var researchStaleWorkspacePaths: Set<String> = []
    private var namedTextDeliverableWorkspacePaths: Set<String> = []
    /// Weighted research pressure accumulated before the first durable named-text draft. Failed
    /// web attempts still consume context and identify evidence gaps, so they count toward the
    /// checkpoint threshold. A successful delegated result counts more because it can carry
    /// several evidence tracks. Long runs checkpoint before compaction can restart the search.
    private(set) var researchPressureWeightBeforeDraft = 0
    /// Paths for which the runner explicitly requested a forced research checkpoint. The first
    /// successful write arms continuation; only a later write after renewed web work clears it.
    private var expectedResearchCheckpointWorkspacePaths: Set<String> = []
    private(set) var pendingResearchContinuationWorkspacePaths: Set<String> = []
    private var resumedResearchCheckpointWorkspacePaths: Set<String> = []
    /// Weighted successful research actions completed after a forced draft. Once this bounded
    /// budget is reached, the runner requires synthesis before permitting another read-only step.
    /// Delegated research counts more than one serial web call because it can return several full
    /// evidence tracks in a single tool result.
    private(set) var successfulResearchStepsAfterCheckpoint = 0
    /// Successful parent-authored delegated batches in this run. Once a named deliverable exists,
    /// another broad batch is usually a restart rather than progress and should be synthesized.
    private(set) var successfulDelegatedResearchBatchCount = 0
    /// Named prose artifacts whose latest successful write contains serialized newline/tab escapes
    /// in visible text. A clean rewrite removes the path before terminal quality enforcement.
    private(set) var malformedWrittenTextPaths: Set<String> = []
    /// Latest malformed content by normalized path. Retained across readback so the runner can
    /// deterministically decode visible formatting escapes after one ignored rewrite request.
    private(set) var malformedWrittenTextContents: [String: String] = [:]
    /// Named prose artifacts whose latest successful write contains bracketed fill-in tokens.
    /// Enforcement is armed only when the user explicitly requests a placeholder-free artifact.
    private(set) var placeholderWrittenTextPaths: Set<String> = []
    /// Latest invalid content by normalized path. Retained across readback so the runner can make
    /// a deterministic blank-field repair if the model ignores its one natural-rewrite request.
    private(set) var placeholderWrittenTextContents: [String: String] = [:]
    /// Named prose artifacts whose latest write declares a count that conflicts with an adjacent
    /// list of source record IDs.
    private(set) var contradictoryCountWrittenTextPaths: Set<String> = []
    /// Latest contradictory content by normalized path, retained for a bounded deterministic fix.
    private(set) var contradictoryCountWrittenTextContents: [String: String] = [:]
    /// Markdown artifacts whose latest write leaves a heading without substantive section content.
    private(set) var incompleteMarkdownWrittenTextPaths: Set<String> = []
    /// Latest incomplete Markdown by normalized path, retained for a bounded heading removal.
    private(set) var incompleteMarkdownWrittenTextContents: [String: String] = [:]
    /// Latest successful text write by normalized path. Source-audit verification compares the
    /// audited rewrite with this snapshot so formatting-only writes do not trigger another model
    /// pass.
    private(set) var latestWrittenTextContents: [String: String] = [:]
    /// Explicitly source-only runs retain the user's request plus successful reads of source files.
    /// Latest writes are checked only for a narrow set of high-risk assertions that can be safely
    /// compared mechanically with that corpus.
    private var enforcesSourceOnlyGrounding = false
    private(set) var sourceGroundingText = ""
    /// Successful tabular source reads retain their path so aggregate artifact rows can be checked
    /// against the exact records rather than flattened prose context.
    private(set) var sourceReadsByPath: [String: String] = [:]
    private(set) var tabularSourceIssuesByPath: [String: [String]] = [:]
    private(set) var unsupportedSourceClaimWrittenTextPaths: Set<String> = []
    private(set) var unsupportedSourceClaimWrittenTextContents: [String: String] = [:]

    /// Call signatures that have already received the repeat SOFT WARNING (Cline learning #2).
    /// One nudge per distinct call; a further repeat of the same call finalizes as before, so the
    /// tier can never loop.
    private var softWarnedCallSignatures: Set<String> = []

    private var flailDetector = FlailDetector()
    private var previousWorkspaceState: String?
    private var injectedFlailAssessment = false

    var latestCompletion: AgentToolStepCompletion? {
        lastCompletion
    }

    func repeatedCompletion(for call: ToolCall) -> AgentToolStepCompletion? {
        guard let lastExecutedCall,
              lastExecutedCall.name == call.name,
              lastExecutedCall.argumentsJSON == call.argumentsJSON
        else {
            return nil
        }
        return lastCompletion
    }

    mutating func baselineWorkspaceStateIfNeeded(
        workspaceRoot: URL,
        stateSignature: (URL) -> String
    ) {
        if previousWorkspaceState == nil {
            previousWorkspaceState = stateSignature(workspaceRoot)
        }
    }

    mutating func recordCompletedStep(
        _ completion: AgentToolStepCompletion,
        workspaceRoot: URL,
        stateSignature: (URL) -> String
    ) -> FlailVerdict {
        toolResults.append(contentsOf: completion.toolResults)
        lastExecutedCall = completion.call
        lastCompletion = completion
        recordArtifactVerification(completion, workspaceRoot: workspaceRoot)
        recordCitationProvenance(completion)
        recordResearchCheckpointProgress(completion)

        let workspaceState = stateSignature(workspaceRoot)
        let deltaSignature = workspaceState == previousWorkspaceState ? "" : workspaceState
        previousWorkspaceState = workspaceState
        return flailDetector.record(FlailTurnRecord(
            fingerprints: [
                ToolCallFingerprint.make(call: completion.call, workspaceRoot: workspaceRoot)
            ],
            deltaSignature: deltaSignature,
            failureSignature: FlailSignatures.failureSignature(fromToolOutput: [
                completion.result.stdout,
                completion.result.stderr,
                completion.result.error ?? "",
            ].joined(separator: "\n"))
        ))
    }

    mutating func seedArtifactVerification(userMessage: String) {
        let deliverables = AgentDeliverableGate.requiredDeliverables(in: userMessage).map(
            AgentArtifactVerificationGate.normalizedPath
        )
        namedTextDeliverableWorkspacePaths = Set(deliverables.filter(Self.isResearchTextArtifact))
        if AgentArtifactVerificationGate.requiresReadback(in: userMessage) {
            requiredReadbackWorkspacePaths = Set(deliverables)
        }
    }

    func pendingResearchCheckpointPath(minimumResearchWeight: Int) -> String? {
        guard researchPressureWeightBeforeDraft >= minimumResearchWeight else { return nil }
        return namedTextDeliverableWorkspacePaths.sorted().first { path in
            !writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, path)
            })
        }
    }

    mutating func expectResearchCheckpoint(at path: String) {
        expectedResearchCheckpointWorkspacePaths.insert(
            AgentArtifactVerificationGate.normalizedPath(path)
        )
    }

    func pendingResearchContinuationPath() -> String? {
        pendingResearchContinuationWorkspacePaths.sorted().first
    }

    func didResumeResearch(afterCheckpointAt path: String) -> Bool {
        resumedResearchCheckpointWorkspacePaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, path)
        })
    }

    func pendingResearchFinalizationPath(minimumResearchSteps: Int) -> String? {
        guard successfulResearchStepsAfterCheckpoint >= minimumResearchSteps else { return nil }
        return pendingResearchContinuationWorkspacePaths.sorted().first(where: {
            didResumeResearch(afterCheckpointAt: $0)
        })
    }

    func writtenNamedTextDeliverablePath() -> String? {
        namedTextDeliverableWorkspacePaths.sorted().first { path in
            writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, path)
            })
        }
    }

    mutating func requireResearchRefresh(at path: String) {
        researchStaleWorkspacePaths.insert(AgentArtifactVerificationGate.normalizedPath(path))
    }

    private mutating func recordArtifactVerification(
        _ completion: AgentToolStepCompletion,
        workspaceRoot: URL
    ) {
        guard completion.result.ok else { return }
        if completion.call.name == ToolDefinition.shellRun.name {
            for path in requiredReadbackWorkspacePaths where
                AgentArtifactVerificationGate.isExistingWorkspaceFile(
                    path,
                    workspaceRoot: workspaceRoot
                ) {
                writtenWorkspacePaths.insert(path)
                unverifiedWrittenWorkspacePaths.insert(path)
            }
            return
        }
        if completion.call.name == ToolDefinition.fileReadMany.name,
           let arguments = try? ToolArguments(completion.call.argumentsJSON),
           let paths = arguments.stringArray("paths") {
            recordSuccessfulFileReads(paths: paths, output: completion.result.stdout)
            return
        }
        guard let path = AgentArtifactVerificationGate.pathArgument(from: completion.call) else {
            return
        }
        let normalized = AgentArtifactVerificationGate.normalizedPath(path)
        switch completion.call.name {
        case ToolDefinition.chartRender.name:
            writtenWorkspacePaths.insert(normalized)
            unverifiedWrittenWorkspacePaths.insert(normalized)
            markResearchArtifactRefreshed(normalized)
        case ToolDefinition.fileWrite.name:
            unverifiedWrittenWorkspacePaths.insert(normalized)
            markResearchArtifactRefreshed(normalized)
            if let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let content = arguments.string("content") {
                latestWrittenTextContents[normalized] = content
            }
            if let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let content = arguments.string("content"),
               AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
                content: content,
                path: normalized
               ) {
                malformedWrittenTextPaths.insert(normalized)
                malformedWrittenTextContents[normalized] = content
            } else {
                malformedWrittenTextPaths.remove(normalized)
                malformedWrittenTextContents.removeValue(forKey: normalized)
            }
            if let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let content = arguments.string("content"),
               AgentArtifactTextQualityGate.containsBracketedPlaceholder(
                content: content,
                path: normalized
               ) {
                placeholderWrittenTextPaths.insert(normalized)
                placeholderWrittenTextContents[normalized] = content
            } else {
                placeholderWrittenTextPaths.remove(normalized)
                placeholderWrittenTextContents.removeValue(forKey: normalized)
            }
            if let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let content = arguments.string("content"),
               AgentArtifactTextQualityGate.containsContradictoryEnumeratedCount(
                content: content,
                path: normalized
               ) {
                contradictoryCountWrittenTextPaths.insert(normalized)
                contradictoryCountWrittenTextContents[normalized] = content
            } else {
                contradictoryCountWrittenTextPaths.remove(normalized)
                contradictoryCountWrittenTextContents.removeValue(forKey: normalized)
            }
            if let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let content = arguments.string("content"),
               !AgentArtifactTextQualityGate.emptyMarkdownSectionTitles(
                content: content,
                path: normalized
               ).isEmpty {
                incompleteMarkdownWrittenTextPaths.insert(normalized)
                incompleteMarkdownWrittenTextContents[normalized] = content
            } else {
                incompleteMarkdownWrittenTextPaths.remove(normalized)
                incompleteMarkdownWrittenTextContents.removeValue(forKey: normalized)
            }
            if enforcesSourceOnlyGrounding,
               let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let content = arguments.string("content"),
               AgentSourceGroundingGate.containsUnsupportedSensitiveClaim(
                content: content,
                path: normalized,
                sourceText: sourceGroundingText
               ) {
                unsupportedSourceClaimWrittenTextPaths.insert(normalized)
                unsupportedSourceClaimWrittenTextContents[normalized] = content
            } else {
                unsupportedSourceClaimWrittenTextPaths.remove(normalized)
                unsupportedSourceClaimWrittenTextContents.removeValue(forKey: normalized)
            }
            if enforcesSourceOnlyGrounding,
               let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let content = arguments.string("content") {
                let issues = AgentTabularSourceGroundingGate.issues(
                    content: content,
                    path: normalized,
                    sourceReadsByPath: sourceReadsByPath
                )
                if issues.isEmpty {
                    tabularSourceIssuesByPath.removeValue(forKey: normalized)
                } else {
                    tabularSourceIssuesByPath[normalized] = issues
                }
            } else {
                tabularSourceIssuesByPath.removeValue(forKey: normalized)
            }
        case ToolDefinition.fileRead.name:
            recordSuccessfulFileReads(paths: [path], output: completion.result.stdout)
        default:
            break
        }
    }

    private mutating func recordSuccessfulFileReads(paths: [String], output: String) {
        let normalizedPaths = paths.map(AgentArtifactVerificationGate.normalizedPath)
        for normalized in normalizedPaths {
            successfullyReadWorkspacePaths.insert(normalized)
            unverifiedWrittenWorkspacePaths = Set(unverifiedWrittenWorkspacePaths.filter {
                !AgentArtifactVerificationGate.pathsMatch($0, normalized)
            })
        }
        let sourcePaths = normalizedPaths.filter { normalized in
            !writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, normalized)
            })
        }
        guard enforcesSourceOnlyGrounding, !sourcePaths.isEmpty else { return }
        sourceGroundingText += "\n" + output
        sourceReadsByPath[sourcePaths.joined(separator: " | ")] = output
        for (writtenPath, content) in latestWrittenTextContents {
            let issues = AgentTabularSourceGroundingGate.issues(
                content: content,
                path: writtenPath,
                sourceReadsByPath: sourceReadsByPath
            )
            if issues.isEmpty {
                tabularSourceIssuesByPath.removeValue(forKey: writtenPath)
            } else {
                tabularSourceIssuesByPath[writtenPath] = issues
            }
        }
    }

    func latestWrittenTextContent(for path: String) -> String? {
        latestWrittenTextContents.first(where: {
            AgentArtifactVerificationGate.pathsMatch($0.key, path)
        })?.value
    }

    /// Seeds the grounded set from context that predates this run's tool steps: the user's
    /// request and the thread's prior messages. Called once by the runner before the loop.
    mutating func seedCitationProvenance(userMessage: String, thread: ChatThread) {
        for url in AgentCitationIntegrityGate.allURLs(in: userMessage) {
            groundedURLs.insert(AgentCitationIntegrityGate.normalize(url))
        }
        for message in thread.messages {
            for url in AgentCitationIntegrityGate.allURLs(in: message.content) {
                groundedURLs.insert(AgentCitationIntegrityGate.normalize(url))
            }
        }
    }

    mutating func seedSourceGrounding(userMessage: String) {
        enforcesSourceOnlyGrounding = AgentSourceGroundingGate.requestsSourceOnlyGrounding(
            in: userMessage
        )
        sourceGroundingText = enforcesSourceOnlyGrounding ? userMessage : ""
        sourceReadsByPath = [:]
        tabularSourceIssuesByPath = [:]
    }

    private mutating func recordCitationProvenance(_ completion: AgentToolStepCompletion) {
        guard completion.result.ok else { return }
        let name = completion.call.name
        // Whole-file producers register their requested path plus the executor's absolute artifact
        // path. apply_patch reports no artifacts; a patch-authored deliverable is simply not scanned.
        if name == ToolDefinition.fileWrite.name || name == ToolDefinition.chartRender.name {
            if let data = completion.call.argumentsJSON.data(using: .utf8),
               let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let path = arguments["path"] as? String {
                writtenWorkspacePaths.insert(path)
            }
            for artifact in completion.result.artifacts {
                writtenWorkspacePaths.insert(artifact)
            }
        }
        if name == "host.web.fetch" || name == ToolDefinition.subagentsRun.name {
            // Delegated results are new research observations just like fetched pages. If they
            // arrive after an artifact write, that artifact must be reconciled before completion.
            // This is especially important when one worker returns usable evidence alongside a
            // partial/failed worker: the parent should preserve what it learned, not silently bless
            // the pre-delegation draft.
            if name == "host.web.fetch" {
                didFetchSuccessfully = true
            }
            for path in namedTextDeliverableWorkspacePaths where
                writtenWorkspacePaths.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, path)
                }) {
                researchStaleWorkspacePaths.insert(path)
            }
        }
        if name == "host.web.fetch" {
            if let data = completion.call.argumentsJSON.data(using: .utf8),
               let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let requested = arguments["url"] as? String {
                groundedURLs.insert(AgentCitationIntegrityGate.normalize(requested))
            }
        }
        // Every URL visible in successful non-search output is grounded provenance: the final
        // fetch URL in the summary line, links inside fetched page content, URLs in files the
        // run read, addresses printed by shell commands. Search output stays ungrounded — a
        // snippet listing is not a read page, and it is the observed leak source.
        guard name != "host.web.search" else { return }
        // Self-confirmation guard: the system prompt MANDATES reading a written artifact back
        // ("read the artifact back (host.file.read / host.file.list) to confirm it exists"), so
        // harvesting that read's output would launder the model's own text into provenance — write
        // a fabricated URL, read the file back, and the citation gate blesses it. A read of a file
        // this run wrote proves nothing about the world. (Residual: `cat`-style shell echoes of an
        // own-written file are not detectable here; the mandated path is host.file.read.)
        guard !isReadOfOwnOutput(completion) else { return }
        for url in AgentCitationIntegrityGate.allURLs(in: completion.result.stdout) {
            groundedURLs.insert(AgentCitationIntegrityGate.normalize(url))
        }
    }

    private mutating func markResearchArtifactRefreshed(_ writtenPath: String) {
        researchStaleWorkspacePaths = Set(researchStaleWorkspacePaths.filter {
            !AgentArtifactVerificationGate.pathsMatch($0, writtenPath)
        })
    }

    private mutating func recordResearchCheckpointProgress(
        _ completion: AgentToolStepCompletion
    ) {
        if completion.call.name == ToolDefinition.webSearch.name ||
            completion.call.name == ToolDefinition.webFetch.name {
            researchPressureWeightBeforeDraft += 1
        } else if completion.call.name == ToolDefinition.subagentsRun.name,
                  completion.result.ok {
            researchPressureWeightBeforeDraft +=
                AgentResearchCheckpointGate.delegatedResearchWeight
        }

        guard completion.result.ok else { return }
        switch completion.call.name {
        case ToolDefinition.webSearch.name, ToolDefinition.webFetch.name:
            if !pendingResearchContinuationWorkspacePaths.isEmpty {
                successfulResearchStepsAfterCheckpoint += 1
            }
            resumedResearchCheckpointWorkspacePaths.formUnion(
                pendingResearchContinuationWorkspacePaths
            )
        case ToolDefinition.subagentsRun.name:
            successfulDelegatedResearchBatchCount += 1
            if !pendingResearchContinuationWorkspacePaths.isEmpty {
                // A delegated batch is the last broad research action after a checkpoint. It may
                // contain several worker tracks and can consume most of the parent's remaining
                // wall-clock budget, so require reconciliation before any further read-only call.
                successfulResearchStepsAfterCheckpoint = max(
                    successfulResearchStepsAfterCheckpoint
                        + AgentResearchCheckpointGate.delegatedResearchWeight,
                    AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
                )
                resumedResearchCheckpointWorkspacePaths.formUnion(
                    pendingResearchContinuationWorkspacePaths
                )
            } else {
                // A delegated batch launched after a deliverable write is a high-density final
                // research step. Require immediate reconciliation before allowing another read-only
                // action; otherwise the parent can serially restart the same research after workers
                // have already returned the evidence needed to finish.
                let writtenDeliverables = namedTextDeliverableWorkspacePaths.filter { path in
                    writtenWorkspacePaths.contains(where: {
                        AgentArtifactVerificationGate.pathsMatch($0, path)
                    })
                }
                if !writtenDeliverables.isEmpty {
                    pendingResearchContinuationWorkspacePaths.formUnion(writtenDeliverables)
                    resumedResearchCheckpointWorkspacePaths.formUnion(writtenDeliverables)
                    successfulResearchStepsAfterCheckpoint = max(
                        successfulResearchStepsAfterCheckpoint,
                        AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
                    )
                }
            }
        case ToolDefinition.fileWrite.name, ToolDefinition.chartRender.name:
            if let path = AgentArtifactVerificationGate.pathArgument(from: completion.call),
               let deliverablePath = namedTextDeliverableWorkspacePaths.first(where: {
                   AgentArtifactVerificationGate.pathsMatch($0, path)
               }) {
                researchPressureWeightBeforeDraft = 0
                if let checkpointPath = expectedResearchCheckpointWorkspacePaths.first(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, deliverablePath)
                }) {
                    expectedResearchCheckpointWorkspacePaths.remove(checkpointPath)
                    pendingResearchContinuationWorkspacePaths.insert(deliverablePath)
                    resumedResearchCheckpointWorkspacePaths.remove(deliverablePath)
                    successfulResearchStepsAfterCheckpoint = 0
                } else if let pendingPath = pendingResearchContinuationWorkspacePaths.first(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, deliverablePath)
                }), resumedResearchCheckpointWorkspacePaths.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, deliverablePath)
                }) {
                    pendingResearchContinuationWorkspacePaths.remove(pendingPath)
                    successfulResearchStepsAfterCheckpoint = 0
                    resumedResearchCheckpointWorkspacePaths = Set(
                        resumedResearchCheckpointWorkspacePaths.filter {
                            !AgentArtifactVerificationGate.pathsMatch($0, deliverablePath)
                        }
                    )
                }
            }
        default:
            break
        }
    }

    private static func isResearchTextArtifact(_ path: String) -> Bool {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "csv", "html", "json", "md", "txt", "tsv", "xml", "yaml", "yml":
            return true
        default:
            return false
        }
    }

    private func isReadOfOwnOutput(_ completion: AgentToolStepCompletion) -> Bool {
        guard let arguments = try? ToolArguments(completion.call.argumentsJSON) else { return false }
        let paths: [String]
        switch completion.call.name {
        case ToolDefinition.fileRead.name:
            guard let path = arguments.string("path") else { return false }
            paths = [path]
        case ToolDefinition.fileReadMany.name:
            guard let batchPaths = arguments.stringArray("paths") else { return false }
            paths = batchPaths
        default:
            return false
        }
        return paths.contains { path in
            let read = AgentArtifactVerificationGate.normalizedPath(path)
            return writtenWorkspacePaths.contains { written in
                AgentArtifactVerificationGate.pathsMatch(written, read)
            }
        }
    }

    /// True the FIRST time a given call repeats: the caller should nudge the model instead of
    /// finalizing. Returns false on any later repeat of the same call, restoring the old
    /// finalize-immediately behavior so the run always terminates.
    mutating func shouldSoftWarnOnRepeat(of call: ToolCall) -> Bool {
        softWarnedCallSignatures.insert("\(call.name)\u{1}\(call.argumentsJSON)").inserted
    }

    mutating func recordDeniedStep(_ completion: AgentToolStepCompletion) {
        toolResults.append(contentsOf: completion.toolResults)
        hadDeniedStep = true
    }

    mutating func recordFlailAssessmentIfNeeded() -> Bool {
        guard !injectedFlailAssessment else { return false }
        injectedFlailAssessment = true
        flailDetector.recordAssessment()
        return true
    }
}
