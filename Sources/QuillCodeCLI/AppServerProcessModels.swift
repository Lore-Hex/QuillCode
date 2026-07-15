import Foundation

struct AppServerProcessSpawnRequest: Sendable, Equatable {
    static let defaultOutputBytesCap = 1_048_576
    static let defaultTimeoutMilliseconds: Int64 = 10_000

    var command: [String]
    var cwd: URL
    var processHandle: String
    var environment: [String: String]
    var usesPTY: Bool
    var streamsStdin: Bool
    var streamsOutput: Bool
    var outputBytesCap: Int?
    var timeoutMilliseconds: Int64?
    var terminalSize: AppServerProcessTerminalSize?

    init(
        params value: CLIJSONValue,
        inheritedEnvironment: [String: String]
    ) throws {
        let params = try AppServerParams(value)
        command = try Self.command(from: params)
        cwd = try Self.absoluteWorkingDirectory(from: params)
        processHandle = try params.requiredString("processHandle")
        environment = try Self.environment(from: params, inherited: inheritedEnvironment)
        usesPTY = try params.optionalBool("tty") ?? false
        let requestedStdinStreaming = try params.optionalBool("streamStdin") ?? false
        let requestedOutputStreaming = try params.optionalBool("streamStdoutStderr") ?? false
        streamsStdin = usesPTY || requestedStdinStreaming
        streamsOutput = usesPTY || requestedOutputStreaming
        outputBytesCap = try Self.optionalLimit(
            named: "outputBytesCap",
            in: params,
            defaultValue: Self.defaultOutputBytesCap
        )
        timeoutMilliseconds = try Self.optionalInt64(
            named: "timeoutMs",
            in: params,
            defaultValue: Self.defaultTimeoutMilliseconds
        )
        terminalSize = try Self.terminalSize(from: params, required: false)
        if terminalSize != nil, !usesPTY {
            throw AppServerRPCError.invalidParams("process/spawn size requires tty: true")
        }
    }

    private static func command(from params: AppServerParams) throws -> [String] {
        guard let values = params.object["command"]?.arrayValue else {
            throw AppServerRPCError.invalidParams("command must be an array of strings")
        }
        let command = try values.map { value in
            guard let component = value.stringValue else {
                throw AppServerRPCError.invalidParams("command must contain only strings")
            }
            return component
        }
        guard !command.isEmpty else {
            throw AppServerRPCError.invalidRequest("command must not be empty")
        }
        guard !command[0].isEmpty else {
            throw AppServerRPCError.invalidRequest("command program must not be empty")
        }
        return command
    }

    private static func absoluteWorkingDirectory(from params: AppServerParams) throws -> URL {
        let path = try params.requiredString("cwd")
        guard path.hasPrefix("/") else {
            throw AppServerRPCError.invalidParams("cwd must be an absolute path")
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func environment(
        from params: AppServerParams,
        inherited: [String: String]
    ) throws -> [String: String] {
        guard let value = params.object["env"], value != .null else { return inherited }
        guard let overrides = value.objectValue else {
            throw AppServerRPCError.invalidParams("env must be an object or null")
        }
        var result = inherited
        for (name, value) in overrides {
            guard !name.isEmpty, !name.contains("=") else {
                throw AppServerRPCError.invalidParams("env keys must be non-empty names without '='")
            }
            switch value {
            case .string(let text): result[name] = text
            case .null: result.removeValue(forKey: name)
            default:
                throw AppServerRPCError.invalidParams("env values must be strings or null")
            }
        }
        return result
    }

    private static func optionalLimit(
        named name: String,
        in params: AppServerParams,
        defaultValue: Int
    ) throws -> Int? {
        guard let value = params.object[name] else { return defaultValue }
        if value == .null { return nil }
        guard let integer = integer(from: value), integer >= 0, integer <= Int64(Int.max) else {
            throw AppServerRPCError.invalidParams("\(name) must be a non-negative integer or null")
        }
        return Int(integer)
    }

    private static func optionalInt64(
        named name: String,
        in params: AppServerParams,
        defaultValue: Int64
    ) throws -> Int64? {
        guard let value = params.object[name] else { return defaultValue }
        if value == .null { return nil }
        guard let integer = integer(from: value), integer >= 0 else {
            throw AppServerRPCError.invalidParams("\(name) must be a non-negative integer or null")
        }
        return integer
    }

    private static func integer(from value: CLIJSONValue) -> Int64? {
        guard let number = value.numberValue,
              number.isFinite,
              number.rounded() == number,
              number >= Double(Int64.min),
              number <= Double(Int64.max)
        else { return nil }
        return Int64(number)
    }

    static func terminalSize(
        from params: AppServerParams,
        required: Bool
    ) throws -> AppServerProcessTerminalSize? {
        guard let value = params.object["size"] else {
            if required { throw AppServerRPCError.invalidParams("size is required") }
            return nil
        }
        if value == .null {
            if required { throw AppServerRPCError.invalidParams("size must be an object") }
            return nil
        }
        guard let object = value.objectValue else {
            throw AppServerRPCError.invalidParams("size must be an object")
        }
        let size = try AppServerParams(.object(object))
        guard let rows = size.object["rows"].flatMap(integer(from:)),
              let columns = size.object["cols"].flatMap(integer(from:)),
              rows > 0,
              columns > 0,
              rows <= Int64(UInt16.max),
              columns <= Int64(UInt16.max)
        else {
            throw AppServerRPCError.invalidParams(
                "process size rows and cols must be integers greater than 0 and at most \(UInt16.max)"
            )
        }
        return AppServerProcessTerminalSize(rows: UInt16(rows), columns: UInt16(columns))
    }
}

struct AppServerProcessTerminalSize: Sendable, Equatable {
    var rows: UInt16
    var columns: UInt16
}

enum AppServerProcessOutputStream: String, Sendable {
    case stdout
    case stderr
}

enum AppServerProcessEvent: Sendable {
    case output(stream: AppServerProcessOutputStream, data: Data, capReached: Bool)
    case exited(AppServerProcessExit)
}

struct AppServerProcessExit: Sendable, Equatable {
    var exitCode: Int32
    var stdout: Data
    var stdoutCapReached: Bool
    var stderr: Data
    var stderrCapReached: Bool
}
