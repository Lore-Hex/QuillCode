import Foundation
import QuillCodeCore
import QuillCodeReview

extension AppServerSession {
    func reviewDelivery(from params: AppServerParams) throws -> CodeReviewDelivery {
        switch try params.optionalString("delivery") ?? "inline" {
        case "inline": .current
        case "detached": .detached
        default: throw AppServerRPCError.invalidParams("delivery must be inline or detached")
        }
    }

    func codeReviewRequest(
        from params: AppServerParams,
        delivery: CodeReviewDelivery
    ) throws -> WorkspaceCodeReviewRequest {
        guard let target = try params.optionalObject("target") else {
            throw AppServerRPCError.invalidParams("target is required")
        }
        let targetParams = try AppServerParams(.object(target))
        let type = try targetParams.requiredString("type")
        let request: WorkspaceCodeReviewRequest
        switch type {
        case "uncommittedChanges":
            request = WorkspaceCodeReviewRequest(scope: .uncommitted, delivery: delivery)
        case "baseBranch":
            request = WorkspaceCodeReviewRequest(
                scope: .baseBranch,
                reference: try targetParams.requiredString("branch"),
                delivery: delivery
            )
        case "commit":
            request = WorkspaceCodeReviewRequest(
                scope: .commit,
                reference: try targetParams.requiredString("sha"),
                title: try targetParams.optionalString("title"),
                delivery: delivery
            )
        case "custom":
            request = WorkspaceCodeReviewRequest(
                scope: .custom,
                instructions: try customReviewInstructions(from: targetParams),
                delivery: delivery
            )
        default:
            throw AppServerRPCError.invalidParams("unsupported review target type: \(type)")
        }
        if let message = request.validationMessage {
            throw AppServerRPCError.invalidParams(message)
        }
        return request
    }

    private func customReviewInstructions(from params: AppServerParams) throws -> String {
        let instructions = try params.requiredString("instructions")
        guard instructions.utf8.count <= 32 * 1_024 else {
            throw AppServerRPCError.invalidParams(
                "target.instructions exceeds the 32768-byte limit"
            )
        }
        return instructions
    }
}

extension WorkspaceCodeReviewRequest {
    var appServerTranscriptPrompt: String {
        switch scope {
        case .uncommitted:
            "Review the current uncommitted changes."
        case .baseBranch:
            "Review changes against base branch \(reference ?? "")."
        case .commit:
            if let title {
                "Review commit \(reference ?? ""): \(title)"
            } else {
                "Review commit \(reference ?? "")"
            }
        case .custom:
            instructions ?? "Review the current uncommitted changes."
        }
    }

    var reviewModeLabel: String {
        switch scope {
        case .uncommitted: "current changes"
        case .baseBranch: "changes against \(reference ?? "the base branch")"
        case .commit: "commit \(reference ?? "")"
        case .custom: instructions ?? "custom review"
        }
    }
}
