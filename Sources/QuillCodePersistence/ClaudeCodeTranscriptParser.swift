import Foundation
import QuillCodeCore

struct ClaudeCodeTranscriptSummary: Sendable, Hashable {
    var sessionID: String
    var cwd: String?
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
}

enum ClaudeCodeTranscriptParser {
    static let maximumFileBytes = 12_000_000
    static let maximumLineBytes = 1_000_000
    static let maximumMessages = 2_000
    static let maximumMessageCharacters = 100_000
    static let maximumTranscriptCharacters = 2_000_000

    static func parse(fileURL: URL, sourceRoot: URL) -> ClaudeCodeTranscriptSummary? {
        guard let data = AgentImportFileSystem.readData(
            fileURL,
            inside: sourceRoot,
            maximumBytes: maximumFileBytes
        ),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        var sessionID = fileURL.deletingPathExtension().lastPathComponent
        var cwd: String?
        var messages: [ChatMessage] = []
        var transcriptCharacters = 0
        var earliestDate: Date?
        var latestDate: Date?

        for line in text.split(whereSeparator: \.isNewline) {
            guard messages.count < maximumMessages,
                  line.utf8.count <= maximumLineBytes,
                  let object = jsonObject(String(line))
            else { continue }

            sessionID = normalizedString(object["sessionId"] ?? object["session_id"], limit: 240)
                ?? sessionID
            if cwd == nil {
                cwd = normalizedAbsolutePath(object["cwd"])
            }
            let date = parsedDate(object["timestamp"] ?? object["created_at"] ?? object["createdAt"])
            if let date {
                earliestDate = earliestDate.map { min($0, date) } ?? date
                latestDate = latestDate.map { max($0, date) } ?? date
            }
            guard object["isMeta"] as? Bool != true,
                  let role = role(from: object),
                  let content = content(from: object),
                  !content.isEmpty
            else { continue }

            let remaining = maximumTranscriptCharacters - transcriptCharacters
            guard remaining > 0 else { break }
            let bounded = String(content.prefix(min(remaining, maximumMessageCharacters)))
            transcriptCharacters += bounded.count
            messages.append(ChatMessage(role: role, content: bounded, createdAt: date ?? latestDate ?? Date()))
        }

        guard !messages.isEmpty else { return nil }
        let fallbackDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        let createdAt = earliestDate ?? messages.first?.createdAt ?? fallbackDate
        let updatedAt = latestDate ?? messages.last?.createdAt ?? fallbackDate
        return ClaudeCodeTranscriptSummary(
            sessionID: sessionID,
            cwd: cwd,
            title: title(from: messages),
            messages: messages,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func role(from object: [String: Any]) -> ChatRole? {
        let message = object["message"] as? [String: Any]
        let raw = normalizedString(message?["role"] ?? object["type"] ?? object["role"], limit: 40)?
            .lowercased()
        switch raw {
        case "user", "human": return ChatRole.user
        case "assistant": return ChatRole.assistant
        default: return nil
        }
    }

    private static func content(from object: [String: Any]) -> String? {
        let message = object["message"] as? [String: Any]
        return contentValue(message?["content"] ?? object["content"])
    }

    private static func contentValue(_ value: Any?) -> String? {
        if let text = normalizedString(value, limit: maximumMessageCharacters) {
            return text
        }
        guard let blocks = value as? [Any] else { return nil }
        let text = blocks.compactMap { block -> String? in
            if let text = normalizedString(block, limit: maximumMessageCharacters) { return text }
            guard let payload = block as? [String: Any] else { return nil }
            let type = normalizedString(payload["type"], limit: 80)?.lowercased()
            guard type == nil || type == "text" || type == "input_text" || type == "output_text" else {
                return nil
            }
            return normalizedString(payload["text"] ?? payload["content"], limit: maximumMessageCharacters)
        }.joined(separator: "\n")
        return normalizedString(text, limit: maximumMessageCharacters)
    }

    private static func normalizedString(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }

    private static func normalizedAbsolutePath(_ value: Any?) -> String? {
        guard let path = normalizedString(value, limit: 4_096), path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func parsedDate(_ value: Any?) -> Date? {
        guard let raw = normalizedString(value, limit: 100) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func title(from messages: [ChatMessage]) -> String {
        let firstUserMessage = messages.first(where: { $0.role == .user })?.content
            ?? messages.first?.content
            ?? "Imported chat"
        let oneLine = firstUserMessage
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !oneLine.isEmpty else { return "Imported chat" }
        return String(oneLine.prefix(80))
    }
}
