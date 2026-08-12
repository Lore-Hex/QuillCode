import Foundation
import QuillCodeCore
import QuillCodeTools

/// Projects a failed turn into a compact scratch context for action-only recovery. The durable
/// thread remains untouched; the correction keeps the original request and the most recent tool
/// evidence while dropping superseded browsing attempts that encourage the model to re-plan.
enum AgentCorrectiveContext {
    static let maximumRecentMessageCharacters = 36_000
    static let minimumRecentMessageCount = 4
    static let maximumRecentMessageEntryCharacters = 8_000
    static let maximumResearchEvidenceCharacters = 48_000
    static let maximumResearchEvidenceEntryCharacters = 16_000
    static let maximumRequiredInputEvidenceCharacters = 24_000

    private struct ResearchEvidence {
        var toolName: String
        var source: String?
        var stdout: String

        var sourceKey: String? {
            guard toolName == ToolDefinition.webFetch.name, let source else { return nil }
            return AgentCitationIntegrityGate.normalize(source)
        }

        var qualityScore: Int {
            let structuredLineCount = stdout.split(separator: "\n").filter { line in
                line.contains("|") || line.contains("\t")
            }.count
            return stdout.count + min(structuredLineCount, 100) * 250
        }
    }

    private struct DelegatedResearchOutput: Decodable {
        struct Worker: Decodable {
            var name: String
            var status: SubagentStatus
            var summary: String?
        }

        var summary: String
        var workers: [Worker]
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

            let retainedMessage = boundedRecentMessage(message)
            let mustKeep = retainedReversed.count < minimumRecentMessageCount
            if !mustKeep,
               retainedCharacters + retainedMessage.content.count
                    > maximumRecentMessageCharacters {
                break
            }
            retainedReversed.append(retainedMessage)
            retainedCharacters += retainedMessage.content.count
        }

        let retainedIDs = Set(retainedReversed.map(\.id))
        let olderMessages = body.filter { message in
            message.id != originalRequest?.id && !retainedIDs.contains(message.id)
        }
        let retainedDelegatedMessages = retainedReversed.filter { message in
            successfulResearchEvidence(from: message)?.toolName
                == ToolDefinition.subagentsRun.name
        }
        let evidence = pinnedResearchEvidence(
            from: olderMessages + retainedDelegatedMessages
        )
        let requiredInputEvidence = pinnedRequiredInputEvidence(
            from: olderMessages,
            requiredPaths: Set(
                originalRequest.map {
                    AgentExplicitSourceReadRecovery.requiredInputPaths(in: $0.content)
                } ?? []
            )
        )

        var projected = thread
        var messages = Array(leadingSystem)
        if let originalRequest,
           !retainedReversed.contains(where: { $0.id == originalRequest.id }) {
            messages.append(originalRequest)
        }
        if !requiredInputEvidence.isEmpty {
            messages.append(.init(role: .user, content: requiredInputEvidence))
        }
        if !evidence.isEmpty {
            messages.append(.init(role: .user, content: evidence))
        }
        messages.append(contentsOf: retainedReversed.reversed())
        projected.messages = messages
        return projected
    }

    private static func boundedRecentMessage(_ message: ChatMessage) -> ChatMessage {
        guard message.content.count > maximumRecentMessageEntryCharacters else { return message }

        var retained = message
        if message.role == .tool,
           let feedback = try? JSONDecoder().decode(
               AgentToolFeedback.self,
               from: Data(message.content.utf8)
           ) {
            retained.content = compactedToolFeedback(feedback)
        } else {
            retained.content = boundedExcerpt(
                message.content,
                maximumCharacters: maximumRecentMessageEntryCharacters
            )
        }
        return retained
    }

    private static func compactedToolFeedback(_ original: AgentToolFeedback) -> String {
        var feedback = original
        feedback.toolCall.argumentsJSON = compactedToolArguments(
            original.toolCall.argumentsJSON
        )
        feedback.result = compactedToolResult(
            original.result,
            toolName: original.toolCall.name,
            stdoutLimit: 5_500
        )
        if let followUp = original.followUpResult {
            feedback.followUpResult = compactedToolResult(
                followUp,
                toolName: original.toolCall.name,
                stdoutLimit: 800
            )
        }

        if let encoded = encodedToolFeedback(feedback),
           encoded.count <= maximumRecentMessageEntryCharacters {
            return encoded
        }

        feedback.toolCall.argumentsJSON = "{}"
        feedback.result = compactedToolResult(
            original.result,
            toolName: original.toolCall.name,
            stdoutLimit: 1_500
        )
        feedback.followUpResult = nil
        return encodedToolFeedback(feedback) ?? boundedExcerpt(
            original.result.stdout,
            maximumCharacters: maximumRecentMessageEntryCharacters
        )
    }

    private static func compactedToolResult(
        _ original: ToolResult,
        toolName: String,
        stdoutLimit: Int
    ) -> ToolResult {
        var result = original
        let preferredOutput = toolName == ToolDefinition.subagentsRun.name
            ? delegatedResearchDigest(from: original.stdout) ?? original.stdout
            : original.stdout
        result.stdout = boundedExcerpt(preferredOutput, maximumCharacters: stdoutLimit)
        result.stderr = boundedExcerpt(original.stderr, maximumCharacters: 500)
        result.error = original.error.map {
            boundedExcerpt($0, maximumCharacters: 500)
        }
        result.artifacts = original.artifacts.prefix(8).map {
            boundedExcerpt($0, maximumCharacters: 300)
        }
        return result
    }

    private static func compactedToolArguments(_ argumentsJSON: String) -> String {
        guard argumentsJSON.count > 1_500,
              let data = argumentsJSON.data(using: .utf8),
              var arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return argumentsJSON }

        for key in arguments.keys {
            if key == "content" || key == "text" || key == "body" {
                arguments[key] = "[large payload omitted from corrective context]"
            } else if let value = arguments[key] as? String, value.count > 1_000 {
                arguments[key] = boundedExcerpt(value, maximumCharacters: 1_000)
            }
        }
        guard let compacted = try? JSONSerialization.data(
            withJSONObject: arguments,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        let compactedJSON = String(decoding: compacted, as: UTF8.self)
        guard compactedJSON.count > 1_500 else { return compactedJSON }

        let visibleKeys = ["path", "paths", "url", "query", "name", "cmd", "pattern"]
        var summary: [String: Any] = [:]
        for key in visibleKeys {
            if let value = arguments[key] as? String {
                summary[key] = boundedExcerpt(value, maximumCharacters: 500)
            } else if let values = arguments[key] as? [String] {
                summary[key] = values.prefix(8).map {
                    boundedExcerpt($0, maximumCharacters: 200)
                }
            }
        }
        guard let summarized = try? JSONSerialization.data(
            withJSONObject: summary,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ), summarized.count <= 1_500 else { return "{}" }
        return String(decoding: summarized, as: UTF8.self)
    }

    private static func encodedToolFeedback(_ feedback: AgentToolFeedback) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(feedback) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func pinnedRequiredInputEvidence(
        from messages: [ChatMessage],
        requiredPaths: Set<String>
    ) -> String {
        guard !requiredPaths.isEmpty else { return "" }
        var receiptsByKey: [String: String] = [:]
        for message in messages where message.role == .tool {
            guard let data = message.content.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let toolCall = payload["toolCall"] as? [String: Any],
                  let toolName = toolCall["name"] as? String,
                  toolName == ToolDefinition.fileRead.name
                    || toolName == ToolDefinition.fileReadMany.name,
                  let result = payload["result"] as? [String: Any],
                  result["ok"] as? Bool == true,
                  let stdout = result["stdout"] as? String,
                  !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let argumentsJSON = toolCall["argumentsJSON"] as? String,
                  let arguments = try? ToolArguments(argumentsJSON)
            else { continue }

            let paths: [String]
            if toolName == ToolDefinition.fileRead.name,
               let path = arguments.string("path") {
                paths = [path]
            } else {
                paths = arguments.stringArray("paths") ?? []
            }
            let matched = paths.map(AgentArtifactVerificationGate.normalizedPath).filter { path in
                requiredPaths.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, path)
                })
            }
            guard !matched.isEmpty else { continue }
            let key = matched.sorted().joined(separator: " | ")
            receiptsByKey[key] = "[required input read: \(key)]\n" + boundedExcerpt(
                stdout,
                maximumCharacters: maximumResearchEvidenceEntryCharacters
            )
        }
        guard !receiptsByKey.isEmpty else { return "" }
        let evidence = receiptsByKey.sorted(by: { $0.key < $1.key })
            .map(\.value)
            .joined(separator: "\n\n")
        return """
        Host-retained required local input evidence follows. These are exact successful file-read \
        results and remain authoritative over model recollection, drafts, delegated summaries, and \
        hard-coded validator expectations.

        \(boundedExcerpt(evidence, maximumCharacters: maximumRequiredInputEvidenceCharacters))
        """
    }

    private static func pinnedResearchEvidence(
        from messages: [ChatMessage]
    ) -> String {
        let parsed = messages.compactMap(successfulResearchEvidence)
        let prioritized = strongestDirectEvidence(from: parsed)
            + Array(parsed.filter { $0.toolName == ToolDefinition.subagentsRun.name }.reversed())

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
        window but remains authoritative. Direct host.web.fetch observations appear first and are \
        authoritative over delegated summaries when they conflict. Preserve verified facts and exact \
        source URLs during synthesis; do not replace a stronger grounded artifact with an incomplete \
        one merely because later fetches failed.

        \(entries.joined(separator: "\n\n"))
        """
    }

    private static func strongestDirectEvidence(
        from evidence: [ResearchEvidence]
    ) -> [ResearchEvidence] {
        var retained: [(index: Int, evidence: ResearchEvidence)] = []
        var indexBySource: [String: Int] = [:]

        for (index, observation) in evidence.enumerated()
            where observation.toolName == ToolDefinition.webFetch.name {
            guard let sourceKey = observation.sourceKey else {
                retained.append((index, observation))
                continue
            }
            if let retainedIndex = indexBySource[sourceKey] {
                if observation.qualityScore >= retained[retainedIndex].evidence.qualityScore {
                    retained[retainedIndex] = (index, observation)
                }
            } else {
                indexBySource[sourceKey] = retained.count
                retained.append((index, observation))
            }
        }
        return retained.sorted { $0.index > $1.index }.map(\.evidence)
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

        if toolName == ToolDefinition.webFetch.name,
           WebFetchSemanticFailure.description(in: stdout) != nil {
            return nil
        }

        var source: String?
        if let argumentsJSON = toolCall["argumentsJSON"] as? String,
           let argumentsData = argumentsJSON.data(using: .utf8),
           let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] {
            source = arguments["url"] as? String
        }
        let retainedOutput = toolName == ToolDefinition.subagentsRun.name
            ? delegatedResearchDigest(from: stdout) ?? stdout
            : stdout
        return ResearchEvidence(toolName: toolName, source: source, stdout: retainedOutput)
    }

    private static func delegatedResearchDigest(from stdout: String) -> String? {
        guard let data = stdout.data(using: .utf8),
              let output = try? JSONDecoder().decode(DelegatedResearchOutput.self, from: data)
        else { return nil }

        let workers = output.workers.sorted { left, right in
            let leftPriority = delegatedStatusPriority(left.status)
            let rightPriority = delegatedStatusPriority(right.status)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
        let entries = workers.compactMap { worker -> String? in
            guard let summary = worker.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !summary.isEmpty
            else { return nil }
            return "[\(worker.status.rawValue) worker: \(worker.name)]\n\(summary)"
        }
        return (["[delegated research coordinator]\n\(output.summary)"] + entries)
            .joined(separator: "\n\n")
    }

    private static func delegatedStatusPriority(_ status: SubagentStatus) -> Int {
        switch status {
        case .completed:
            0
        case .cancelled, .failed, .interrupted:
            1
        case .blocked, .awaitingApproval:
            2
        case .queued, .running:
            3
        }
    }

    private static func boundedExcerpt(_ text: String, maximumCharacters: Int) -> String {
        guard text.count > maximumCharacters else { return text }
        let marker = "\n[...middle omitted from retained evidence...]\n"
        guard maximumCharacters > marker.count else {
            return String(text.prefix(maximumCharacters))
        }
        let availableCharacters = maximumCharacters - marker.count
        let headCount = availableCharacters * 2 / 3
        let tailCount = availableCharacters - headCount
        return String(text.prefix(headCount))
            + marker
            + String(text.suffix(tailCount))
    }
}
