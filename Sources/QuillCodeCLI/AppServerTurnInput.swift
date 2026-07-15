import Foundation
import QuillCodeCore
import QuillCodePersistence

struct AppServerTurnInput: Sendable {
    var text: String
    var attachments: [ChatAttachment]
    var clientUserMessageID: String?

    init(
        params: AppServerParams,
        threadID: UUID,
        attachmentStore: ImageAttachmentStore
    ) throws {
        guard let items = try params.optionalArray("input"), !items.isEmpty else {
            throw AppServerRPCError.invalidParams("input must be a non-empty array")
        }

        var textSegments: [String] = []
        var attachments: [ChatAttachment] = []
        for (index, value) in items.enumerated() {
            let item = try AppServerParams(value)
            let type = try item.requiredString("type")
            switch type {
            case "text":
                guard let text = item.object["text"]?.stringValue else {
                    throw AppServerRPCError.invalidParams("input[\(index)].text must be a string")
                }
                textSegments.append(text)
            case "localImage":
                guard attachments.count < ChatAttachment.maximumCountPerTurn else {
                    throw AppServerRPCError.invalidParams(
                        "input supports at most \(ChatAttachment.maximumCountPerTurn) images"
                    )
                }
                let path = try item.requiredString("path")
                let source = URL(fileURLWithPath: path).standardizedFileURL
                do {
                    attachments.append(try attachmentStore.importImage(from: source, threadID: threadID))
                } catch {
                    throw AppServerRPCError.invalidParams(
                        "input[\(index)] localImage is invalid: \(error.localizedDescription)"
                    )
                }
            case "image":
                throw AppServerRPCError.invalidParams(
                    "remote image input is not supported yet; provide a localImage path"
                )
            case "skill", "mention":
                throw AppServerRPCError.invalidParams("\(type) input is not supported yet")
            default:
                throw AppServerRPCError.invalidParams("input[\(index)] has unsupported type \(type)")
            }
        }

        let text = textSegments.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else {
            throw AppServerRPCError.invalidParams("input must contain text or a local image")
        }

        self.text = text
        self.attachments = attachments
        self.clientUserMessageID = try params.optionalString("clientUserMessageId")
    }

    func message() -> ChatMessage {
        ChatMessage(role: .user, content: text, attachments: attachments)
    }
}
