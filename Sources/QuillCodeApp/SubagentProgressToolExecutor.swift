import Foundation
import QuillCodeCore

enum SubagentProgressToolExecutor {
    private static let maxSubagentCount = 12
    private static let maxObjectiveCharacters = 260
    private static let maxGroupPathComponentCharacters = 32
    private static let maxNameCharacters = 72
    private static let maxRoleCharacters = 140
    private static let maxSummaryCharacters = 220
    private static let maxTranscriptEntryCount = 24
    private static let maxTranscriptIDCharacters = 96
    private static let maxTranscriptTitleCharacters = 72
    private static let maxTranscriptDetailCharacters = 320
    private static let maxTranscriptStatusCharacters = 24
    private static let maxApprovalIDCharacters = 96
    private static let maxApprovalToolNameCharacters = 96
    private static let maxApprovalReasonCharacters = 220

    static func execute(_ call: ToolCall) -> ToolResult {
        guard call.name == ToolDefinition.subagentsUpdate.name else {
            return ToolResult(ok: false, error: "Unknown tool: \(call.name)")
        }

        do {
            let update = try normalizedUpdate(from: call.argumentsJSON)
            return ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        } catch {
            return ToolResult(ok: false, error: userFacingError(error))
        }
    }

    static func latestUpdate(in thread: ChatThread) -> SubagentProgressUpdate? {
        thread.events.reversed().compactMap(subagentUpdate).first
    }

    static func activityItems(for thread: ChatThread) -> [ActivityItemSurface] {
        guard let update = latestUpdate(in: thread) else { return [] }
        return update.subagents.enumerated().map { index, item in
            ActivityItemSurface(
                id: "subagent-\(index)-\(item.name)",
                title: displayTitle(for: item),
                detail: detail(for: item, objective: update.objective),
                kind: "subagent",
                statusLabel: item.status.label,
                actions: actions(for: item),
                transcript: item.transcript
            )
        }
    }

    private static func subagentUpdate(from event: ThreadEvent) -> SubagentProgressUpdate? {
        guard event.kind == .toolCompleted,
              event.summary == "\(ToolDefinition.subagentsUpdate.name) completed",
              let payloadJSON = event.payloadJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: payloadJSON),
              result.ok,
              let update = try? JSONHelpers.decode(SubagentProgressUpdate.self, from: result.stdout)
        else {
            return nil
        }
        return update.subagents.isEmpty ? nil : update
    }

    private static func normalizedUpdate(from argumentsJSON: String) throws -> SubagentProgressUpdate {
        let decoded = try JSONHelpers.decode(SubagentProgressUpdate.self, from: argumentsJSON)
        let subagents = decoded.subagents
            .map(normalizedItem)
            .filter { !$0.name.isEmpty && !$0.role.isEmpty }
        guard !subagents.isEmpty else {
            throw SubagentProgressToolError.emptySubagents
        }
        guard subagents.count <= maxSubagentCount else {
            throw SubagentProgressToolError.tooManySubagents(subagents.count, maxSubagentCount)
        }
        return SubagentProgressUpdate(
            objective: boundedOptionalText(decoded.objective, limit: maxObjectiveCharacters),
            subagents: subagents
        )
    }

    private static func normalizedItem(_ item: SubagentProgressItem) -> SubagentProgressItem {
        let name = boundedLine(item.name, limit: maxNameCharacters)
        let approvalGate = item.status == .awaitingApproval
            ? normalizedApprovalGate(item.approvalGate)
            : nil
        let status: SubagentStatus = item.status == .awaitingApproval && approvalGate == nil
            ? .blocked
            : item.status
        return SubagentProgressItem(
            name: name,
            role: boundedLine(item.role, limit: maxRoleCharacters),
            status: status,
            summary: boundedOptionalText(item.summary, limit: maxSummaryCharacters),
            groupPath: normalizedGroupPath(item.groupPath, fallbackName: name),
            transcript: normalizedTranscript(item.transcript),
            approvalGate: approvalGate
        )
    }

    private static func normalizedApprovalGate(_ gate: SubagentApprovalGate?) -> SubagentApprovalGate? {
        guard let gate else { return nil }
        let runID = boundedLine(gate.runID, limit: maxApprovalIDCharacters)
        let requestID = boundedLine(gate.requestID, limit: maxApprovalIDCharacters)
        let toolName = boundedRedactedLine(gate.toolName, limit: maxApprovalToolNameCharacters)
        let normalized = SubagentApprovalGate(
            runID: runID,
            requestID: requestID,
            toolName: toolName,
            reason: boundedRedactedLine(gate.reason, limit: maxApprovalReasonCharacters)
        )
        return WorkspaceSubagentApprovalCommand.isValid(normalized) ? normalized : nil
    }

    private static func actions(for item: SubagentProgressItem) -> [ActivityItemActionSurface] {
        guard item.status == .awaitingApproval, let gate = item.approvalGate else { return [] }
        return [
            ActivityItemActionSurface(
                title: "Approve",
                commandID: WorkspaceSubagentApprovalCommand.approveCommandID(for: gate),
                kind: "approve"
            ),
            ActivityItemActionSurface(
                title: "Skip",
                commandID: WorkspaceSubagentApprovalCommand.rejectCommandID(for: gate),
                kind: "reject"
            )
        ]
    }

    private static func normalizedTranscript(_ entries: [SubagentTranscriptEntry]) -> [SubagentTranscriptEntry] {
        entries.prefix(maxTranscriptEntryCount).enumerated().compactMap { index, entry in
            let title = boundedRedactedLine(entry.title, limit: maxTranscriptTitleCharacters)
            guard !title.isEmpty else { return nil }
            let normalizedID = boundedLine(entry.id, limit: maxTranscriptIDCharacters)
            return SubagentTranscriptEntry(
                id: normalizedID.isEmpty ? "transcript-\(index)" : normalizedID,
                kind: entry.kind,
                title: title,
                detail: boundedRedactedLine(entry.detail, limit: maxTranscriptDetailCharacters),
                statusLabel: boundedRedactedLine(entry.statusLabel, limit: maxTranscriptStatusCharacters)
            )
        }
    }

    private static func detail(for item: SubagentProgressItem, objective: String?) -> String {
        let parts = [
            groupPathDetail(for: item),
            item.role,
            item.summary,
            item.approvalGate.map { "Approval: \($0.reason)" },
            objective.map { "Goal: \($0)" }
        ].compactMap { text -> String? in
            guard let text, !text.isEmpty else { return nil }
            return text
        }
        return boundedLine(parts.joined(separator: " - "), limit: 220)
    }

    private static func displayTitle(for item: SubagentProgressItem) -> String {
        guard !item.groupPath.isEmpty,
              let leaf = item.name.split(separator: "/").last
        else { return item.name }
        return String(leaf)
    }

    private static func groupPathDetail(for item: SubagentProgressItem) -> String? {
        let path = normalizedGroupPath(item.groupPath, fallbackName: item.name)
        guard !path.isEmpty else { return nil }
        let leaf = item.name.split(separator: "/").last.map(String.init) ?? item.name
        return "Path: \((path + [leaf]).joined(separator: " / "))"
    }

    private static func normalizedGroupPath(_ explicitPath: [String], fallbackName: String) -> [String] {
        let path = explicitPath.isEmpty ? inferredGroupPath(from: fallbackName) : explicitPath
        return path
            .map { boundedLine($0, limit: maxGroupPathComponentCharacters) }
            .filter { !$0.isEmpty }
    }

    private static func inferredGroupPath(from name: String) -> [String] {
        let components = name
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count > 1 else { return [] }
        return Array(components.dropLast())
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        guard let text = text.map({ boundedLine($0, limit: limit) }), !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func boundedLine(_ text: String, limit: Int) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func boundedRedactedLine(_ text: String, limit: Int) -> String {
        boundedLine(WorkspaceContextSummarySanitizer.summary(from: text) ?? "", limit: limit)
    }

    private static func userFacingError(_ error: any Error) -> String {
        if let error = error as? SubagentProgressToolError {
            return error.description
        }
        return "Subagent progress arguments must be JSON with `subagents: [{ name, role, status }]`."
    }
}

private enum SubagentProgressToolError: Error, CustomStringConvertible {
    case emptySubagents
    case tooManySubagents(Int, Int)

    var description: String {
        switch self {
        case .emptySubagents:
            return "Subagent progress requires at least one subagent with a name and role."
        case .tooManySubagents(let count, let limit):
            return "Subagent progress has \(count) subagents; keep it to \(limit) or fewer."
        }
    }
}
