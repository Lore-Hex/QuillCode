import Foundation
import QuillCodeCore

/// Forces a durable draft before a named-artifact research run spends its entire budget reading.
/// The draft is a checkpoint, not a completion signal: ordinary research-refresh and readback
/// gates still require the final artifact to include later evidence and be verified.
enum AgentResearchCheckpointGate {
    struct Correction: Equatable {
        var path: String
        var prompt: String
    }

    static let minimumPreDraftResearchWeight = 8
    static let minimumDirectResearchBeforeDelegation = 3
    static let minimumPostCheckpointResearchSteps = 6
    static let maximumPostDraftResearchWeight = 15
    static let delegatedResearchWeight = 3
    static let correctionLimitPerPath = 2
    static let finalizationCorrectionLimitPerPath = 2

    static func earlyDelegationCorrection(
        path: String?,
        proposedToolName: String,
        proposedCall: ToolCall? = nil,
        canDelegate: Bool,
        canWriteFiles: Bool,
        hasDelegatedResearch: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard proposedCall.map(isParallelizableResearchCollectionCall)
                ?? isParallelizableResearchCollectionTool(proposedToolName),
              canDelegate,
              canWriteFiles,
              !hasDelegatedResearch,
              let path,
              correctionCounts[path, default: 0] < correctionLimitPerPath
        else { return nil }

        return Correction(
            path: path,
            prompt: """
            The serial pre-draft research limit for ./\(path) has been reached. Do not perform \
            another direct search or fetch. Launch host.subagents.run now with two to four precise, \
            independent research workers so named entities or evidence tracks are investigated in \
            parallel. Require each worker to return the requested facts, exact source URLs, and a \
            clear blocked status for any missing evidence; a promise to continue is not a completed \
            worker result. After the batch returns, reconcile every requested entity into ./\(path), \
            then read the artifact back. Respond with host.subagents.run now.
            """
        )
    }

    static func correction(
        path: String?,
        proposedToolName: String? = nil,
        proposedCall: ToolCall? = nil,
        proposedToolRisk: ToolRiskClass?,
        canWriteFiles: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard proposedToolRisk == .read
                || proposedCall.map(isResearchCollectionCall) == true
                || proposedToolName.map(isResearchCollectionTool) == true,
              canWriteFiles,
              let path,
              correctionCounts[path, default: 0] < correctionLimitPerPath
        else { return nil }

        return Correction(
            path: path,
            prompt: """
            Research checkpoint required. Before any additional read, search, fetch, or skill-load \
            action, write the best current draft to ./\(path) now. Include the verified facts and \
            source URLs already gathered, plus an explicit Evidence gaps section for facts still \
            missing. This is a checkpoint, not completion: after writing it, continue the remaining \
            research and rewrite the final artifact with later evidence. Respond with \
            host.file.write for exactly ./\(path); do not perform another read-only action first.
            """
        )
    }

    static func exhaustionCorrection(
        path: String?,
        proposedToolName: String,
        proposedCall: ToolCall? = nil,
        canWriteFiles: Bool,
        userMessage: String,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard proposedCall.map(isResearchCollectionCall)
                ?? isResearchCollectionTool(proposedToolName),
              canWriteFiles,
              let path,
              correctionCounts[path, default: 0] < correctionLimitPerPath
        else { return nil }

        return Correction(
            path: path,
            prompt: """
            The bounded direct-research budget for this deliverable is exhausted. Do not search, \
            fetch, or delegate again. Synthesize the strongest verified evidence already present in \
            the tool results into the complete final artifact at ./\(path) now. Start from the \
            original request, not the current draft's structure; treat that draft as disposable. \
            Audit every requested entity and count, row and column shape, numeric value and date, \
            source URL, and self-contained visual or file-format requirement. Incorporate relevant \
            values and exact URLs from every successful tool result. Do not reference a local asset \
            that has not been written. Preserve exact source URLs, state genuinely unavailable facts \
            honestly, remove pending/draft status language, and then read the rewritten artifact \
            back. Respond with host.file.write for exactly ./\(path).

            Original request requirements:
            \(originalRequestExcerpt(userMessage))
            """
        )
    }

    static func isResearchCollectionTool(_ name: String) -> Bool {
        isDirectResearchCollectionTool(name)
            || name == ToolDefinition.subagentsRun.name
    }

    static func isResearchCollectionCall(_ call: ToolCall) -> Bool {
        isDirectResearchCollectionCall(call)
            || call.name == ToolDefinition.subagentsRun.name
    }

    static func isDirectResearchCollectionCall(_ call: ToolCall) -> Bool {
        isDirectResearchCollectionTool(call.name) || isShellResearchCollectionCall(call)
    }

    static func isDirectResearchCollectionTool(_ name: String) -> Bool {
        [
            ToolDefinition.webSearch.name,
            ToolDefinition.webFetch.name,
            ToolDefinition.browserOpen.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.browserScript.name,
        ].contains(name)
    }

    static func isParallelizableResearchCollectionTool(_ name: String) -> Bool {
        name == ToolDefinition.webSearch.name || name == ToolDefinition.webFetch.name
    }

    static func isParallelizableResearchCollectionCall(_ call: ToolCall) -> Bool {
        isParallelizableResearchCollectionTool(call.name)
    }

    /// Shell is intentionally advertised as a general mutation tool, but agents also use it as a
    /// second browser via curl/wget and then repeatedly parse the downloaded page. Those calls must
    /// consume the same bounded research budget as host.web.fetch or they can bypass every durable
    /// checkpoint and spend the run's finalization reserve re-fetching evidence already in context.
    private static func isShellResearchCollectionCall(_ call: ToolCall) -> Bool {
        guard call.name == ToolDefinition.shellRun.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let command = arguments.string("cmd")?.lowercased()
        else { return false }

        let markers = [
            "curl ",
            "wget ",
            "http://",
            "https://",
            "downloads/",
        ]
        return markers.contains(where: command.contains)
    }

    static func continuationCorrection(
        path: String?,
        didResumeResearch: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard let path,
              correctionCounts[path, default: 0] < correctionLimitPerPath
        else { return nil }

        let nextStep = if didResumeResearch {
            "Use the evidence gathered after the checkpoint to rewrite"
        } else {
            "Resume the missing research with host.web.search and host.web.fetch, then rewrite"
        }
        return Correction(
            path: path,
            prompt: """
            The current artifact at ./\(path) is only the required research checkpoint and cannot \
            complete the task. \(nextStep) ./\(path) as the complete final deliverable, then read \
            that final version back. Do not return a final answer while Evidence gaps, draft, \
            checkpoint, pending, or in-progress status remains. Respond with the next concrete tool \
            action now.
            """
        )
    }

    static func finalizationCorrection(
        path: String?,
        proposedToolName: String? = nil,
        proposedCall: ToolCall? = nil,
        proposedToolRisk: ToolRiskClass?,
        canWriteFiles: Bool,
        userMessage: String,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard proposedToolRisk == .read
                || proposedCall.map(isResearchCollectionCall) == true
                || proposedToolName.map(isResearchCollectionTool) == true,
              canWriteFiles,
              let path,
              correctionCounts[path, default: 0] < finalizationCorrectionLimitPerPath
        else { return nil }

        return Correction(
            path: path,
            prompt: """
            The post-checkpoint research budget is complete. Before another read, search, fetch, \
            skill-load, or delegated-research action, synthesize all evidence gathered so far into \
            the complete final artifact at ./\(path). Start from the original request, not the \
            current draft's structure; treat that draft as disposable. Audit every requested entity \
            and count, row and column shape, numeric value and date, source URL, and self-contained \
            visual or file-format requirement. Incorporate relevant values and exact URLs from every \
            successful tool result, and do not reference a local asset that has not been written. \
            Replace the checkpoint rather than appending another status update. Resolve every \
            evidence gap you can from the current tool results; do not leave TBD, pending, draft, \
            checkpoint, or in-progress markers. Then read the rewritten artifact back before \
            completing. Respond with host.file.write for exactly ./\(path) now.

            Original request requirements:
            \(originalRequestExcerpt(userMessage))
            """
        )
    }

    private static func originalRequestExcerpt(_ userMessage: String) -> String {
        let request = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let maximumCharacters = 12_000
        guard request.count > maximumCharacters else { return request }

        let half = maximumCharacters / 2
        return String(request.prefix(half))
            + "\n[...middle of original request omitted for bounded synthesis context...]\n"
            + String(request.suffix(half))
    }

    static func repeatedDelegationCorrection(path: String) -> Correction {
        Correction(
            path: path,
            prompt: """
            A delegated research batch has already returned and the named deliverable exists at \
            ./\(path). Do not launch another delegated batch. Preserve the completed worker \
            evidence and all later direct research by rewriting ./\(path) as the complete final \
            artifact now. State any genuinely unavailable fact honestly instead of restarting \
            broad research, then read the rewritten artifact back. Respond with host.file.write for \
            exactly ./\(path).
            """
        )
    }
}
