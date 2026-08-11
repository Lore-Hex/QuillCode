import Foundation
import QuillCodeCore
import QuillCodeTools

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
    /// Recent successful live/delegated research outputs are retained as a bounded, read-only
    /// ledger. Corrective synthesis and validation prompts can surface exact evidence again after
    /// long transcripts have diluted the original tool observations.
    private(set) var latestResearchEvidenceReceipt: String?
    private struct ResearchEvidenceReceipt: Sendable {
        var sourceKey: String
        var toolName: String
        var text: String
        var qualityScore: Int
        var structuredLineCount: Int
    }
    private var researchEvidenceReceipts: [ResearchEvidenceReceipt] = []
    private(set) var writtenWorkspacePaths: Set<String> = []
    /// A successful write remains here until a LATER successful read of the same path. Rewrites
    /// re-arm verification, preventing an early read from blessing a subsequently changed file.
    private(set) var unverifiedWrittenWorkspacePaths: Set<String> = []
    /// Workspace files successfully read this run. Empty-response recovery uses this to advance
    /// only the finite set of source reads the user explicitly requested and has not completed.
    private(set) var successfullyReadWorkspacePaths: Set<String> = []
    /// Explicitly required local inputs remain authoritative in mixed local-plus-live-research
    /// runs. Keeping a bounded host receipt prevents long browsing transcripts and corrective
    /// compaction from replacing exact supplied records with remembered or invented values.
    private var requiredInputWorkspacePaths: Set<String> = []
    private var requiredInputEvidenceReceiptsByKey: [String: String] = [:]
    private(set) var latestRequiredInputEvidenceReceipt: String?
    /// Task-named deliverables that must be read after their latest write. Shell tools can create
    /// rich artifacts that do not appear in ToolResult.artifacts, so successful shell steps use
    /// this bounded set to discover those outputs on disk and arm the normal readback gate.
    private var requiredReadbackWorkspacePaths: Set<String> = []
    /// Task-named artifacts with explicit machine-checkable structure. A successful validator is
    /// invalidated by every later write, unlike ordinary readback which proves only persistence.
    private var requiredContractAuditWorkspacePaths: Set<String> = []
    private(set) var contractAuditedWorkspacePaths: Set<String> = []
    /// A failed deterministic audit permits one targeted read of the audited deliverable before
    /// its repair. This keeps bounded closure finite while letting the model inspect the exact
    /// bytes that failed instead of reconstructing a long artifact from diluted context.
    private var failedContractAuditWorkspacePaths: Set<String> = []
    private var consumedContractAuditRepairReadbackWorkspacePaths: Set<String> = []
    /// A failed audit remains blocked until either the audited deliverable or its validator helper
    /// changes. The stored signature marks an unrepaired failure; the next shell spelling is not
    /// trusted to prove progress because quoting or comments can change without changing behavior.
    private var failedContractAuditCallSignaturesByWorkspacePath:
        [String: ToolCallFingerprint] = [:]
    /// Exact failed validator output survives readback and artifact rewrites until a later audit
    /// passes. Repair prompts can therefore act on named assertion failures even after compaction
    /// or a model rewrite that changes formatting without fixing the underlying values.
    private var failedContractAuditReceiptsByWorkspacePath: [String: String] = [:]
    /// Task-named text deliverables whose latest write predates a successful live-page fetch.
    /// Terminal completion is gated until a later write incorporates or dispositions that evidence;
    /// the ordinary readback gate then verifies the refreshed artifact.
    private(set) var researchStaleWorkspacePaths: Set<String> = []
    private var namedTextDeliverableWorkspacePaths: Set<String> = []
    /// Named text artifacts whose latest saved content explicitly declares itself unfinished. A
    /// narrow patch must not turn an internal checkpoint into a final artifact merely because it
    /// refreshed one source value.
    private(set) var provisionalWrittenTextPaths: Set<String> = []
    private var requestAllowsProvisionalArtifact = false
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
    /// Direct research performed after a named text deliverable exists. The phase counter resets
    /// on every rewrite so long runs periodically synthesize instead of accumulating dozens of
    /// unsaved fetches. The total counter never resets and ultimately closes the direct-research
    /// phase, leaving a bounded reserve for final synthesis and readback.
    private(set) var researchPressureAfterLatestDraftByPath: [String: Int] = [:]
    private(set) var totalResearchPressureAfterFirstDraftByPath: [String: Int] = [:]
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

    var latestAuthoritativeEvidenceReceipt: String? {
        let receipts: [String] = [
            latestRequiredInputEvidenceReceipt,
            latestResearchEvidenceReceipt,
        ].compactMap { receipt -> String? in
            guard let receipt,
                  !receipt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return receipt
        }
        return receipts.isEmpty ? nil : receipts.joined(
            separator: "\n\n--- next authoritative evidence class ---\n\n"
        )
    }

    /// A dense table from an already-successful direct fetch is usually better reconciled by the
    /// parent than fetched again by several workers. This suppresses only forced delegation; the
    /// model can still collect more sources directly and the normal checkpoint remains bounded.
    var hasSubstantialStructuredDirectResearchEvidence: Bool {
        researchEvidenceReceipts.contains { receipt in
            receipt.toolName != ToolDefinition.subagentsRun.name
                && receipt.structuredLineCount >= 5
        }
    }

    var requiredStructuredInputWorkspacePaths: Set<String> {
        Set(requiredInputWorkspacePaths.filter { path in
            Self.structuredInputExtensions.contains(
                URL(fileURLWithPath: path).pathExtension.lowercased()
            )
        })
    }

    func authoritativeEvidenceContradiction(at path: String) -> String? {
        let normalizedPath = AgentArtifactVerificationGate.normalizedPath(path)
        guard let artifact = latestWrittenTextContents.first(where: { storedPath, _ in
            AgentArtifactVerificationGate.pathsMatch(storedPath, normalizedPath)
        })?.value,
        let evidenceReceipt = latestResearchEvidenceReceipt
        else { return nil }
        return AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidenceReceipt
        )
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
        requestAllowsProvisionalArtifact = AgentArtifactFinalityGate
            .requestAllowsProvisionalArtifact(userMessage)
        if AgentArtifactVerificationGate.requiresReadback(in: userMessage) {
            requiredReadbackWorkspacePaths = Set(deliverables)
        }
        if AgentArtifactContractAuditGate.requiresAudit(in: userMessage) {
            requiredContractAuditWorkspacePaths = Set(deliverables)
        }
    }

    func pendingArtifactContractAuditPath() -> String? {
        requiredContractAuditWorkspacePaths.sorted().first { path in
            writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, path)
            }) && !contractAuditedWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, path)
            })
        }
    }

    func needsContractAuditRepairReadback(at path: String) -> Bool {
        failedContractAuditWorkspacePaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, path)
        }) && !consumedContractAuditRepairReadbackWorkspacePaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, path)
        })
    }

    func isUnchangedFailedContractAuditReplay(_ call: ToolCall, at path: String) -> Bool {
        let normalizedPath = AgentArtifactVerificationGate.normalizedPath(path)
        let auditedPaths = AgentArtifactContractAuditGate.auditedPaths(
            for: call,
            among: [normalizedPath]
        )
        guard !auditedPaths.isEmpty else { return false }
        return failedContractAuditCallSignaturesByWorkspacePath.contains { storedPath, _ in
            AgentArtifactVerificationGate.pathsMatch(storedPath, normalizedPath)
        }
    }

    func failedContractAuditReceipt(at path: String) -> String? {
        let normalizedPath = AgentArtifactVerificationGate.normalizedPath(path)
        return failedContractAuditReceiptsByWorkspacePath.first(where: { storedPath, _ in
            AgentArtifactVerificationGate.pathsMatch(storedPath, normalizedPath)
        })?.value
    }

    func requiresContractAuditDeliverableRepair(at path: String) -> Bool {
        let normalizedPath = AgentArtifactVerificationGate.normalizedPath(path)
        guard failedContractAuditWorkspacePaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, normalizedPath)
        }), let receipt = failedContractAuditReceipt(at: normalizedPath) else {
            return false
        }
        return AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(receipt)
    }

    func pendingArtifactReadbackPath() -> String? {
        pendingArtifactReadbackWorkspacePaths.sorted().first
    }

    var pendingArtifactReadbackWorkspacePaths: Set<String> {
        Set(requiredReadbackWorkspacePaths.filter { path in
            unverifiedWrittenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, path)
            })
        })
    }

    func verifiedRequiredArtifactCompletionMessage() -> String? {
        let paths = requiredReadbackWorkspacePaths.sorted()
        guard !paths.isEmpty,
              paths.allSatisfy({ requiredPath in
                  writtenWorkspacePaths.contains(where: {
                      AgentArtifactVerificationGate.pathsMatch($0, requiredPath)
                  }) && !unverifiedWrittenWorkspacePaths.contains(where: {
                      AgentArtifactVerificationGate.pathsMatch($0, requiredPath)
                  })
              })
        else { return nil }

        if paths.count == 1, let path = paths.first {
            return "Completed and verified `\(path)`."
        }
        return "Completed and verified the requested artifacts."
    }

    func isUnrelatedFileWriteAfterRequiredReadback(_ call: ToolCall) -> Bool {
        guard !requiredReadbackWorkspacePaths.isEmpty,
              call.name == ToolDefinition.fileWrite.name,
              let path = AgentArtifactVerificationGate.pathArgument(from: call),
              requiredReadbackWorkspacePaths.allSatisfy({ requiredPath in
                  writtenWorkspacePaths.contains(where: {
                      AgentArtifactVerificationGate.pathsMatch($0, requiredPath)
                  }) && !unverifiedWrittenWorkspacePaths.contains(where: {
                      AgentArtifactVerificationGate.pathsMatch($0, requiredPath)
                  })
              })
        else { return false }

        return !requiredReadbackWorkspacePaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, path)
        })
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
        if successfulResearchStepsAfterCheckpoint >= minimumResearchSteps,
           let checkpointPath = pendingResearchContinuationWorkspacePaths.sorted().first(where: {
               didResumeResearch(afterCheckpointAt: $0)
           }) {
            return checkpointPath
        }
        return researchPressureAfterLatestDraftByPath.keys.sorted().first(where: {
            researchPressureAfterLatestDraftByPath[$0, default: 0] >= minimumResearchSteps
        })
    }

    func exhaustedResearchBudgetPath(maximumResearchWeight: Int) -> String? {
        totalResearchPressureAfterFirstDraftByPath.keys.sorted().first(where: {
            totalResearchPressureAfterFirstDraftByPath[$0, default: 0] >= maximumResearchWeight
        })
    }

    func writtenNamedTextDeliverablePath() -> String? {
        namedTextDeliverableWorkspacePaths.sorted().first { path in
            writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, path)
            })
        }
    }

    func pendingBoundedRunFinalizationPath() -> String? {
        namedTextDeliverableWorkspacePaths.sorted().first(where: {
            needsBoundedRunFinalization(at: $0)
        })
    }

    func boundedRunFinalizationTargetPath() -> String? {
        pendingBoundedRunFinalizationPath()
            ?? pendingArtifactContractAuditPath()
            ?? pendingArtifactReadbackPath()
            ?? writtenNamedTextDeliverablePath()
            ?? namedTextDeliverableWorkspacePaths.sorted().first
    }

    func boundedRunFinalizationPhase(
        at path: String
    ) -> AgentBoundedRunFinalizationGate.Phase {
        if needsBoundedRunFinalization(at: path) {
            return .synthesize
        }
        if pendingArtifactContractAuditPath().map({
            AgentArtifactVerificationGate.pathsMatch($0, path)
        }) == true {
            return .audit
        }
        if pendingArtifactReadbackPath().map({
            AgentArtifactVerificationGate.pathsMatch($0, path)
        }) == true {
            return .readback
        }
        return .complete
    }

    func needsBoundedRunFinalization(at path: String) -> Bool {
        let wasWritten = writtenWorkspacePaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, path)
        })
        let isStale = researchStaleWorkspacePaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, path)
        })
        let isProvisional = provisionalWrittenTextPaths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, path)
        })
        return !wasWritten || isStale || isProvisional
    }

    /// Once research lands after a draft, the next model turn is grounded synthesis rather than
    /// tight post-write verification. The wider synthesis budget remains active only until the
    /// artifact is rewritten, which resets the per-draft research pressure.
    func requiresGroundedSynthesisReasoningBudget() -> Bool {
        researchPressureAfterLatestDraftByPath.values.contains(where: { $0 > 0 })
    }

    mutating func requireResearchRefresh(at path: String) {
        researchStaleWorkspacePaths.insert(AgentArtifactVerificationGate.normalizedPath(path))
    }

    private mutating func recordArtifactVerification(
        _ completion: AgentToolStepCompletion,
        workspaceRoot: URL
    ) {
        if completion.call.name == ToolDefinition.shellRun.name {
            // A compound shell step can create the named deliverable and then exit nonzero when
            // its validator fails. Discover the durable file before handling the exit status so
            // repair readback and overwrite safety agree about the artifact's existence.
            recordExistingShellAuthoredArtifacts(workspaceRoot: workspaceRoot)
            let auditedPaths = AgentArtifactContractAuditGate.auditedPaths(
                for: completion.call,
                among: requiredContractAuditWorkspacePaths
            )
            if completion.result.ok {
                let contradicted = Set(auditedPaths.filter { path in
                    guard let content = currentArtifactText(
                        at: path,
                        workspaceRoot: workspaceRoot
                    ), let evidenceReceipt = latestResearchEvidenceReceipt else {
                        return false
                    }
                    return AgentArtifactContractAuditGate.evidenceContradiction(
                        artifact: content,
                        evidenceReceipt: evidenceReceipt
                    ) != nil
                })
                let accepted = auditedPaths.subtracting(contradicted)
                contractAuditedWorkspacePaths.formUnion(accepted)
                failedContractAuditWorkspacePaths.subtract(accepted)
                consumedContractAuditRepairReadbackWorkspacePaths.subtract(accepted)
                removeFailedContractAuditCallSignatures(for: accepted)
                removeFailedContractAuditReceipts(for: accepted)

                if !contradicted.isEmpty {
                    contractAuditedWorkspacePaths.subtract(contradicted)
                    failedContractAuditWorkspacePaths.formUnion(contradicted)
                    consumedContractAuditRepairReadbackWorkspacePaths.subtract(contradicted)
                    let signature = ToolCallFingerprint.make(
                        name: completion.call.name,
                        argumentsJSON: completion.call.argumentsJSON
                    )
                    for path in contradicted {
                        failedContractAuditCallSignaturesByWorkspacePath[path] = signature
                        let content = currentArtifactText(at: path, workspaceRoot: workspaceRoot) ?? ""
                        let issue = AgentArtifactContractAuditGate.evidenceContradiction(
                            artifact: content,
                            evidenceReceipt: latestResearchEvidenceReceipt ?? ""
                        ) ?? "artifact conflicts with retained research evidence"
                        failedContractAuditReceiptsByWorkspacePath[path] =
                            "VALIDATION REJECTED: \(issue)"
                    }
                }
            } else {
                failedContractAuditWorkspacePaths.formUnion(auditedPaths)
                consumedContractAuditRepairReadbackWorkspacePaths.subtract(auditedPaths)
                let signature = ToolCallFingerprint.make(
                    name: completion.call.name,
                    argumentsJSON: completion.call.argumentsJSON
                )
                for path in auditedPaths {
                    failedContractAuditCallSignaturesByWorkspacePath[path] = signature
                    let validatorReceipt = Self.failedContractAuditReceipt(from: completion.result)
                    if let content = currentArtifactText(at: path, workspaceRoot: workspaceRoot),
                       let evidenceReceipt = latestResearchEvidenceReceipt,
                       let issue = AgentArtifactContractAuditGate.evidenceContradiction(
                           artifact: content,
                           evidenceReceipt: evidenceReceipt
                       ) {
                        failedContractAuditReceiptsByWorkspacePath[path] = """
                        VALIDATION REJECTED: \(issue)

                        Validator execution also failed:
                        \(validatorReceipt)
                        """
                    } else {
                        failedContractAuditReceiptsByWorkspacePath[path] = validatorReceipt
                    }
                }
                return
            }
            return
        }
        guard completion.result.ok else { return }
        if completion.call.name == ToolDefinition.fileReadMany.name,
           let arguments = try? ToolArguments(completion.call.argumentsJSON),
           let paths = arguments.stringArray("paths") {
            recordSuccessfulFileReads(paths: paths, output: completion.result.stdout)
            return
        }
        if completion.call.name == ToolDefinition.applyPatch.name,
           let arguments = try? ToolArguments(completion.call.argumentsJSON),
           let patch = arguments.string("patch") {
            for path in PatchToolExecutor.targetPaths(in: patch) {
                let normalized = AgentArtifactVerificationGate.normalizedPath(path)
                let url = workspaceRoot.appendingPathComponent(normalized)
                guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                    invalidateContractAudit(for: normalized)
                    unverifiedWrittenWorkspacePaths.insert(normalized)
                    markResearchArtifactRefreshed(normalized)
                    continue
                }
                let syntheticCall = ToolCall(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": normalized,
                        "content": content,
                    ])
                )
                recordArtifactVerification(
                    AgentToolStepCompletion(
                        call: syntheticCall,
                        result: completion.result,
                        followUpReviewResult: nil,
                        toolResults: []
                    ),
                    workspaceRoot: workspaceRoot
                )
            }
            return
        }
        guard let path = AgentArtifactVerificationGate.pathArgument(from: completion.call) else {
            return
        }
        let normalized = AgentArtifactVerificationGate.normalizedPath(path)
        switch completion.call.name {
        case ToolDefinition.chartRender.name:
            invalidateContractAudit(for: normalized)
            writtenWorkspacePaths.insert(normalized)
            unverifiedWrittenWorkspacePaths.insert(normalized)
            markResearchArtifactRefreshed(normalized)
        case ToolDefinition.fileWrite.name:
            let content = (try? ToolArguments(completion.call.argumentsJSON))?.string("content")
            let previousContent = latestWrittenTextContents[normalized]
            let preservesFailedReplay = previousContent.map { previous in
                content.map { Self.auditSemanticFingerprint($0) }
                    == Self.auditSemanticFingerprint(previous)
            } ?? false
            invalidateContractAudit(
                for: normalized,
                preservingFailedReplay: preservesFailedReplay
            )
            unverifiedWrittenWorkspacePaths.insert(normalized)
            markResearchArtifactRefreshed(normalized)
            if let content {
                if previousContent != content {
                    let repairedAuditPaths = requiredContractAuditWorkspacePaths.filter { path in
                        AgentBoundedRunFinalizationGate.validatorHelperExecutionCall(
                            after: completion.call,
                            deliverablePath: path
                        ) != nil
                    }
                    removeFailedContractAuditCallSignatures(for: repairedAuditPaths)
                }
                latestWrittenTextContents[normalized] = content
                recordArtifactFinality(content: content, path: normalized)
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

    private func currentArtifactText(at path: String, workspaceRoot: URL) -> String? {
        let normalized = AgentArtifactVerificationGate.normalizedPath(path)
        if let content = latestWrittenTextContents.first(where: { storedPath, _ in
            AgentArtifactVerificationGate.pathsMatch(storedPath, normalized)
        })?.value {
            return content
        }
        let url = workspaceRoot.appendingPathComponent(normalized)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private mutating func recordExistingShellAuthoredArtifacts(workspaceRoot: URL) {
        let discoverablePaths = requiredReadbackWorkspacePaths
            .union(requiredContractAuditWorkspacePaths)
        for path in discoverablePaths where
            !writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, path)
            }) &&
            AgentArtifactVerificationGate.isExistingWorkspaceFile(
                path,
                workspaceRoot: workspaceRoot
            ) {
            writtenWorkspacePaths.insert(path)
            unverifiedWrittenWorkspacePaths.insert(path)
            if let content = try? String(
                contentsOf: workspaceRoot.appendingPathComponent(path),
                encoding: .utf8
            ) {
                latestWrittenTextContents[path] = content
                recordArtifactFinality(content: content, path: path)
            }
        }
    }

    private mutating func recordArtifactFinality(content: String, path: String) {
        guard !requestAllowsProvisionalArtifact,
              namedTextDeliverableWorkspacePaths.contains(where: {
                  AgentArtifactVerificationGate.pathsMatch($0, path)
              }),
              AgentArtifactFinalityGate.containsProvisionalCompletionLanguage(
                content: content,
                path: path
              )
        else {
            provisionalWrittenTextPaths = Set(provisionalWrittenTextPaths.filter {
                !AgentArtifactVerificationGate.pathsMatch($0, path)
            })
            return
        }
        provisionalWrittenTextPaths.insert(path)
    }

    private mutating func invalidateContractAudit(
        for writtenPath: String,
        preservingFailedReplay: Bool = false
    ) {
        contractAuditedWorkspacePaths = Set(contractAuditedWorkspacePaths.filter {
            !AgentArtifactVerificationGate.pathsMatch($0, writtenPath)
        })
        if !preservingFailedReplay {
            failedContractAuditWorkspacePaths = Set(failedContractAuditWorkspacePaths.filter {
                !AgentArtifactVerificationGate.pathsMatch($0, writtenPath)
            })
            consumedContractAuditRepairReadbackWorkspacePaths = Set(
                consumedContractAuditRepairReadbackWorkspacePaths.filter {
                    !AgentArtifactVerificationGate.pathsMatch($0, writtenPath)
                }
            )
            removeFailedContractAuditCallSignatures(for: [writtenPath])
        }
    }

    private mutating func removeFailedContractAuditCallSignatures<S: Sequence>(
        for paths: S
    ) where S.Element == String {
        let paths = Array(paths)
        failedContractAuditCallSignaturesByWorkspacePath =
            failedContractAuditCallSignaturesByWorkspacePath.filter { storedPath, _ in
                !paths.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, storedPath)
                })
            }
    }

    private mutating func removeFailedContractAuditReceipts<S: Sequence>(
        for paths: S
    ) where S.Element == String {
        let paths = Array(paths)
        failedContractAuditReceiptsByWorkspacePath =
            failedContractAuditReceiptsByWorkspacePath.filter { storedPath, _ in
                !paths.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, storedPath)
                })
            }
    }

    private static func failedContractAuditReceipt(from result: ToolResult) -> String {
        var sections: [String] = []
        if let exitCode = result.exitCode {
            sections.append("exit code: \(exitCode)")
        }
        if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("stdout:\n\(result.stdout)")
        }
        if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("stderr:\n\(result.stderr)")
        }
        if let error = result.error,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("error:\n\(error)")
        }
        let receipt = sections.isEmpty ? "validator failed without diagnostic output" :
            sections.joined(separator: "\n")
        let maximumCharacters = 8_000
        guard receipt.count > maximumCharacters else { return receipt }
        let half = maximumCharacters / 2
        return String(receipt.prefix(half))
            + "\n[failed validator output truncated]\n"
            + String(receipt.suffix(half))
    }

    private static func auditSemanticFingerprint(_ content: String) -> String {
        var normalized = content.precomposedStringWithCompatibilityMapping.lowercased()
        let punctuationReplacements = [
            "\u{2013}": "-", "\u{2014}": "-", "\u{2212}": "-", "\u{00D7}": "x",
            "\u{2018}": "'", "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\"",
        ]
        for (source, replacement) in punctuationReplacements {
            normalized = normalized.replacingOccurrences(of: source, with: replacement)
        }
        normalized = normalized.replacingOccurrences(of: "*", with: "")
        return normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private mutating func recordSuccessfulFileReads(paths: [String], output: String) {
        let normalizedPaths = paths.map(AgentArtifactVerificationGate.normalizedPath)
        for normalized in normalizedPaths {
            successfullyReadWorkspacePaths.insert(normalized)
            unverifiedWrittenWorkspacePaths = Set(unverifiedWrittenWorkspacePaths.filter {
                !AgentArtifactVerificationGate.pathsMatch($0, normalized)
            })
            if failedContractAuditWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, normalized)
            }) {
                consumedContractAuditRepairReadbackWorkspacePaths.insert(normalized)
            }
        }
        let sourcePaths = normalizedPaths.filter { normalized in
            !writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, normalized)
            })
        }
        let requiredPaths = sourcePaths.filter { normalized in
            requiredInputWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, normalized)
            })
        }
        if !requiredPaths.isEmpty {
            recordRequiredInputEvidence(paths: requiredPaths, output: output)
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
        requiredInputWorkspacePaths = Set(
            AgentExplicitSourceReadRecovery.requiredInputPaths(in: userMessage)
        )
        requiredInputEvidenceReceiptsByKey = [:]
        latestRequiredInputEvidenceReceipt = nil
    }

    private mutating func recordRequiredInputEvidence(paths: [String], output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = paths.sorted().joined(separator: " | ")
        requiredInputEvidenceReceiptsByKey[key] = """
        Successful required local input read (\(key)):
        \(Self.boundedRequiredInputEvidence(trimmed))
        """

        var retained: [String] = []
        var retainedCharacters = 0
        for receipt in requiredInputEvidenceReceiptsByKey.sorted(by: { $0.key < $1.key }).map(\.value) {
            guard retainedCharacters + receipt.count <= Self.maximumRequiredInputEvidenceCharacters
            else { continue }
            retained.append(receipt)
            retainedCharacters += receipt.count
        }
        latestRequiredInputEvidenceReceipt = """
        Host-retained required local input evidence. These are exact successful file-read results, \
        not model recollections. Treat their rows and values as authoritative over draft text, \
        delegated summaries, and hard-coded validator expectations.

        \(retained.joined(separator: "\n\n"))
        """
    }

    private mutating func recordCitationProvenance(_ completion: AgentToolStepCompletion) {
        guard completion.result.ok else { return }
        let name = completion.call.name
        // Workspace producers register both requested paths and executor-reported absolute artifacts.
        if name == ToolDefinition.fileWrite.name || name == ToolDefinition.chartRender.name
            || name == ToolDefinition.applyPatch.name {
            if let data = completion.call.argumentsJSON.data(using: .utf8),
               let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let path = arguments["path"] as? String {
                writtenWorkspacePaths.insert(path)
            }
            if name == ToolDefinition.applyPatch.name,
               let arguments = try? ToolArguments(completion.call.argumentsJSON),
               let patch = arguments.string("patch") {
                writtenWorkspacePaths.formUnion(PatchToolExecutor.targetPaths(in: patch))
            }
            for artifact in completion.result.artifacts {
                writtenWorkspacePaths.insert(artifact)
            }
        }
        let isResearchObservation = AgentResearchCheckpointGate.isDirectResearchCollectionCall(
            completion.call
        )
            || name == ToolDefinition.subagentsRun.name
        if isResearchObservation {
            let containsSemanticFailure = Self.containsSemanticResearchFailure(
                call: completion.call,
                output: completion.result.stdout
            )
            // Delegated results are new research observations just like fetched pages. If they
            // arrive after an artifact write, that artifact must be reconciled before completion.
            // This is especially important when one worker returns usable evidence alongside a
            // partial/failed worker: the parent should preserve what it learned, not silently bless
            // the pre-delegation draft.
            if AgentResearchCheckpointGate.isDirectResearchCollectionCall(completion.call),
               name != ToolDefinition.webSearch.name,
               !containsSemanticFailure {
                didFetchSuccessfully = true
            }
            if name != ToolDefinition.webSearch.name,
               !containsSemanticFailure,
               let receipt = Self.researchEvidenceReceipt(
                call: completion.call,
                output: completion.result.stdout
            ) {
                if let existingIndex = researchEvidenceReceipts.firstIndex(where: {
                    $0.sourceKey == receipt.sourceKey
                }) {
                    if receipt.qualityScore >= researchEvidenceReceipts[existingIndex].qualityScore {
                        researchEvidenceReceipts.remove(at: existingIndex)
                        researchEvidenceReceipts.append(receipt)
                    }
                } else {
                    researchEvidenceReceipts.append(receipt)
                }
                if researchEvidenceReceipts.count > Self.maximumResearchEvidenceReceiptCount {
                    let removalCount = researchEvidenceReceipts.count
                        - Self.maximumResearchEvidenceReceiptCount
                    for _ in 0..<removalCount {
                        guard let weakestIndex = researchEvidenceReceipts.indices.min(by: {
                            Self.researchEvidenceRetentionScore(researchEvidenceReceipts[$0])
                                < Self.researchEvidenceRetentionScore(
                                    researchEvidenceReceipts[$1]
                                )
                        }) else { break }
                        researchEvidenceReceipts.remove(at: weakestIndex)
                    }
                }
                let prioritized = researchEvidenceReceipts.enumerated().sorted { left, right in
                    let leftDirect = left.element.toolName != ToolDefinition.subagentsRun.name
                    let rightDirect = right.element.toolName != ToolDefinition.subagentsRun.name
                    if leftDirect != rightDirect { return leftDirect }
                    return left.offset < right.offset
                }.map(\.element.text)
                latestResearchEvidenceReceipt = prioritized.joined(
                    separator: "\n\n--- next successful research observation ---\n\n"
                )
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

    private static func researchEvidenceReceipt(
        call: ToolCall,
        output: String
    ) -> ResearchEvidenceReceipt? {
        let toolName = call.name
        let receiptOutput: String
        var observedURL: String?
        if toolName == ToolDefinition.subagentsRun.name,
           let data = output.data(using: .utf8),
           let run = try? JSONDecoder().decode(RetainedSubagentRunOutput.self, from: data) {
            let workers = run.workers.map { worker in
                let summary = worker.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Worker \(worker.name) [\(worker.status)]:\n\(summary ?? "No result returned.")"
            }
            receiptOutput = (["Delegation summary:\n\(run.summary)"] + workers)
                .joined(separator: "\n\n")
        } else if toolName == ToolDefinition.browserScript.name,
           let data = output.data(using: .utf8),
           let script = try? JSONDecoder().decode(BrowserScriptToolOutput.self, from: data) {
            let value = script.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            receiptOutput = "Page: \(script.title)\nURL: \(script.url)\nExtracted value:\n\(value)"
            observedURL = script.url
        } else {
            receiptOutput = output
        }
        let trimmed = receiptOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let maximumCharacters = 12_000
        let bounded: String
        if trimmed.count <= maximumCharacters {
            bounded = trimmed
        } else {
            let half = maximumCharacters / 2
            bounded = String(trimmed.prefix(half))
                + "\n[...middle of evidence receipt omitted...]\n"
                + String(trimmed.suffix(half))
        }
        if observedURL == nil,
           let arguments = try? ToolArguments(call.argumentsJSON) {
            observedURL = arguments.string("url")
        }
        if observedURL == nil {
            observedURL = AgentCitationIntegrityGate.allURLs(in: receiptOutput).first
        }
        let isDelegated = toolName == ToolDefinition.subagentsRun.name
        let callFingerprint = ToolCallFingerprint.make(
            name: toolName,
            argumentsJSON: call.argumentsJSON
        ).value
        let sourceKey = if !isDelegated, let observedURL {
            "direct:\(AgentCitationIntegrityGate.normalize(observedURL))"
        } else {
            (isDelegated ? "delegated:" : "direct:") + callFingerprint
        }
        let structuredLineCount = trimmed.split(separator: "\n").filter { line in
            line.contains("|") || line.contains("\t")
        }.count
        return ResearchEvidenceReceipt(
            sourceKey: sourceKey,
            toolName: toolName,
            text: "Successful \(toolName) observation:\n\(bounded)",
            qualityScore: trimmed.count + min(structuredLineCount, 100) * 250,
            structuredLineCount: structuredLineCount
        )
    }

    private static let maximumResearchEvidenceReceiptCount = 3
    private static let maximumRequiredInputEvidenceCharacters = 16_000
    private static let structuredInputExtensions: Set<String> = [
        "csv", "json", "jsonl", "tsv", "xls", "xlsx",
    ]

    private struct RetainedSubagentRunOutput: Decodable {
        struct Worker: Decodable {
            var name: String
            var status: String
            var summary: String?
        }

        var summary: String
        var workers: [Worker]
    }

    private static func boundedRequiredInputEvidence(_ text: String) -> String {
        let maximumCharacters = 12_000
        guard text.count > maximumCharacters else { return text }
        let headCount = maximumCharacters * 2 / 3
        let tailCount = maximumCharacters - headCount
        return String(text.prefix(headCount))
            + "\n[...middle of required local input omitted from retained evidence...]\n"
            + String(text.suffix(tailCount))
    }

    private static func researchEvidenceRetentionScore(
        _ receipt: ResearchEvidenceReceipt
    ) -> Int {
        let directEvidenceBonus = receipt.toolName == ToolDefinition.subagentsRun.name
            ? 0
            : 1_000_000
        return directEvidenceBonus + receipt.qualityScore
    }

    private static func containsSemanticResearchFailure(
        call: ToolCall,
        output: String
    ) -> Bool {
        if WebFetchSemanticFailure.description(in: output) != nil {
            return true
        }
        guard call.name == ToolDefinition.shellRun.name else { return false }
        let patterns = [
            #"(?is)<title>\s*HTTP\s+Status\s+[45]\d\d\b"#,
            #"(?is)<h1>\s*HTTP\s+Status\s+[45]\d\d\b"#,
            #"(?is)<title>\s*(?:Access\s+Denied|Forbidden|Unauthorized)\s*</title>"#,
            #"(?is)<h[12]>\s*(?:Access\s+Denied|Forbidden|Unauthorized)\s*</h[12]>"#,
        ]
        let range = NSRange(output.startIndex..., in: output)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: output, range: range) != nil
        }
    }

    private mutating func recordResearchCheckpointProgress(
        _ completion: AgentToolStepCompletion
    ) {
        let researchWeight: Int
        if AgentResearchCheckpointGate.isDirectResearchCollectionCall(completion.call) {
            // Failed requests consume the same wall-clock/context reserve and establish an evidence
            // gap the deliverable should disposition, so direct attempts count regardless of result.
            researchWeight = 1
        } else if completion.call.name == ToolDefinition.subagentsRun.name,
                  completion.result.ok {
            researchWeight = AgentResearchCheckpointGate.delegatedResearchWeight
        } else {
            researchWeight = 0
        }
        researchPressureWeightBeforeDraft += researchWeight
        if researchWeight > 0 {
            for path in namedTextDeliverableWorkspacePaths where
                writtenWorkspacePaths.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, path)
                }) {
                researchPressureAfterLatestDraftByPath[path, default: 0] += researchWeight
                totalResearchPressureAfterFirstDraftByPath[path, default: 0] += researchWeight
            }
        }

        guard completion.result.ok else { return }
        if AgentResearchCheckpointGate.isDirectResearchCollectionCall(completion.call) {
            if !pendingResearchContinuationWorkspacePaths.isEmpty {
                successfulResearchStepsAfterCheckpoint += 1
            }
            resumedResearchCheckpointWorkspacePaths.formUnion(
                pendingResearchContinuationWorkspacePaths
            )
        } else if completion.call.name == ToolDefinition.subagentsRun.name {
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
        } else if completion.call.name == ToolDefinition.fileWrite.name
                    || completion.call.name == ToolDefinition.chartRender.name {
            if let path = AgentArtifactVerificationGate.pathArgument(from: completion.call),
               let deliverablePath = namedTextDeliverableWorkspacePaths.first(where: {
                   AgentArtifactVerificationGate.pathsMatch($0, path)
               }) {
                researchPressureWeightBeforeDraft = 0
                researchPressureAfterLatestDraftByPath[deliverablePath] = 0
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

    mutating func resetFlailDetectorAfterRecovery() {
        flailDetector = FlailDetector()
    }
}
