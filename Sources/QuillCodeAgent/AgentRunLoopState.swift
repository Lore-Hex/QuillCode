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

    private mutating func recordCitationProvenance(_ completion: AgentToolStepCompletion) {
        guard completion.result.ok else { return }
        let name = completion.call.name
        // Scope: only host.file.write registers written paths (args.path + the executor's
        // absolute artifact path). apply_patch reports no artifacts; a patch-authored deliverable
        // is simply not scanned — under-enforcement, never a false positive on user files.
        if name == "host.file.write" {
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
        for url in AgentCitationIntegrityGate.allURLs(in: completion.result.stdout) {
            groundedURLs.insert(AgentCitationIntegrityGate.normalize(url))
        }
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
