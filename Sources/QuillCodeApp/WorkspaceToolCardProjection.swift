import Foundation
import QuillCodeCore

enum WorkspaceToolCardProjection {
    static func queuedCard(for event: ThreadEvent) -> ToolCardState {
        let call = decode(ToolCall.self, event.payloadJSON)
        let title = call?.name ?? "Tool"
        let inputJSON = call?.argumentsJSON ?? event.payloadJSON
        return ToolCardState(
            id: call?.id ?? event.id.uuidString,
            title: title,
            subtitle: toolSubtitle(stateLabel: "Queued", title: title, inputJSON: inputJSON),
            status: .queued,
            inputJSON: inputJSON
        )
    }

    static func orphanCard(
        id: String,
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String?
    ) -> ToolCardState {
        ToolCardState(
            id: id,
            title: "Tool",
            subtitle: stateLabel,
            status: status,
            outputJSON: outputJSON,
            artifacts: outputJSON.map(artifacts(from:)) ?? []
        )
    }

    static func approvalReviewCard(for event: ThreadEvent, fallback: ToolCardState? = nil) -> ToolCardState {
        let request = decode(ApprovalRequest.self, event.payloadJSON)
        let toolCall = request?.toolCall
        let title = toolCall?.name ?? fallback?.title ?? "Approval needed"
        let inputJSON = toolCall?.argumentsJSON ?? fallback?.inputJSON ?? event.payloadJSON
        let actions = request.flatMap { approvalActions(for: $0) } ?? []

        return ToolCardState(
            id: fallback?.id ?? toolCall?.id ?? event.id.uuidString,
            title: title,
            subtitle: approvalSubtitle(
                title: title,
                inputJSON: inputJSON,
                reason: request?.reason ?? event.summary,
                recommendedVerdict: request?.recommendedVerdict
            ),
            status: .review,
            inputJSON: inputJSON,
            actions: actions,
            isExpanded: true,
            reviewState: request?.recommendedVerdict == .deny ? .needsReview : .ready
        )
    }

    static func updateApprovalCard(_ card: inout ToolCardState, decisionJSON: String?) {
        let decision = decode(ApprovalDecision.self, decisionJSON)
        let stateLabel: String
        switch decision?.verdict {
        case .approve:
            stateLabel = "Approved"
        case .deny:
            stateLabel = "Skipped"
        case .clarify:
            stateLabel = "Needs detail"
        case .none:
            stateLabel = "Updated"
        }
        card.status = .done
        card.subtitle = toolSubtitle(stateLabel: stateLabel, title: card.title, inputJSON: card.inputJSON)
        card.outputJSON = decisionJSON
        card.actions = []
        card.density = ToolCardState.defaultDensity(status: card.status, isExpanded: false)
        card.reviewState = .none
        card.isExpanded = false
    }

    static func updateCard(
        _ card: inout ToolCardState,
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String? = nil
    ) {
        card.status = status
        card.subtitle = toolSubtitle(stateLabel: stateLabel, title: card.title, inputJSON: card.inputJSON)
        card.density = ToolCardState.defaultDensity(status: status, isExpanded: card.isExpanded)
        card.reviewState = ToolCardState.defaultReviewState(status: status)
        card.isExpanded = card.density == .expanded
        if let outputJSON {
            card.outputJSON = outputJSON
            card.artifacts = artifacts(from: outputJSON)
        }
    }

    private static func approvalActions(for request: ApprovalRequest) -> [ToolCardActionSurface]? {
        guard request.recommendedVerdict != .deny else {
            return nil
        }
        return [
            ToolCardActionSurface(
                title: "Run",
                kind: .approve,
                requestID: request.id,
                style: .primary,
                systemImage: "play.fill"
            ),
            ToolCardActionSurface(
                title: "Edit",
                kind: .edit,
                requestID: request.id,
                style: .secondary,
                systemImage: "pencil"
            ),
            ToolCardActionSurface(
                title: "Skip",
                kind: .deny,
                requestID: request.id,
                style: .secondary,
                systemImage: "xmark"
            )
        ]
    }

    private static func approvalSubtitle(
        title: String,
        inputJSON: String?,
        reason: String,
        recommendedVerdict: ApprovalVerdict?
    ) -> String {
        let stateLabel = recommendedVerdict == .deny ? "Blocked" : "Ready to run"
        let base = toolSubtitle(stateLabel: stateLabel, title: title, inputJSON: inputJSON)
        let cleanedReason = reason
            .replacingOccurrences(of: #"^(approve|deny|clarify):\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMeaningfulApprovalReason(cleanedReason),
              cleanedReason != base
        else {
            return base
        }
        return "\(base) · \(cleanedReason)"
    }

    private static func isMeaningfulApprovalReason(_ reason: String) -> Bool {
        let normalized = reason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        return ![
            "review required",
            "approval requested",
            "approve shell",
            "needs review",
            "needs your okay"
        ].contains(normalized)
    }

    private static func artifacts(from outputJSON: String) -> [ToolArtifactState] {
        guard let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON) else {
            return []
        }
        return result.artifacts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { value in
                ToolArtifactState(value: value, textPreview: ToolArtifactTextPreviewBuilder.textPreview(for: value))
            }
    }

    private static func toolSubtitle(stateLabel: String, title: String, inputJSON: String?) -> String {
        WorkspaceToolCardSubtitleBuilder.subtitle(stateLabel: stateLabel, toolName: title, inputJSON: inputJSON)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
