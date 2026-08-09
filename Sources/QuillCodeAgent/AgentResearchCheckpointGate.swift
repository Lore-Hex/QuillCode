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

    static let minimumWebSteps = 8
    static let correctionLimitPerPath = 2

    static func correction(
        path: String?,
        proposedToolRisk: ToolRiskClass?,
        canWriteFiles: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard proposedToolRisk == .read,
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
}
