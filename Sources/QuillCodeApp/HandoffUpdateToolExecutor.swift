import Foundation
import QuillCodeCore

enum HandoffUpdateToolExecutor {
    private static let maxSummaryCharacters = 1_200
    private static let maxNextStepCount = 8
    private static let maxNextStepCharacters = 180

    static func execute(_ call: ToolCall) -> ToolResult {
        guard call.name == ToolDefinition.handoffUpdate.name else {
            return ToolResult(ok: false, error: "Unknown tool: \(call.name)")
        }

        do {
            let update = try normalizedUpdate(from: call.argumentsJSON)
            return ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        } catch {
            return ToolResult(ok: false, error: userFacingError(error))
        }
    }

    static func latestUpdate(in thread: ChatThread) -> AgentHandoffUpdate? {
        thread.events.reversed().compactMap(handoffUpdate).first
    }

    static func displayText(for update: AgentHandoffUpdate) -> String {
        guard !update.nextSteps.isEmpty else {
            return update.summary
        }
        let steps = update.nextSteps.enumerated().map { index, step in
            "\(index + 1). \(step)"
        }
        return ([update.summary, "Next steps:"] + steps).joined(separator: "\n")
    }

    private static func handoffUpdate(from event: ThreadEvent) -> AgentHandoffUpdate? {
        guard event.kind == .toolCompleted,
              event.summary == "\(ToolDefinition.handoffUpdate.name) completed",
              let payloadJSON = event.payloadJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: payloadJSON),
              result.ok,
              let update = try? JSONHelpers.decode(AgentHandoffUpdate.self, from: result.stdout)
        else {
            return nil
        }
        return update.summary.isEmpty ? nil : update
    }

    private static func normalizedUpdate(from argumentsJSON: String) throws -> AgentHandoffUpdate {
        let decoded = try JSONHelpers.decode(AgentHandoffUpdate.self, from: argumentsJSON)
        let summary = boundedMultiline(decoded.summary, limit: maxSummaryCharacters)
        guard !summary.isEmpty else {
            throw HandoffUpdateToolError.emptySummary
        }
        let nextSteps = decoded.nextSteps
            .map { boundedLine($0, limit: maxNextStepCharacters) }
            .filter { !$0.isEmpty }
        guard nextSteps.count <= maxNextStepCount else {
            throw HandoffUpdateToolError.tooManyNextSteps(nextSteps.count, maxNextStepCount)
        }
        return AgentHandoffUpdate(summary: summary, nextSteps: nextSteps)
    }

    private static func boundedMultiline(_ text: String, limit: Int) -> String {
        let normalized = text
            .split(whereSeparator: \.isNewline)
            .map { boundedLine(String($0), limit: limit) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func boundedLine(_ text: String, limit: Int) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func userFacingError(_ error: any Error) -> String {
        if let error = error as? HandoffUpdateToolError {
            return error.description
        }
        return "Handoff update arguments must be JSON with `summary` and optional `nextSteps`."
    }
}

private enum HandoffUpdateToolError: Error, CustomStringConvertible {
    case emptySummary
    case tooManyNextSteps(Int, Int)

    var description: String {
        switch self {
        case .emptySummary:
            return "Handoff update requires a non-empty summary."
        case .tooManyNextSteps(let count, let limit):
            return "Handoff update has \(count) next steps; keep it to \(limit) or fewer."
        }
    }
}
