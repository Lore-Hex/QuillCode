import Foundation
import QuillCodeCore
import QuillComputerUseKit
import QuillCodeSafety

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
        let title = approvalTitle(request: request, fallback: fallback)
        let inputJSON = toolCall?.argumentsJSON ?? fallback?.inputJSON ?? event.payloadJSON
        let actions = request.flatMap { approvalActions(for: $0) } ?? []
        let needsReview = request?.recommendedVerdict == .deny

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
            isExpanded: needsReview,
            density: needsReview ? .expanded : .peek,
            reviewState: needsReview ? .needsReview : .ready
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
        card.subtitle = outputSubtitle(
            stateLabel: stateLabel,
            title: card.title,
            outputJSON: outputJSON
        ) ?? toolSubtitle(stateLabel: stateLabel, title: card.title, inputJSON: card.inputJSON)
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
        if request.scope == .runSpendFuse {
            return [
                ToolCardActionSurface(
                    title: "Continue",
                    kind: .approve,
                    requestID: request.id,
                    style: .primary,
                    systemImage: "play.fill"
                ),
                ToolCardActionSurface(
                    title: "Stop",
                    kind: .deny,
                    requestID: request.id,
                    style: .secondary,
                    systemImage: "xmark"
                )
            ]
        }
        var actions = [
            ToolCardActionSurface(
                title: "Run",
                kind: .approve,
                requestID: request.id,
                style: .primary,
                systemImage: "play.fill"
            )
        ]
        // "Always run" is only offered when the call is allow-scopable — i.e. an exact rule derived
        // from it would bound what runs. For a tool with no bounding resource (apply_patch, git.*,
        // a shell call carrying an env/cwd override) an always-allow would over-broaden, so the
        // button is withheld; "Run" (this once) still works. Scopability depends only on the tool
        // call arguments, so a nil workspace root is fine here (matching not being performed).
        if PermissionRuleSubject.make(toolCall: request.toolCall, workspaceRoot: nil).allowScopable {
            actions.append(ToolCardActionSurface(
                title: "Always run",
                kind: .approveAlways,
                requestID: request.id,
                style: .secondary,
                systemImage: "repeat"
            ))
        }
        actions.append(contentsOf: [
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
            ),
            ToolCardActionSurface(
                title: "Never",
                kind: .denyAlways,
                requestID: request.id,
                style: .destructive,
                systemImage: "nosign"
            )
        ])
        return actions
    }

    private static func approvalTitle(request: ApprovalRequest?, fallback: ToolCardState?) -> String {
        if request?.scope == .runSpendFuse {
            return spendReviewTitle(for: request)
        }
        return request?.toolCall.name ?? fallback?.title ?? "Approval needed"
    }

    private static func spendReviewTitle(for request: ApprovalRequest?) -> String {
        guard let kind = spendLimitKind(in: request),
              kind != .threadFuse
        else {
            return "Spend Review"
        }
        return "\(spendLimitName(kind)) Spend Review"
    }

    private static func spendLimitName(_ kind: RunSpendLimitKind) -> String {
        switch kind {
        case .threadFuse:
            return "Thread"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }

    private static func spendLimitKind(in request: ApprovalRequest?) -> RunSpendLimitKind? {
        guard let request,
              request.scope == .runSpendFuse
        else {
            return nil
        }
        return decode(RunSpendFuseApprovalPayload.self, request.toolCall.argumentsJSON)?.approvalLimitKind
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

    private static func outputSubtitle(stateLabel: String, title: String, outputJSON: String?) -> String? {
        guard title == ToolDefinition.computerScreenshot.name,
              let outputJSON,
              let result = decode(ToolResult.self, outputJSON),
              result.ok,
              let screenshot = try? JSONHelpers.decode(ComputerScreenshotToolOutput.self, from: result.stdout)
        else {
            return nil
        }
        var details = ["\(screenshot.width) x \(screenshot.height)"]
        if let foregroundApplication = boundedDetail(screenshot.foregroundApplication?.displayLabel) {
            details.append(foregroundApplication)
        }
        if let count = screenshot.accessibilitySnapshot?.elements.count, count > 0 {
            details.append("\(count) controls")
        }
        return "\(stateLabel) · \(details.joined(separator: " · "))"
    }

    private static func boundedDetail(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > 72 else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 72)
        return String(collapsed[..<end]) + "..."
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
