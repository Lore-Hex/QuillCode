import Foundation
import QuillCodeCore
import QuillCodeTools

/// Redirects Codex-envelope patches before they become failed tool cards. `host.apply_patch`
/// deliberately accepts raw git unified diffs so successful edits remain exactly reversible.
enum AgentInvalidPatchProposalPreflight {
    struct Correction: Equatable {
        var summary: String
        var prompt: String
    }

    static func correction(for call: ToolCall) -> Correction? {
        guard call.name == ToolDefinition.applyPatch.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let patch = arguments.string("patch")?.trimmingCharacters(in: .whitespacesAndNewlines),
              patch.hasPrefix("*** Begin Patch"),
              patch.contains("*** End Patch")
        else { return nil }

        if isSemanticNoOp(patch) {
            return Correction(
                summary: "Self-healing: discarded a patch that would not change any bytes.",
                prompt: """
                That patch removes and adds identical content, so it would make no change. Skip the \
                patch. If the requested work is complete, return the concise final answer now; \
                otherwise continue with the next necessary step. Do not retry this no-op.
                """
            )
        }

        return Correction(
            summary: "Self-healing: requested the supported raw unified-diff format.",
            prompt: """
            host.apply_patch accepts a raw git unified diff, not a `*** Begin Patch` envelope. \
            Regenerate the edit beginning with `diff --git` and include `---`, `+++`, and numbered \
            `@@ -old +new @@` headers, or use host.file.write after reading the current file. \
            Submit only the raw diff in the patch argument.
            """
        )
    }

    private static func isSemanticNoOp(_ patch: String) -> Bool {
        var removed: [String] = []
        var added: [String] = []
        for line in patch.components(separatedBy: .newlines) {
            if line.hasPrefix("-") && !line.hasPrefix("***") {
                removed.append(String(line.dropFirst()))
            } else if line.hasPrefix("+") && !line.hasPrefix("***") {
                added.append(String(line.dropFirst()))
            }
        }
        return !removed.isEmpty && removed == added
    }
}
