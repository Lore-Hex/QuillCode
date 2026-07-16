import Foundation

struct AppServerThreadGitInfo: Codable, Sendable, Equatable {
    var sha: String?
    var branch: String?
    var originURL: String?

    private enum CodingKeys: String, CodingKey {
        case sha
        case branch
        case originURL = "originUrl"
    }

    var projection: CLIJSONValue {
        .object([
            "sha": sha.map(CLIJSONValue.string) ?? .null,
            "branch": branch.map(CLIJSONValue.string) ?? .null,
            "originUrl": originURL.map(CLIJSONValue.string) ?? .null
        ])
    }
}

enum AppServerThreadMemoryMode: String, Codable, Sendable, Equatable {
    case enabled
    case disabled
}

enum AppServerThreadSubscriptionMode: Sendable, Equatable {
    case ifNew
    case always
}

struct AppServerCollaborationMode: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case plan
        case `default`
    }

    struct Settings: Codable, Sendable, Equatable {
        var model: String
        var reasoningEffort: String?
        var developerInstructions: String?

        private enum CodingKeys: String, CodingKey {
            case model
            case reasoningEffort = "reasoning_effort"
            case developerInstructions = "developer_instructions"
        }

        var projection: CLIJSONValue {
            .object([
                "model": .string(model),
                "reasoning_effort": reasoningEffort.map(CLIJSONValue.string) ?? .null,
                "developer_instructions": developerInstructions.map(CLIJSONValue.string) ?? .null
            ])
        }
    }

    var mode: Kind
    var settings: Settings

    var projection: CLIJSONValue {
        .object([
            "mode": .string(mode.rawValue),
            "settings": settings.projection
        ])
    }
}

struct AppServerSandboxPolicy: Codable, Sendable, Equatable {
    var mode: CLISandboxMode
    var networkAccess: Bool
    var writableRoots: [String]
    var excludeTemporaryDirectoryEnvironmentVariable: Bool
    var excludeSlashTemporaryDirectory: Bool

    init(
        mode: CLISandboxMode,
        networkAccess: Bool = false,
        writableRoots: [String] = [],
        excludeTemporaryDirectoryEnvironmentVariable: Bool = false,
        excludeSlashTemporaryDirectory: Bool = false
    ) {
        self.mode = mode
        self.networkAccess = networkAccess
        self.writableRoots = writableRoots
        self.excludeTemporaryDirectoryEnvironmentVariable = excludeTemporaryDirectoryEnvironmentVariable
        self.excludeSlashTemporaryDirectory = excludeSlashTemporaryDirectory
    }

    var projection: CLIJSONValue {
        switch mode {
        case .readOnly:
            .object([
                "type": .string("readOnly"),
                "networkAccess": .bool(networkAccess)
            ])
        case .workspaceWrite:
            .object([
                "type": .string("workspaceWrite"),
                "writableRoots": .array(writableRoots.map(CLIJSONValue.string)),
                "networkAccess": .bool(networkAccess),
                "excludeTmpdirEnvVar": .bool(excludeTemporaryDirectoryEnvironmentVariable),
                "excludeSlashTmp": .bool(excludeSlashTemporaryDirectory)
            ])
        case .dangerFullAccess:
            .object(["type": .string("dangerFullAccess")])
        }
    }
}

struct AppServerDeferredNotification: Sendable, Equatable {
    var method: String
    var params: CLIJSONValue
}

struct AppServerThreadSettingsUpdateOutcome: Sendable, Equatable {
    var result: CLIJSONValue
    var notification: AppServerDeferredNotification?
}
