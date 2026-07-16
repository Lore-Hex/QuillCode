import Foundation
import QuillCodeCore

/// Adapts raw Responses API history to TrustedRouter's chat-completions request shape.
///
/// Ordinary message items retain their role, text, and inline images. Other response-item variants
/// remain model-visible as canonical JSON without pretending they are executable chat tool calls.
enum ThreadModelContextPromptProjector {
    static func message(for item: ThreadModelContextItem) -> [String: Any] {
        guard let object = item.responseItem.objectValue,
              object["type"]?.stringValue == "message",
              let role = object["role"]?.stringValue,
              let content = object["content"]?.arrayValue,
              let projectedRole = projectedRole(role)
        else {
            return canonicalContextMessage(item.responseItem)
        }

        let parts = content.compactMap(projectedContent)
        guard !parts.isEmpty else {
            return ["role": projectedRole, "content": ""]
        }
        if parts.allSatisfy({ $0["type"] as? String == "text" }) {
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return ["role": projectedRole, "content": text]
        }
        return ["role": projectedRole, "content": parts]
    }

    private static func projectedRole(_ role: String) -> String? {
        switch role {
        case "system", "user", "assistant":
            return role
        case "developer":
            return "system"
        default:
            return nil
        }
    }

    private static func projectedContent(_ value: QuillJSONValue) -> [String: Any]? {
        guard let object = value.objectValue, let type = object["type"]?.stringValue else {
            return nil
        }
        switch type {
        case "input_text", "output_text":
            guard let text = object["text"]?.stringValue else { return nil }
            return ["type": "text", "text": text]
        case "input_image":
            guard let url = object["image_url"]?.stringValue else { return nil }
            let detail = object["detail"]?.stringValue ?? "high"
            return [
                "type": "image_url",
                "image_url": ["url": url, "detail": detail]
            ]
        default:
            return nil
        }
    }

    private static func canonicalContextMessage(_ value: QuillJSONValue) -> [String: Any] {
        let encoded = (try? JSONEncoder.canonical.encode(value)).map {
            String(decoding: $0, as: UTF8.self)
        } ?? "{}"
        return [
            "role": "assistant",
            "content": "[Injected Responses API context]\n\(encoded)"
        ]
    }
}

private extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
