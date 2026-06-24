import Foundation
import QuillCodeCore

enum MCPStdioResultMapper {
    struct ResourceListEntry {
        var displayName: String
        var uri: String
    }

    static func toolDescriptors(from tools: [[String: Any]]) -> [MCPToolDescriptor] {
        tools.compactMap { tool in
            guard let name = (tool["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else {
                return nil
            }
            let description = (tool["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let schema = (tool["inputSchema"] as? [String: Any])
                ?? (tool["input_schema"] as? [String: Any])
            let arguments = schemaArguments(from: schema)
            return MCPToolDescriptor(
                name: name,
                description: description,
                requiredArguments: arguments.required,
                optionalArguments: arguments.optional,
                schemaSummary: arguments.summary
            )
        }
    }

    static func names(
        from result: [String: Any],
        resultKey: String,
        nameKeys: [String]
    ) -> [String] {
        let entries = (result[resultKey] as? [[String: Any]]) ?? []
        return entries.compactMap { entry in
            firstNonEmptyString(in: entry, keys: nameKeys)
        }
    }

    static func resourceList(from result: [String: Any]) -> [ResourceListEntry] {
        let entries = (result["resources"] as? [[String: Any]]) ?? []
        return entries.compactMap { entry in
            guard let uri = firstNonEmptyString(in: entry, keys: ["uri"]) else { return nil }
            let displayName = firstNonEmptyString(in: entry, keys: ["name"]) ?? uri
            return ResourceListEntry(displayName: displayName, uri: uri)
        }
    }

    static func argumentsObject(from json: String) throws -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let data = trimmed.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw MCPProbeError.invalidMessage("MCP tool arguments must be a JSON object.")
        }
        return object
    }

    static func toolResult(from result: [String: Any]) -> ToolResult {
        let isError = (result["isError"] as? Bool) ?? false
        let content = (result["content"] as? [[String: Any]]) ?? []
        let text = content
            .compactMap(jsonText)
            .joined(separator: "\n")
        if isError {
            return ToolResult(ok: false, stderr: text, error: text.isEmpty ? "MCP tool returned an error." : text)
        }
        if !text.isEmpty {
            return ToolResult(ok: true, stdout: text)
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            return ToolResult(ok: true, stdout: String(decoding: data, as: UTF8.self))
        }
        return ToolResult(ok: true)
    }

    static func resourceResult(from result: [String: Any], uri: String) -> ToolResult {
        let contents = (result["contents"] as? [[String: Any]]) ?? []
        let text = contents
            .compactMap { item -> String? in
                if let text = item["text"] as? String {
                    return text
                }
                if let blob = item["blob"] as? String {
                    let itemURI = item["uri"] as? String ?? uri
                    let mimeType = item["mimeType"] as? String ?? "binary"
                    return "[\(itemURI) \(mimeType) blob, \(blob.count) base64 characters]"
                }
                return jsonText(from: item)
            }
            .joined(separator: "\n")
        if !text.isEmpty {
            return ToolResult(ok: true, stdout: text, artifacts: [uri])
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            return ToolResult(ok: true, stdout: String(decoding: data, as: UTF8.self), artifacts: [uri])
        }
        return ToolResult(ok: true, artifacts: [uri])
    }

    static func promptResult(from result: [String: Any], name: String) -> ToolResult {
        var lines: [String] = ["Prompt: \(name)"]
        if let description = (result["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            lines.append("Description: \(description)")
        }
        let messages = (result["messages"] as? [[String: Any]]) ?? []
        for message in messages {
            let role = (message["role"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "message"
            let content = promptMessageContent(from: message["content"])
            guard !content.isEmpty else { continue }
            lines.append("\(role): \(content)")
        }
        if lines.count > 1 {
            return ToolResult(ok: true, stdout: lines.joined(separator: "\n"))
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            return ToolResult(ok: true, stdout: String(decoding: data, as: UTF8.self))
        }
        return ToolResult(ok: true)
    }

    private static func firstNonEmptyString(in entry: [String: Any], keys: [String]) -> String? {
        for key in keys {
            let value = (entry[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func schemaArguments(from schema: [String: Any]?) -> (
        required: [String],
        optional: [String],
        summary: String
    ) {
        guard let schema else { return ([], [], "") }
        let requiredNames = ((schema["required"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let requiredSet = Set(requiredNames)
        let properties = (schema["properties"] as? [String: Any]) ?? [:]
        let propertySummaries = properties
            .compactMap { name, value -> (name: String, summary: String, isRequired: Bool)? in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return (
                    name: trimmed,
                    summary: "\(trimmed):\(schemaTypeLabel(from: value))",
                    isRequired: requiredSet.contains(trimmed)
                )
            }

        let required = propertySummaries
            .filter(\.isRequired)
            .sorted { $0.name < $1.name }
        let optional = propertySummaries
            .filter { !$0.isRequired }
            .sorted { $0.name < $1.name }
        let missingRequired = requiredNames
            .filter { name in !propertySummaries.contains { $0.name == name } }
            .sorted()
            .map { (name: $0, summary: "\($0):any", isRequired: true) }

        let requiredSummaries = (required + missingRequired).map(\.summary)
        let optionalSummaries = optional.map(\.summary)
        var parts: [String] = []
        if !requiredSummaries.isEmpty {
            parts.append("required: \(boundedSchemaList(requiredSummaries))")
        }
        if !optionalSummaries.isEmpty {
            parts.append("optional: \(boundedSchemaList(optionalSummaries))")
        }
        return (
            required: (required.map(\.name) + missingRequired.map(\.name)),
            optional: optional.map(\.name),
            summary: parts.joined(separator: "; ")
        )
    }

    private static func schemaTypeLabel(from value: Any) -> String {
        guard let property = value as? [String: Any] else { return "any" }
        if let type = property["type"] as? String,
           !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return type.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let types = property["type"] as? [String],
           let type = types.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return type.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if property["enum"] != nil {
            return "enum"
        }
        if property["items"] != nil {
            return "array"
        }
        if property["properties"] != nil {
            return "object"
        }
        return "any"
    }

    private static func boundedSchemaList(_ summaries: [String]) -> String {
        let visible = summaries.prefix(5)
        let remaining = summaries.count - visible.count
        let joined = visible.joined(separator: ", ")
        guard remaining > 0 else { return joined }
        return "\(joined), +\(remaining) more"
    }

    private static func promptMessageContent(from value: Any?) -> String {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let object = value as? [String: Any] {
            if let text = object["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return jsonText(from: object) ?? ""
        }
        return ""
    }

    private static func jsonText(from item: [String: Any]) -> String? {
        if let text = item["text"] as? String {
            return text
        }
        if let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }
}
