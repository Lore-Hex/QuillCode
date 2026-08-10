import Foundation
import QuillCodeCore

/// Converts the final portion of a host-bounded run from open-ended research into guaranteed
/// artifact synthesis. Interactive runs do not configure this gate and remain unbounded.
enum AgentBoundedRunFinalizationGate {
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

    static func allows(_ action: AgentAction, deliverablePath: String) -> Bool {
        guard case .tool(let call) = action,
              call.name == ToolDefinition.fileWrite.name,
              let path = AgentArtifactVerificationGate.pathArgument(from: call)
        else { return false }
        return AgentArtifactVerificationGate.pathsMatch(path, deliverablePath)
    }

    static func correctionPrompt(path: String, userMessage: String) -> String {
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
