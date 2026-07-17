import Foundation

struct AppServerCommandExecRequest: Sendable, Equatable {
    var processID: String?
    var sessionHandle: String
    var processRequest: AppServerProcessSpawnRequest

    init(
        params value: CLIJSONValue,
        cwd: URL,
        inheritedEnvironment: [String: String],
        sandboxPolicy: AppServerSandboxPolicy
    ) throws {
        let params = try AppServerParams(value)
        let processID = try Self.optionalProcessID(from: params)
        let tty = try params.optionalBool("tty") ?? false
        let streamStdin = try params.optionalBool("streamStdin") ?? false
        let streamOutput = try params.optionalBool("streamStdoutStderr") ?? false
        if (tty || streamStdin || streamOutput), processID == nil {
            throw AppServerRPCError.invalidRequest(
                "command/exec tty or streaming requires a client-supplied processId"
            )
        }
        let terminalSize = try AppServerProcessSpawnRequest.terminalSize(
            from: params,
            required: false,
            errorPrefix: "command/exec"
        )
        if terminalSize != nil, !tty {
            throw AppServerCommandExecError.invalidParams(
                "command/exec size requires tty: true"
            )
        }

        let disablesOutputCap = try params.optionalBool("disableOutputCap") ?? false
        if disablesOutputCap, params.object["outputBytesCap"] != nil,
           params.object["outputBytesCap"] != .null {
            throw AppServerCommandExecError.invalidParams(
                "command/exec cannot set both outputBytesCap and disableOutputCap"
            )
        }
        let disablesTimeout = try params.optionalBool("disableTimeout") ?? false
        if disablesTimeout, params.object["timeoutMs"] != nil,
           params.object["timeoutMs"] != .null {
            throw AppServerCommandExecError.invalidParams(
                "command/exec cannot set both timeoutMs and disableTimeout"
            )
        }
        if let timeout = try params.optionalInt("timeoutMs"), timeout < 0 {
            throw AppServerCommandExecError.invalidParams(
                "command/exec timeoutMs must be non-negative, got \(timeout)"
            )
        }

        let handle = "command-exec-\(UUID().uuidString.lowercased())"
        var spawnParams = params.object
        spawnParams["cwd"] = .string(cwd.path)
        spawnParams["processHandle"] = .string(handle)
        if disablesOutputCap { spawnParams["outputBytesCap"] = .null }
        if disablesTimeout { spawnParams["timeoutMs"] = .null }

        self.processID = processID
        self.sessionHandle = handle
        self.processRequest = try AppServerProcessSpawnRequest(
            params: .object(spawnParams),
            inheritedEnvironment: inheritedEnvironment,
            sandboxPolicy: sandboxPolicy
        )
    }

    static func requiredProcessID(from params: AppServerParams) throws -> String {
        try params.requiredString("processId")
    }

    private static func optionalProcessID(from params: AppServerParams) throws -> String? {
        guard let processID = try params.optionalString("processId") else { return nil }
        guard !processID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppServerCommandExecError.invalidParams(
                "processId must be a non-empty string or null"
            )
        }
        return processID
    }
}

struct AppServerActiveCommandExec: Sendable {
    var requestID: AppServerRequestID
    var processID: String?
    var session: AppServerProcessSession
}

enum AppServerCommandExecError {
    static func invalidParams(_ message: String) -> AppServerRPCError {
        AppServerRPCError(code: -32_602, message: message)
    }

    static func noActiveProcess(_ processID: String) -> AppServerRPCError {
        .invalidRequest(
            "no active command/exec for process id \(processID.debugDescription)"
        )
    }

    static func noLongerRunning(_ processID: String) -> AppServerRPCError {
        .invalidRequest("command/exec \(processID.debugDescription) is no longer running")
    }
}
