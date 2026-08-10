import Foundation
import QuillCodeCore

/// Projects a failed turn into a compact scratch context for action-only recovery. The durable
/// thread remains untouched; the correction keeps the original request and the most recent tool
/// evidence while dropping superseded browsing attempts that encourage the model to re-plan.
enum AgentCorrectiveContext {
    static let maximumRecentMessageCharacters = 36_000
    static let minimumRecentMessageCount = 4
    static let maximumResearchEvidenceCharacters = 48_000
    static let maximumResearchEvidenceEntryCharacters = 16_000

    private struct ResearchEvidence {
        var toolName: String
        var source: String?
        var stdout: String
    }

    static func projected(_ thread: ChatThread) -> ChatThread {
        guard thread.messages.count > minimumRecentMessageCount else { return thread }

        let leadingSystem = thread.messages.prefix(while: { $0.role == .system })
        let body = thread.messages.dropFirst(leadingSystem.count)
        let originalRequest = body.first(where: { $0.role == .user })

        var retainedReversed: [ChatMessage] = []
        var retainedCharacters = 0
        for message in body.reversed() {
            let isOriginalRequest = message.id == originalRequest?.id
            if isOriginalRequest { continue }

            let mustKeep = retainedReversed.count < minimumRecentMessageCount
            if !mustKeep,
               retainedCharacters + message.content.count > maximumRecentMessageCharacters {
                break
            }
            retainedReversed.append(message)
            retainedCharacters += message.content.count
        }

        let retainedIDs = Set(retainedReversed.map(\.id))
        let olderMessages = body.filter { message in
            message.id != originalRequest?.id && !retainedIDs.contains(message.id)
        }
        let evidence = pinnedResearchEvidence(from: olderMessages)

        var projected = thread
        var messages = Array(leadingSystem)
        if let originalRequest,
           !retainedReversed.contains(where: { $0.id == originalRequest.id }) {
            messages.append(originalRequest)
        }
        if !evidence.isEmpty {
            messages.append(.init(role: .user, content: evidence))
        }
        messages.append(contentsOf: retainedReversed.reversed())
        projected.messages = messages
        return projected
    }

    private static func pinnedResearchEvidence(
        from messages: [ChatMessage]
    ) -> String {
        let parsed = messages.compactMap(successfulResearchEvidence)
        let prioritized = Array(
            parsed.filter { $0.toolName == ToolDefinition.subagentsRun.name }.reversed()
        ) + Array(parsed.filter { $0.toolName == ToolDefinition.webFetch.name }.reversed())

        var entries: [String] = []
        var retainedCharacters = 0
        for evidence in prioritized {
            let output = boundedExcerpt(
                evidence.stdout,
                maximumCharacters: maximumResearchEvidenceEntryCharacters
            )
            let source = evidence.source.map { " (\($0))" } ?? ""
            let entry = "[\(evidence.toolName)\(source)]\n\(output)"
            guard retainedCharacters + entry.count <= maximumResearchEvidenceCharacters else {
                continue
            }
            entries.append(entry)
            retainedCharacters += entry.count
        }
        guard !entries.isEmpty else { return "" }
        return """
        Host-retained successful research evidence follows. This evidence predates the recent retry \
        window but remains authoritative. Preserve its verified facts and exact source URLs during \
        synthesis; do not replace a stronger grounded artifact with an incomplete one merely because \
        later fetches failed.

        \(entries.joined(separator: "\n\n"))
        """
    }

    private static func successfulResearchEvidence(
        from message: ChatMessage
    ) -> ResearchEvidence? {
        guard message.role == .tool,
              let data = message.content.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolCall = payload["toolCall"] as? [String: Any],
              let toolName = toolCall["name"] as? String,
              toolName == ToolDefinition.subagentsRun.name
                || toolName == ToolDefinition.webFetch.name,
              let result = payload["result"] as? [String: Any],
              result["ok"] as? Bool == true,
              let stdout = result["stdout"] as? String,
              !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        var source: String?
        if let argumentsJSON = toolCall["argumentsJSON"] as? String,
           let argumentsData = argumentsJSON.data(using: .utf8),
           let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] {
            source = arguments["url"] as? String
        }
        return ResearchEvidence(toolName: toolName, source: source, stdout: stdout)
    }

    private static func boundedExcerpt(_ text: String, maximumCharacters: Int) -> String {
        guard text.count > maximumCharacters else { return text }
        let headCount = maximumCharacters * 2 / 3
        let tailCount = maximumCharacters - headCount
        return String(text.prefix(headCount))
            + "\n[...middle omitted from retained evidence...]\n"
            + String(text.suffix(tailCount))
    }
}
