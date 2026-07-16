import Foundation
import QuillCodeCore
import QuillCodePersistence

struct AppServerTurnInput: Sendable {
    var text: String
    var attachments: [ChatAttachment]
    var inputReferences: [ChatInputReference]
    var clientUserMessageID: String?

    init(
        params: AppServerParams,
        threadID: UUID,
        attachmentStore: ImageAttachmentStore,
        richInputResolver: AppServerRichTurnInputResolver
    ) throws {
        guard let items = try params.optionalArray("input"), !items.isEmpty else {
            throw AppServerRPCError.invalidParams("input must be a non-empty array")
        }

        var textSegments: [String] = []
        var attachments: [ChatAttachment] = []
        var inputReferences: [ChatInputReference] = []
        var selectedSkillPaths = Set<String>()
        var contextBytes = 0
        do {
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
                    try Self.requireImageCapacity(attachments.count)
                    let path = try item.requiredString("path")
                    let source = URL(fileURLWithPath: path).standardizedFileURL
                    let detail = try Self.imageDetail(item, index: index)
                    do {
                        attachments.append(try attachmentStore.importImage(
                            from: source,
                            threadID: threadID,
                            detail: detail
                        ))
                    } catch {
                        throw AppServerRPCError.invalidParams(
                            "input[\(index)] localImage is invalid: \(error.localizedDescription)"
                        )
                    }
                case "image":
                    try Self.requireImageCapacity(attachments.count)
                    let detail = try Self.imageDetail(item, index: index)
                    do {
                        let image = try AppServerImageDataURL(item.requiredString("url"))
                        attachments.append(try attachmentStore.importImage(
                            data: image.data,
                            displayName: image.displayName,
                            threadID: threadID,
                            detail: detail
                        ))
                    } catch {
                        throw AppServerRPCError.invalidParams(
                            "input[\(index)] image is invalid: \(error.localizedDescription)"
                        )
                    }
                case "skill":
                    let reference = try richInputResolver.skill(
                        name: item.requiredString("name"),
                        path: item.requiredString("path")
                    )
                    guard selectedSkillPaths.insert(reference.path).inserted else { continue }
                    try Self.requireReferenceCapacity(inputReferences.count)
                    contextBytes += reference.context?.utf8.count ?? 0
                    guard contextBytes <= AppServerRichTurnInputResolver.maximumContextBytes else {
                        throw AppServerRPCError.invalidParams("selected skill context exceeds the per-turn limit")
                    }
                    inputReferences.append(reference)
                case "mention":
                    try Self.requireReferenceCapacity(inputReferences.count)
                    inputReferences.append(try richInputResolver.mention(
                        name: item.requiredString("name"),
                        path: item.requiredString("path")
                    ))
                default:
                    throw AppServerRPCError.invalidParams("input[\(index)] has unsupported type \(type)")
                }
            }
        } catch {
            attachments.forEach { try? attachmentStore.remove($0) }
            throw error
        }

        let text = textSegments.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty
                || !inputReferences.isEmpty else {
            throw AppServerRPCError.invalidParams("input must contain text, an image, a skill, or a mention")
        }

        self.text = text
        self.attachments = attachments
        self.inputReferences = inputReferences
        self.clientUserMessageID = try params.optionalString("clientUserMessageId")
    }

    func message(turnID: String) -> ChatMessage {
        ChatMessage(
            role: .user,
            content: text,
            attachments: attachments,
            inputReferences: inputReferences,
            turnID: turnID,
            clientMessageID: clientUserMessageID
        )
    }

    private static func requireImageCapacity(_ count: Int) throws {
        guard count < ChatAttachment.maximumCountPerTurn else {
            throw AppServerRPCError.invalidParams(
                "input supports at most \(ChatAttachment.maximumCountPerTurn) images"
            )
        }
    }

    private static func requireReferenceCapacity(_ count: Int) throws {
        guard count < ChatInputReference.maximumCountPerMessage else {
            throw AppServerRPCError.invalidParams(
                "input supports at most \(ChatInputReference.maximumCountPerMessage) skill and mention items"
            )
        }
    }

    private static func imageDetail(_ item: AppServerParams, index: Int) throws -> ChatImageDetail {
        guard let value = try item.optionalString("detail") else { return .auto }
        guard let detail = ChatImageDetail(rawValue: value) else {
            throw AppServerRPCError.invalidParams(
                "input[\(index)].detail must be auto, low, high, or original"
            )
        }
        return detail
    }
}
