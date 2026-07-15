import Foundation
import QuillCodeReview

struct CLIReviewPromptResolver: Sendable {
    func resolve(
        request: CLIReviewRequest,
        input: any CLIInputReading
    ) throws -> WorkspaceCodeReviewRequest {
        guard case .custom(let rawInstructions)? = request.target,
              rawInstructions == "-"
        else {
            return try request.workspaceRequest()
        }

        let instructions = try CLIStdinTextReader().read(input)
        guard !instructions.isEmpty else { throw CLIError.missingPrompt }
        return try request.workspaceRequest(customInstructions: instructions)
    }
}
