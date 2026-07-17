import Foundation
import QuillCodeCore

struct AppServerEnvironmentInfo: Sendable, Equatable {
    struct Shell: Sendable, Equatable {
        var name: String
        var path: String

        var rpcValue: CLIJSONValue {
            .object([
                "name": .string(name),
                "path": .string(path)
            ])
        }
    }

    var shell: Shell
    var cwd: String?

    var rpcValue: CLIJSONValue {
        .object([
            "cwd": cwd.map(CLIJSONValue.string) ?? .null,
            "shell": shell.rpcValue
        ])
    }
}

enum AppServerEnvironmentStatus: String, Sendable, Equatable {
    case ready
    case pending
    case disconnected
    case unknown
}

struct AppServerEnvironmentConnectionSnapshot: Sendable, Equatable {
    var status: AppServerEnvironmentStatus
    var error: String?

    static let ready = Self(status: .ready, error: nil)
    static let pending = Self(status: .pending, error: nil)

    static func disconnected(_ error: String?) -> Self {
        Self(status: .disconnected, error: error)
    }

    var rpcValue: CLIJSONValue {
        .object([
            "error": error.map(CLIJSONValue.string) ?? .null,
            "status": .string(status.rawValue)
        ])
    }

    var isConnected: Bool { status == .ready }
}

struct AppServerThreadEnvironmentSelection: Codable, Sendable, Equatable {
    var environmentID: String
    var cwd: String

    enum CodingKeys: String, CodingKey {
        case environmentID = "environmentId"
        case cwd
    }
}

struct AppServerRemoteProcessRequest: Sendable, Equatable {
    var argv: [String]
    var cwdURI: String
    var environment: [String: String]
    var timeoutSeconds: TimeInterval
}

struct AppServerRemoteProcessResult: Sendable, Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
    var failure: String?
    var sandboxDenied: Bool
}

struct AppServerRemoteFileMetadata: Sendable, Equatable {
    var isDirectory: Bool
    var isFile: Bool
    var isSymbolicLink: Bool
    var size: UInt64
}

struct AppServerRemoteDirectoryEntry: Sendable, Equatable {
    var fileName: String
    var isDirectory: Bool
    var isFile: Bool
}

protocol AppServerExecServerClient: Sendable {
    func connect() async throws
    /// Reports the current environment state without opening or resuming a connection.
    func connectionSnapshot() async -> AppServerEnvironmentConnectionSnapshot
    func environmentInfo() async throws -> AppServerEnvironmentInfo
    func runProcess(_ request: AppServerRemoteProcessRequest) async throws -> AppServerRemoteProcessResult
    func readFile(at pathURI: String) async throws -> Data
    func writeFile(_ data: Data, at pathURI: String) async throws
    func createDirectory(at pathURI: String, recursive: Bool) async throws
    func metadata(at pathURI: String) async throws -> AppServerRemoteFileMetadata
    func canonicalize(_ pathURI: String) async throws -> String
    func readDirectory(at pathURI: String) async throws -> [AppServerRemoteDirectoryEntry]
    func remove(at pathURI: String, recursive: Bool, force: Bool) async throws
    func close() async
}

enum AppServerResolvedEnvironment: Sendable {
    case local(info: AppServerEnvironmentInfo)
    case remote(info: AppServerEnvironmentInfo, client: any AppServerExecServerClient)

    var info: AppServerEnvironmentInfo {
        switch self {
        case .local(let info), .remote(let info, _): info
        }
    }
}

enum AppServerExecServerError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case timedOut(operation: String, seconds: TimeInterval)
    case disconnected(String)
    case invalidResponse(String)
    case remoteRPC(code: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            "exec-server protocol error: unsupported WebSocket URL `\(value)`"
        case .timedOut(let operation, let seconds):
            "exec-server \(operation) timed out after \(Self.durationDescription(seconds))"
        case .disconnected(let detail):
            "exec-server connection failed: \(detail)"
        case .invalidResponse(let detail):
            "exec-server protocol error: \(detail)"
        case .remoteRPC(_, let message):
            "exec-server request failed: \(message)"
        }
    }

    private static func durationDescription(_ seconds: TimeInterval) -> String {
        let rounded = seconds.rounded()
        guard seconds.isFinite,
              rounded == seconds,
              rounded > Double(Int64.min),
              rounded < Double(Int64.max) else {
            return "\(seconds)s"
        }
        return "\(Int64(rounded))s"
    }
}

extension AppServerThreadEnvironmentSelection {
    static func parse(from params: AppServerParams) throws -> [Self]? {
        guard let raw = params.object["environments"], raw != .null else { return nil }
        guard let values = raw.arrayValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid type for `environments`; expected an array"
            )
        }
        return try values.enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw AppServerRPCError.invalidRequest(
                    "Invalid request: environments[\(index)] must be an object"
                )
            }
            guard let environmentValue = object["environmentId"] else {
                throw AppServerRPCError.invalidRequest(
                    "Invalid request: missing field `environmentId`"
                )
            }
            guard let environmentID = environmentValue.stringValue else {
                throw AppServerRPCError.invalidRequest(
                    "Invalid request: `environmentId` must be a string"
                )
            }
            guard let cwdValue = object["cwd"] else {
                throw AppServerRPCError.invalidRequest("Invalid request: missing field `cwd`")
            }
            guard let cwd = cwdValue.stringValue else {
                throw AppServerRPCError.invalidRequest("Invalid request: `cwd` must be a string")
            }
            return Self(environmentID: environmentID, cwd: cwd)
        }
    }
}
