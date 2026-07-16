import Foundation

extension AppServerSession {
    func updateThreadMetadata(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let reference = try threadControlReference(from: params)
        var record = try await loadThreadControlRecord(reference)
        let patch = try gitInfoPatch(from: params)
        var gitInfo = record.settings.gitInfo ?? AppServerThreadGitInfo()
        patch.apply(to: &gitInfo)
        record.settings.gitInfo = gitInfo
        record.thread.updatedAt = Date()
        try await repository.save(record)
        return .object([
            "thread": projectedThread(
                record,
                includeTurns: false,
                isActive: hasActiveOperation(for: reference.id)
            )
        ])
    }
}

private extension AppServerSession {
    struct GitInfoPatch {
        enum Value {
            case clear
            case replace(String)
        }

        var sha: Value?
        var branch: Value?
        var originURL: Value?

        func apply(to gitInfo: inout AppServerThreadGitInfo) {
            Self.apply(sha, to: &gitInfo.sha)
            Self.apply(branch, to: &gitInfo.branch)
            Self.apply(originURL, to: &gitInfo.originURL)
        }

        private static func apply(_ patch: Value?, to value: inout String?) {
            switch patch {
            case .none:
                break
            case .clear:
                value = nil
            case .replace(let replacement):
                value = replacement
            }
        }
    }

    func gitInfoPatch(from params: AppServerParams) throws -> GitInfoPatch {
        guard let value = params.object["gitInfo"],
              value != .null,
              let object = value.objectValue else {
            throw AppServerRPCError.invalidRequest("gitInfo must include at least one field")
        }
        let supported = ["sha", "branch", "originUrl"]
        guard supported.contains(where: { object[$0] != nil }) else {
            throw AppServerRPCError.invalidRequest("gitInfo must include at least one field")
        }
        return GitInfoPatch(
            sha: try gitInfoValue("sha", in: object),
            branch: try gitInfoValue("branch", in: object),
            originURL: try gitInfoValue("originUrl", in: object)
        )
    }

    func gitInfoValue(
        _ key: String,
        in object: [String: CLIJSONValue]
    ) throws -> GitInfoPatch.Value? {
        guard let value = object[key] else { return nil }
        if value == .null { return .clear }
        guard let string = value.stringValue else {
            throw AppServerRPCError.invalidRequest("gitInfo.\(key) must be a string or null")
        }
        guard !string.isEmpty else {
            throw AppServerRPCError.invalidRequest("gitInfo.\(key) must not be empty")
        }
        return .replace(string)
    }
}
