import Foundation
import QuillCodeCore

/// Converts the final portion of a host-bounded run from open-ended research into guaranteed
/// artifact synthesis. Interactive runs do not configure this gate and remain unbounded.
enum AgentBoundedRunFinalizationGate {
    enum Phase: Equatable {
        case synthesize
        case audit
        case readback
        case complete
    }

    static func shouldEnter(
        elapsedSeconds: TimeInterval,
        finalizationAfterSeconds: TimeInterval?
    ) -> Bool {
        guard let finalizationAfterSeconds,
              finalizationAfterSeconds.isFinite,
              finalizationAfterSeconds >= 0
        else { return false }
        return elapsedSeconds >= finalizationAfterSeconds
    }

    static func allows(
        _ action: AgentAction,
        deliverablePath: String,
        phase: Phase
    ) -> Bool {
        if case .say = action {
            return phase == .complete
        }
        guard case .tool(let call) = action else { return false }

        if call.name == ToolDefinition.fileWrite.name,
           let path = AgentArtifactVerificationGate.pathArgument(from: call),
           AgentArtifactVerificationGate.pathsMatch(path, deliverablePath) {
            return true
        }

        switch phase {
        case .synthesize, .complete:
            return false
        case .readback:
            return isReadback(call, deliverablePath: deliverablePath)
        case .audit:
            return isValidatorHelperWrite(call, deliverablePath: deliverablePath)
                || AgentArtifactContractAuditGate.auditedPaths(
                    for: call,
                    among: [AgentArtifactVerificationGate.normalizedPath(deliverablePath)]
                ).isEmpty == false
        }
    }

    static func correctionPrompt(
        path: String,
        userMessage: String,
        phase: Phase = .synthesize
    ) -> String {
        switch phase {
        case .synthesize:
            synthesisPrompt(path: path, userMessage: userMessage)
        case .audit:
            """
            The bounded run is in its reserved validation window. Stop researching, browsing, and \
            delegating. Run one deterministic validator with host.shell.run against ./\(path) now, \
            with real assertions for the original request's machine-checkable requirements. The \
            command must include ./\(path), print a concise PASS summary, and exit nonzero with \
            named failures. If the validator needs a multiline script, write one validator helper \
            first and then execute it against ./\(path). If validation fails, rewrite only the \
            complete named deliverable and validate it again.
            """
        case .readback:
            """
            The bounded run is in its reserved verification window. Stop all research and helper \
            work. Read the latest saved ./\(path) back now with host.file.read so the final artifact \
            is verified after its latest write and validation.
            """
        case .complete:
            """
            The bounded run's requested deliverable, deterministic audit, and readback are complete. \
            Do not call another tool. Return a concise terminal answer that accurately states that \
            ./\(path) was completed and verified.
            """
        }
    }

    private static func synthesisPrompt(path: String, userMessage: String) -> String {
        """
        The bounded run has entered its reserved finalization window. Stop researching, browsing, \
        delegating, parsing, and creating helper files. Synthesize the strongest verified evidence \
        already present in the tool results into the complete requested deliverable at ./\(path) now. \
        Start from the original request, state genuinely unavailable facts honestly, and do not invent \
        missing evidence. Respond with host.file.write for exactly ./\(path); no other action is \
        permitted until that deliverable exists. The normal artifact readback and validation steps will \
        run after the write.

        Original request requirements:
        \(originalRequestExcerpt(userMessage))
        """
    }

    private static func isReadback(_ call: ToolCall, deliverablePath: String) -> Bool {
        if call.name == ToolDefinition.fileRead.name,
           let path = AgentArtifactVerificationGate.pathArgument(from: call) {
            return AgentArtifactVerificationGate.pathsMatch(path, deliverablePath)
        }
        guard call.name == ToolDefinition.fileReadMany.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let paths = arguments.stringArray("paths")
        else { return false }
        return paths.contains(where: {
            AgentArtifactVerificationGate.pathsMatch($0, deliverablePath)
        })
    }

    private static func isValidatorHelperWrite(
        _ call: ToolCall,
        deliverablePath: String
    ) -> Bool {
        guard call.name == ToolDefinition.fileWrite.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let path = arguments.string("path"),
              let content = arguments.string("content"),
              ["py", "js", "mjs", "cjs", "rb", "pl"].contains(
                URL(fileURLWithPath: path).pathExtension.lowercased()
              )
        else { return false }

        let normalizedContent = content.replacingOccurrences(of: "\\", with: "/").lowercased()
        let normalizedDeliverable = AgentArtifactVerificationGate
            .normalizedPath(deliverablePath)
            .lowercased()
        let namesTarget = normalizedContent.contains(normalizedDeliverable)
            || normalizedContent.contains(URL(fileURLWithPath: normalizedDeliverable).lastPathComponent)
        let hasValidation = ["assert", "validate", "verify", "raise", "systemexit", "exit("].contains {
            normalizedContent.contains($0)
        }
        return namesTarget && hasValidation
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
}
