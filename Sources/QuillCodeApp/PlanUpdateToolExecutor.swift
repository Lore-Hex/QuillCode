import Foundation
import QuillCodeCore

enum PlanUpdateToolExecutor {
    private static let maxPlanItems = 12
    private static let maxStepCharacters = 140
    private static let maxDetailCharacters = 220
    private static let maxExplanationCharacters = 500

    static func execute(_ call: ToolCall) -> ToolResult {
        guard call.name == ToolDefinition.planUpdate.name else {
            return ToolResult(ok: false, error: "Unknown tool: \(call.name)")
        }

        do {
            let update = try normalizedUpdate(from: call.argumentsJSON)
            return ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        } catch {
            return ToolResult(ok: false, error: userFacingError(error))
        }
    }

    static func latestUpdate(in thread: ChatThread) -> AgentPlanUpdate? {
        thread.events.reversed().compactMap(planUpdate).first
    }

    private static func planUpdate(from event: ThreadEvent) -> AgentPlanUpdate? {
        guard event.kind == .toolCompleted,
              event.summary == "\(ToolDefinition.planUpdate.name) completed",
              let payloadJSON = event.payloadJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: payloadJSON),
              result.ok,
              let update = try? JSONHelpers.decode(AgentPlanUpdate.self, from: result.stdout)
        else {
            return nil
        }
        return update.plan.isEmpty ? nil : update
    }

    private static func normalizedUpdate(from argumentsJSON: String) throws -> AgentPlanUpdate {
        let decoded = try JSONHelpers.decode(AgentPlanUpdate.self, from: argumentsJSON)
        let plan = decoded.plan
            .map(normalizedItem)
            .filter { !$0.step.isEmpty }
        guard !plan.isEmpty else {
            throw PlanUpdateToolError.emptyPlan
        }
        guard plan.count <= maxPlanItems else {
            throw PlanUpdateToolError.tooManyItems(plan.count, maxPlanItems)
        }
        let runningCount = plan.filter { $0.status == .inProgress }.count
        guard runningCount <= 1 else {
            throw PlanUpdateToolError.tooManyRunningItems
        }
        return AgentPlanUpdate(
            explanation: boundedOptionalText(decoded.explanation, limit: maxExplanationCharacters),
            plan: plan
        )
    }

    private static func normalizedItem(_ item: AgentPlanItem) -> AgentPlanItem {
        AgentPlanItem(
            step: boundedText(item.step, limit: maxStepCharacters),
            status: item.status,
            detail: boundedOptionalText(item.detail, limit: maxDetailCharacters)
        )
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        guard let text = text.map({ boundedText($0, limit: limit) }), !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func userFacingError(_ error: any Error) -> String {
        if let error = error as? PlanUpdateToolError {
            return error.description
        }
        return "Plan update arguments must be JSON with `plan: [{ step, status }]`."
    }
}

private enum PlanUpdateToolError: Error, CustomStringConvertible {
    case emptyPlan
    case tooManyItems(Int, Int)
    case tooManyRunningItems

    var description: String {
        switch self {
        case .emptyPlan:
            return "Plan update requires at least one non-empty step."
        case .tooManyItems(let count, let limit):
            return "Plan update has \(count) steps; keep it to \(limit) or fewer."
        case .tooManyRunningItems:
            return "Plan update can have at most one in_progress step."
        }
    }
}
