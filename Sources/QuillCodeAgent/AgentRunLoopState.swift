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
        guard AgentArtifactVerificationGate.requiresReadback(in: userMessage) else { return }
        requiredReadbackWorkspacePaths = Set(
            AgentDeliverableGate.requiredDeliverables(in: userMessage).map(
                AgentArtifactVerificationGate.normalizedPath
            )
        )
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
        guard let path = AgentArtifactVerificationGate.pathArgument(from: completion.call) else {
            return
        }
        let normalized = AgentArtifactVerificationGate.normalizedPath(path)
        switch completion.call.name {
        case ToolDefinition.chartRender.name:
            writtenWorkspacePaths.insert(normalized)
            unverifiedWrittenWorkspacePaths.insert(normalized)
        case ToolDefinition.fileWrite.name:
            unverifiedWrittenWorkspacePaths.insert(normalized)
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
            successfullyReadWorkspacePaths.insert(normalized)
            unverifiedWrittenWorkspacePaths = Set(unverifiedWrittenWorkspacePaths.filter {
                !AgentArtifactVerificationGate.pathsMatch($0, normalized)
            })
            if enforcesSourceOnlyGrounding,
               !writtenWorkspacePaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, normalized)
               }) {
                sourceGroundingText += "\n" + completion.result.stdout
                sourceReadsByPath[normalized] = completion.result.stdout
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
        default:
            break
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
        if name == "host.web.fetch" {
            didFetchSuccessfully = true
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

    private func isReadOfOwnOutput(_ completion: AgentToolStepCompletion) -> Bool {
        guard completion.call.name == "host.file.read",
              let data = completion.call.argumentsJSON.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = arguments["path"] as? String
        else { return false }
        let read = AgentArtifactVerificationGate.normalizedPath(path)
        return writtenWorkspacePaths.contains { written in
            AgentArtifactVerificationGate.pathsMatch(written, read)
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
