import Foundation
import QuillCodeCore

struct AgentRunLoopState: Sendable {
    private(set) var toolResults: [ToolResult] = []
    private(set) var lastExecutedCall: ToolCall?
    private(set) var lastCompletion: AgentToolStepCompletion?

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

    mutating func recordFlailAssessmentIfNeeded() -> Bool {
        guard !injectedFlailAssessment else { return false }
        injectedFlailAssessment = true
        flailDetector.recordAssessment()
        return true
    }
}
