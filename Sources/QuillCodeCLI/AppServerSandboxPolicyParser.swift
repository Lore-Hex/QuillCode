import Foundation

enum AppServerSandboxPolicyParser {
    static func parse(_ value: CLIJSONValue) throws -> AppServerSandboxPolicy {
        guard let object = value.objectValue,
              let type = object["type"]?.stringValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: sandboxPolicy must be an object with a type"
            )
        }
        switch type {
        case "readOnly":
            return AppServerSandboxPolicy(
                mode: .readOnly,
                networkAccess: try boolean("networkAccess", in: object, default: false)
            )
        case "workspaceWrite":
            return AppServerSandboxPolicy(
                mode: .workspaceWrite,
                networkAccess: try boolean("networkAccess", in: object, default: false),
                writableRoots: try writableRoots(in: object),
                excludeTemporaryDirectoryEnvironmentVariable: try boolean(
                    "excludeTmpdirEnvVar",
                    in: object,
                    default: false
                ),
                excludeSlashTemporaryDirectory: try boolean(
                    "excludeSlashTmp",
                    in: object,
                    default: false
                )
            )
        case "dangerFullAccess":
            return AppServerSandboxPolicy(mode: .dangerFullAccess)
        default:
            throw AppServerRPCError.invalidRequest(
                "Invalid request: unsupported sandbox policy `\(type)`"
            )
        }
    }

    private static func writableRoots(
        in object: [String: CLIJSONValue]
    ) throws -> [String] {
        guard let value = object["writableRoots"] else { return [] }
        guard let array = value.arrayValue,
              array.allSatisfy({ $0.stringValue != nil }) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: writableRoots must contain strings"
            )
        }
        return array.compactMap(\.stringValue)
    }

    private static func boolean(
        _ key: String,
        in object: [String: CLIJSONValue],
        default defaultValue: Bool
    ) throws -> Bool {
        guard let value = object[key] else { return defaultValue }
        guard let boolean = value.boolValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: \(key) must be a boolean"
            )
        }
        return boolean
    }
}
