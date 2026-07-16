import Foundation

extension AppServerSession {
    func startCommandExec(id: AppServerRequestID, params value: CLIJSONValue) throws {
        try requireExperimentalAPI(for: "command/exec")
        let params = try AppServerParams(value)
        let cwd = try resolvedCWD(try params.optionalString("cwd"), fallback: currentDirectory)
        let sandboxPolicy = try commandExecSandboxPolicy(from: params, cwd: cwd)
        let request = try AppServerCommandExecRequest(
            params: value,
            cwd: cwd,
            inheritedEnvironment: environment,
            sandboxPolicy: sandboxPolicy
        )
        let registryKey = request.processID ?? request.sessionHandle
        if let processID = request.processID, commandExecSessions[registryKey] != nil {
            throw AppServerRPCError.invalidRequest(
                "duplicate active command/exec process id: \(processID.debugDescription)"
            )
        }

        let processSession = AppServerProcessSession(request: request.processRequest)
        commandExecSessions[registryKey] = AppServerActiveCommandExec(
            requestID: id,
            processID: request.processID,
            session: processSession
        )
        do {
            try processSession.start()
        } catch {
            commandExecSessions.removeValue(forKey: registryKey)
            throw error
        }
        launchCommandExecEventStream(registryKey: registryKey, session: processSession)
    }

    func writeCommandExec(_ value: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "command/exec/write")
        let params = try AppServerParams(value)
        let processID = try params.requiredString("processId", allowingEmpty: true)
        let closeStdin = try params.optionalBool("closeStdin") ?? false
        let encoded = try params.optionalString("deltaBase64")
        guard encoded != nil || closeStdin else {
            throw AppServerCommandExecError.invalidParams(
                "command/exec/write requires deltaBase64 or closeStdin"
            )
        }
        let data: Data
        if let encoded {
            guard let decoded = Data(base64Encoded: encoded) else {
                throw AppServerCommandExecError.invalidParams("invalid deltaBase64")
            }
            data = decoded
        } else {
            data = Data()
        }

        do {
            try activeCommandExec(processID).writeStdin(data, closeStdin: closeStdin)
        } catch let error as AppServerRPCError {
            throw translatedCommandExecError(error, processID: processID)
        }
        return .object([:])
    }

    func resizeCommandExec(_ value: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "command/exec/resize")
        let params = try AppServerParams(value)
        let processID = try params.requiredString("processId", allowingEmpty: true)
        let size = try AppServerProcessSpawnRequest.terminalSize(
            from: params,
            required: true,
            errorPrefix: "command/exec"
        )
        do {
            try activeCommandExec(processID).resizePTY(to: try requiredCommandExecSize(size))
        } catch let error as AppServerRPCError {
            throw translatedCommandExecError(error, processID: processID)
        }
        return .object([:])
    }

    func terminateCommandExec(_ value: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "command/exec/terminate")
        let processID = try AppServerParams(value).requiredString(
            "processId",
            allowingEmpty: true
        )
        do {
            try activeCommandExec(processID).kill()
        } catch let error as AppServerRPCError {
            throw translatedCommandExecError(error, processID: processID)
        }
        return .object([:])
    }

    func terminateAllCommandExecProcesses() async {
        let sessions = commandExecSessions.values.map(\.session)
        let tasks = Array(commandExecEventTasks.values)
        for session in sessions { session.terminateForDisconnect() }
        for task in tasks { await task.value }
        commandExecSessions.removeAll()
        commandExecEventTasks.removeAll()
    }

    private func launchCommandExecEventStream(
        registryKey: String,
        session: AppServerProcessSession
    ) {
        commandExecEventTasks[registryKey] = Task { [weak self] in
            for await event in session.events {
                await self?.receiveCommandExecEvent(event, registryKey: registryKey)
            }
        }
    }

    private func receiveCommandExecEvent(
        _ event: AppServerProcessEvent,
        registryKey: String
    ) async {
        guard let active = commandExecSessions[registryKey] else { return }
        switch event {
        case .output(let stream, let data, let capReached):
            guard !inputFinished, let processID = active.processID else { return }
            await sendNotification("command/exec/outputDelta", params: .object([
                "processId": .string(processID),
                "stream": .string(stream.rawValue),
                "deltaBase64": .string(data.base64EncodedString()),
                "capReached": .bool(capReached)
            ]))
        case .exited(let result):
            commandExecSessions.removeValue(forKey: registryKey)
            commandExecEventTasks.removeValue(forKey: registryKey)
            guard !inputFinished else { return }
            await send(.response(id: active.requestID, result: .object([
                "exitCode": .number(Double(result.exitCode)),
                "stdout": .string(String(decoding: result.stdout, as: UTF8.self)),
                "stderr": .string(String(decoding: result.stderr, as: UTF8.self))
            ])))
        }
    }

    private func activeCommandExec(_ processID: String) throws -> AppServerProcessSession {
        guard let active = commandExecSessions[processID] else {
            throw AppServerCommandExecError.noActiveProcess(processID)
        }
        return active.session
    }

    private func translatedCommandExecError(
        _ error: AppServerRPCError,
        processID: String
    ) -> AppServerRPCError {
        if error.message.contains(" is no longer running") {
            return AppServerCommandExecError.noLongerRunning(processID)
        }
        if error.message == "stdin streaming is not enabled for this process" {
            return .invalidRequest("stdin streaming is not enabled for this command/exec")
        }
        return error
    }

    private func requiredCommandExecSize(
        _ size: AppServerProcessTerminalSize?
    ) throws -> AppServerProcessTerminalSize {
        guard let size else {
            throw AppServerCommandExecError.invalidParams("command/exec size is required")
        }
        return size
    }

    private func commandExecSandboxPolicy(
        from params: AppServerParams,
        cwd: URL
    ) throws -> AppServerSandboxPolicy {
        let sandboxValue = params.object["sandboxPolicy"]
        let permissionProfileValue = params.object["permissionProfile"]
        if sandboxValue != nil, sandboxValue != .null,
           permissionProfileValue != nil, permissionProfileValue != .null {
            throw AppServerRPCError.invalidRequest(
                "`permissionProfile` cannot be combined with `sandboxPolicy`"
            )
        }

        if let sandboxValue, sandboxValue != .null {
            let policy = try AppServerSandboxPolicyParser.parse(sandboxValue)
            return try normalizedCommandExecPolicy(policy, workspaceRoot: currentDirectory)
        }
        if let permissionProfile = try params.optionalString("permissionProfile") {
            return try commandExecPermissionProfile(permissionProfile, cwd: cwd)
        }

        switch appConfig.mode {
        case .readOnly, .plan:
            return AppServerSandboxPolicy(mode: .readOnly)
        case .review, .auto:
            return AppServerSandboxPolicy(
                mode: .workspaceWrite,
                writableRoots: [currentDirectory.path]
            )
        }
    }

    private func commandExecPermissionProfile(
        _ identifier: String,
        cwd: URL
    ) throws -> AppServerSandboxPolicy {
        switch identifier {
        case ":read-only":
            return AppServerSandboxPolicy(mode: .readOnly)
        case ":workspace":
            return AppServerSandboxPolicy(mode: .workspaceWrite, writableRoots: [cwd.path])
        case ":danger-full-access":
            return AppServerSandboxPolicy(mode: .dangerFullAccess)
        default:
            throw AppServerRPCError.invalidRequest(
                "invalid permission profile: failed to load configuration: default_permissions "
                    + "refers to unknown built-in profile `\(identifier)`"
            )
        }
    }

    private func normalizedCommandExecPolicy(
        _ policy: AppServerSandboxPolicy,
        workspaceRoot: URL
    ) throws -> AppServerSandboxPolicy {
        guard policy.mode == .workspaceWrite else { return policy }
        var normalized = policy
        normalized.writableRoots = try ([workspaceRoot.path] + policy.writableRoots).flatMap { path in
            let candidate = NSString(string: path).isAbsolutePath
                ? URL(fileURLWithPath: path, isDirectory: true)
                : workspaceRoot.appendingPathComponent(path, isDirectory: true)
            let standardized = candidate.standardizedFileURL
            let resolved = standardized.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: standardized.path,
                isDirectory: &isDirectory
            ),
                  isDirectory.boolValue else {
                throw AppServerRPCError.invalidRequest(
                    "invalid sandbox policy: writable root must name an existing directory"
                )
            }
            return [standardized.path, resolved.path]
        }
        normalized.writableRoots = Array(Set(normalized.writableRoots)).sorted()
        return normalized
    }
}
