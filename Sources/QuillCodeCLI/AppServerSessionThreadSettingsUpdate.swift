import Foundation
import QuillCodeCore
import QuillCodePersistence

extension AppServerSession {
    func updateThreadSettings(
        _ raw: CLIJSONValue
    ) async throws -> AppServerThreadSettingsUpdateOutcome {
        let params = try AppServerParams(raw)
        let reference = try threadControlReference(from: params)
        var record = try await loadThreadControlRecord(reference)
        let original = record
        let requirements = try managedRequirements()

        try applyModel(from: params, to: &record)
        try applyReasoningEffort(from: params, to: &record)
        try applyCWD(from: params, to: &record)
        try applyApprovalSettings(from: params, requirements: requirements, to: &record)
        try applySandboxSettings(from: params, requirements: requirements, to: &record)
        try applyPersonality(from: params, to: &record)
        try applyServiceAndSummary(from: params, to: &record)
        try applyCollaborationMode(from: params, to: &record)
        try validateDeprecatedMultiAgentMode(in: params)
        record.thread.mode = mode(for: record.settings)

        guard record != original else {
            return AppServerThreadSettingsUpdateOutcome(
                result: .object([:]),
                notification: nil
            )
        }
        record.thread.updatedAt = Date()
        try await repository.save(record)
        return AppServerThreadSettingsUpdateOutcome(
            result: .object([:]),
            notification: AppServerDeferredNotification(
                method: "thread/settings/updated",
                params: .object([
                    "threadId": .string(AppServerThreadProjection.identifier(reference.id)),
                    "threadSettings": AppServerThreadProjection.settings(record)
                ])
            )
        )
    }
}

private extension AppServerSession {
    func applyModel(from params: AppServerParams, to record: inout AppServerThreadRecord) throws {
        guard let value = params.object["model"], value != .null else { return }
        guard let model = value.stringValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: model must be a string")
        }
        record.thread.model = model
        if var collaboration = record.settings.collaborationMode {
            collaboration.settings.model = model
            record.settings.collaborationMode = collaboration
        }
    }

    func applyReasoningEffort(
        from params: AppServerParams,
        to record: inout AppServerThreadRecord
    ) throws {
        guard let value = params.object["effort"], value != .null else { return }
        let effort = try nonEmptyReasoningEffort(value)
        record.settings.reasoningEffort = effort
        if var collaboration = record.settings.collaborationMode {
            collaboration.settings.reasoningEffort = effort
            record.settings.collaborationMode = collaboration
        }
    }

    func applyCWD(from params: AppServerParams, to record: inout AppServerThreadRecord) throws {
        guard let value = params.object["cwd"], value != .null else { return }
        guard let rawCWD = value.stringValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: cwd must be a string")
        }
        do {
            record.settings.cwd = try resolvedCWD(rawCWD, fallback: record.settings.cwd)
        } catch let error as AppServerRPCError {
            throw AppServerRPCError.invalidRequest(
                error.message.replacingOccurrences(
                    of: "Invalid params: ",
                    with: "Invalid request: "
                )
            )
        }
    }

    func applyApprovalSettings(
        from params: AppServerParams,
        requirements: ManagedRequirements?,
        to record: inout AppServerThreadRecord
    ) throws {
        if let value = params.object["approvalPolicy"], value != .null {
            do {
                let policy = try approvalPolicy(value) ?? record.settings.approvalPolicy
                try validateManagedApprovalPolicy(policy, against: requirements)
                record.settings.approvalPolicy = policy
            } catch let error as AppServerRPCError {
                throw AppServerRPCError.invalidRequest(
                    error.message.replacingOccurrences(
                        of: "Invalid params: ",
                        with: "Invalid request: "
                    )
                )
            }
        }
        guard let value = params.object["approvalsReviewer"], value != .null else { return }
        guard let reviewer = value.stringValue,
              ["user", "auto_review", "guardian_subagent"].contains(reviewer) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: approvalsReviewer must be `user` or `auto_review`"
            )
        }
        try validateManagedApprovalsReviewer(reviewer, against: requirements)
        record.settings.approvalsReviewer = reviewer == "guardian_subagent"
            ? "auto_review"
            : reviewer
    }

    func applySandboxSettings(
        from params: AppServerParams,
        requirements: ManagedRequirements?,
        to record: inout AppServerThreadRecord
    ) throws {
        let sandboxValue = params.object["sandboxPolicy"]
        let permissionsValue = params.object["permissions"]
        if sandboxValue != nil, sandboxValue != .null,
           permissionsValue != nil, permissionsValue != .null {
            throw AppServerRPCError.invalidRequest(
                "`permissions` cannot be combined with `sandboxPolicy`"
            )
        }
        if let sandboxValue, sandboxValue != .null {
            let policy = try AppServerSandboxPolicyParser.parse(sandboxValue)
            try validateManagedSandboxMode(policy.mode, against: requirements)
            record.settings.sandbox = policy.mode
            record.settings.sandboxPolicy = policy
            record.settings.permissionProfileID = nil
            record.settings.permissionProfileIsExplicit = true
        }
        if let permissionsValue, permissionsValue != .null {
            guard let profileID = permissionsValue.stringValue else {
                throw AppServerRPCError.invalidRequest(
                    "Invalid request: permissions must be a string"
                )
            }
            let mode = try permissionProfileMode(profileID)
            try validateManagedPermissionProfile(profileID, mode: mode, against: requirements)
            record.settings.sandbox = mode
            record.settings.sandboxPolicy = AppServerSandboxPolicy(mode: mode)
            record.settings.permissionProfileID = profileID
            record.settings.permissionProfileIsExplicit = true
        }
    }

    func applyPersonality(
        from params: AppServerParams,
        to record: inout AppServerThreadRecord
    ) throws {
        guard let value = params.object["personality"], value != .null else { return }
        guard let rawPersonality = value.stringValue,
              let personality = QuillCodePersonality(rawValue: rawPersonality) else {
            let raw = value.stringValue ?? "null"
            throw AppServerRPCError.invalidRequest(
                "Invalid request: unknown variant `\(raw)`, expected one of "
                    + "`none`, `friendly`, `pragmatic`"
            )
        }
        record.thread.personality = personality
    }

    func applyServiceAndSummary(
        from params: AppServerParams,
        to record: inout AppServerThreadRecord
    ) throws {
        if let value = params.object["serviceTier"] {
            if value == .null {
                record.settings.serviceTier = "default"
            } else if let serviceTier = value.stringValue {
                record.settings.serviceTier = serviceTier
            } else {
                throw AppServerRPCError.invalidRequest(
                    "Invalid request: serviceTier must be a string or null"
                )
            }
        }
        guard let value = params.object["summary"], value != .null else { return }
        guard let summary = value.stringValue,
              ["auto", "concise", "detailed", "none"].contains(summary) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: unsupported reasoning summary"
            )
        }
        record.settings.reasoningSummary = summary
    }

    func applyCollaborationMode(
        from params: AppServerParams,
        to record: inout AppServerThreadRecord
    ) throws {
        guard let value = params.object["collaborationMode"], value != .null else { return }
        guard let object = value.objectValue,
              let rawMode = object["mode"]?.stringValue,
              let mode = AppServerCollaborationMode.Kind(rawValue: rawMode),
              let settingsObject = object["settings"]?.objectValue,
              let model = settingsObject["model"]?.stringValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: collaborationMode must contain a supported mode "
                    + "and settings.model"
            )
        }
        let reasoningEffort: String?
        if let value = settingsObject["reasoning_effort"], value != .null {
            reasoningEffort = try nonEmptyReasoningEffort(value)
        } else {
            reasoningEffort = nil
        }
        let developerInstructions: String?
        if let value = settingsObject["developer_instructions"], value != .null {
            guard let string = value.stringValue else {
                throw AppServerRPCError.invalidRequest(
                    "Invalid request: developer_instructions must be a string or null"
                )
            }
            developerInstructions = string
        } else {
            developerInstructions = nil
        }
        let collaboration = AppServerCollaborationMode(
            mode: mode,
            settings: .init(
                model: model,
                reasoningEffort: reasoningEffort,
                developerInstructions: developerInstructions
            )
        )
        record.settings.collaborationMode = collaboration
        record.thread.model = model
        if let reasoningEffort {
            record.settings.reasoningEffort = reasoningEffort
        }
    }

    func validateDeprecatedMultiAgentMode(in params: AppServerParams) throws {
        guard let value = params.object["multiAgentMode"], value != .null else { return }
        guard let mode = value.stringValue,
              ["none", "explicitRequestOnly", "proactive"].contains(mode) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: unsupported multiAgentMode"
            )
        }
    }

    func nonEmptyReasoningEffort(_ value: CLIJSONValue) throws -> String {
        guard let effort = value.stringValue,
              !effort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: reasoning_effort must not be empty"
            )
        }
        return effort
    }

}
