import Foundation
import QuillCodeCore

enum AppServerThreadProjection {
    static func thread(
        _ record: AppServerThreadRecord,
        includeTurns: Bool,
        isActive: Bool,
        threadFile: URL?
    ) -> CLIJSONValue {
        let value = record.thread
        return .object([
            "id": .string(identifier(value.id)),
            "sessionId": .string(identifier(record.settings.sessionID ?? value.id)),
            "forkedFromId": optionalIdentifier(record.settings.forkedFromID),
            "parentThreadId": .null,
            "preview": .string(preview(value)),
            "ephemeral": .bool(record.settings.ephemeral),
            "modelProvider": .string("trustedrouter"),
            "createdAt": .number(value.createdAt.timeIntervalSince1970.rounded(.down)),
            "updatedAt": .number(value.updatedAt.timeIntervalSince1970.rounded(.down)),
            "recencyAt": .number(value.updatedAt.timeIntervalSince1970.rounded(.down)),
            "status": .object(isActive
                ? ["type": .string("active"), "activeFlags": .array([])]
                : ["type": .string("idle")]),
            "path": threadFile.map { .string($0.path) } ?? .null,
            "cwd": .string(record.settings.cwd.path),
            "cliVersion": .string(QuillCodeCommandRunner.version),
            "source": .string("appServer"),
            "threadSource": .null,
            "agentNickname": .null,
            "agentRole": .null,
            "gitInfo": record.settings.gitInfo?.projection ?? .null,
            "name": record.settings.name.map(CLIJSONValue.string) ?? .null,
            "turns": includeTurns ? .array(AppServerThreadHistoryProjection.turns(record)) : .array([])
        ])
    }

    static func startOrResumeResponse(
        _ record: AppServerThreadRecord,
        includeTurns: Bool,
        isActive: Bool,
        threadFile: URL?
    ) -> CLIJSONValue {
        .object([
            "thread": thread(record, includeTurns: includeTurns, isActive: isActive, threadFile: threadFile),
            "model": .string(record.thread.model),
            "modelProvider": .string("trustedrouter"),
            "serviceTier": record.settings.serviceTier.map(CLIJSONValue.string) ?? .null,
            "cwd": .string(record.settings.cwd.path),
            "runtimeWorkspaceRoots": .array([.string(record.settings.cwd.path)]),
            "instructionSources": .array(record.thread.instructions.map { .string($0.path) }),
            "approvalPolicy": record.settings.approvalPolicy,
            "approvalsReviewer": .string(record.settings.approvalsReviewer),
            "sandbox": record.settings.effectiveSandboxPolicy.projection,
            "activePermissionProfile": activePermissionProfile(record.settings),
            "reasoningEffort": record.settings.reasoningEffort.map(CLIJSONValue.string) ?? .null,
            "multiAgentMode": .string("explicitRequestOnly")
        ])
    }

    static func settings(_ record: AppServerThreadRecord) -> CLIJSONValue {
        let collaboration = record.settings.collaborationMode ?? AppServerCollaborationMode(
            mode: .default,
            settings: .init(
                model: record.thread.model,
                reasoningEffort: record.settings.reasoningEffort,
                developerInstructions: nil
            )
        )
        return .object([
            "model": .string(record.thread.model),
            "modelProvider": .string("trustedrouter"),
            "effort": record.settings.reasoningEffort.map(CLIJSONValue.string) ?? .null,
            "cwd": .string(record.settings.cwd.path),
            "approvalPolicy": record.settings.approvalPolicy,
            "approvalsReviewer": .string(record.settings.approvalsReviewer),
            "sandboxPolicy": record.settings.effectiveSandboxPolicy.projection,
            "activePermissionProfile": activePermissionProfile(record.settings),
            "collaborationMode": collaboration.projection,
            "personality": .string(record.thread.personality.rawValue),
            "serviceTier": record.settings.serviceTier.map(CLIJSONValue.string) ?? .null,
            "summary": record.settings.reasoningSummary.map(CLIJSONValue.string) ?? .null,
            "multiAgentMode": .string("explicitRequestOnly")
        ])
    }

    static func turn(
        id: String,
        items: [CLIJSONValue],
        status: String,
        startedAt: Date?,
        completedAt: Date?,
        error: String? = nil,
        itemsView: String? = nil
    ) -> CLIJSONValue {
        .object([
            "id": .string(id),
            "items": .array(items),
            "itemsView": .string(itemsView ?? (items.isEmpty ? "notLoaded" : "full")),
            "status": .string(status),
            "error": error.map { .object(["message": .string($0), "additionalDetails": .null, "codexErrorInfo": .null]) } ?? .null,
            "startedAt": startedAt.map { .number($0.timeIntervalSince1970.rounded(.down)) } ?? .null,
            "completedAt": completedAt.map { .number($0.timeIntervalSince1970.rounded(.down)) } ?? .null,
            "durationMs": durationMilliseconds(from: startedAt, to: completedAt)
        ])
    }

    static func userMessageItem(_ message: ChatMessage, clientID: String? = nil) -> CLIJSONValue {
        var content: [CLIJSONValue] = []
        if !message.content.isEmpty {
            content.append(.object([
                "type": .string("text"),
                "text": .string(message.content),
                "text_elements": .array([])
            ]))
        }
        content.append(contentsOf: message.attachments.map { attachment in
            .object([
                "type": .string("localImage"),
                "path": .string(attachment.localURL.path),
                "detail": .string(attachment.detail.rawValue)
            ])
        })
        content.append(contentsOf: message.inputReferences.map { reference in
            .object([
                "type": .string(reference.kind.rawValue),
                "name": .string(reference.name),
                "path": .string(reference.path)
            ])
        })
        return .object([
            "type": .string("userMessage"),
            "id": .string(identifier(message.id)),
            "clientId": (clientID ?? message.clientMessageID).map(CLIJSONValue.string) ?? .null,
            "content": .array(content)
        ])
    }

    static func assistantMessageItem(_ message: ChatMessage) -> CLIJSONValue {
        .object([
            "type": .string("agentMessage"),
            "id": .string(identifier(message.id)),
            "text": .string(message.content),
            "phase": .null,
            "memoryCitation": .null
        ])
    }

    static func identifier(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func turnIdentifier(_ userMessageID: UUID) -> String {
        "turn_\(identifier(userMessageID))"
    }

    private static func preview(_ thread: ChatThread) -> String {
        let source = thread.messages.first(where: { $0.role == .user })?.content ?? ""
        return String(source.prefix(160))
    }

    private static func optionalIdentifier(_ id: UUID?) -> CLIJSONValue {
        id.map { .string(identifier($0)) } ?? .null
    }

    private static func activePermissionProfile(_ settings: AppServerThreadSettings) -> CLIJSONValue {
        if settings.permissionProfileIsExplicit == true {
            guard let id = settings.permissionProfileID else { return .null }
            return permissionProfile(id)
        }
        return permissionProfile(permissionProfileID(settings.sandbox))
    }

    private static func permissionProfile(_ id: String) -> CLIJSONValue {
        .object(["id": .string(id), "extends": .null])
    }

    private static func permissionProfileID(_ mode: CLISandboxMode) -> String {
        switch mode {
        case .readOnly:
            ":read-only"
        case .workspaceWrite:
            ":workspace"
        case .dangerFullAccess:
            ":danger-full-access"
        }
    }

    private static func durationMilliseconds(from start: Date?, to end: Date?) -> CLIJSONValue {
        guard let start, let end else { return .null }
        return .number(max(0, end.timeIntervalSince(start) * 1_000).rounded())
    }
}
