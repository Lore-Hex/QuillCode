import Foundation

extension AppServerSession {
    func spawnProcess(_ value: CLIJSONValue) throws -> String {
        try requireExperimentalAPI(for: "process/spawn")
        let request = try AppServerProcessSpawnRequest(
            params: value,
            inheritedEnvironment: environment
        )
        guard processSessions[request.processHandle] == nil else {
            throw AppServerRPCError.invalidRequest(
                "duplicate active process handle: \(request.processHandle.debugDescription)"
            )
        }

        let session = AppServerProcessSession(request: request)
        processSessions[request.processHandle] = session
        do {
            try session.start()
        } catch {
            processSessions.removeValue(forKey: request.processHandle)
            throw error
        }
        return request.processHandle
    }

    func writeProcessStdin(_ value: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "process/writeStdin")
        let params = try AppServerParams(value)
        let handle = try params.requiredString("processHandle")
        let closeStdin = try params.optionalBool("closeStdin") ?? false
        let encoded = try params.optionalString("deltaBase64")
        guard encoded != nil || closeStdin else {
            throw AppServerRPCError.invalidParams(
                "process/writeStdin requires deltaBase64 or closeStdin"
            )
        }
        let data: Data
        if let encoded {
            guard let decoded = Data(base64Encoded: encoded) else {
                throw AppServerRPCError.invalidParams("invalid deltaBase64")
            }
            data = decoded
        } else {
            data = Data()
        }
        try activeProcess(handle).writeStdin(data, closeStdin: closeStdin)
        return .object([:])
    }

    func resizeProcessPTY(_ value: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "process/resizePty")
        let params = try AppServerParams(value)
        let handle = try params.requiredString("processHandle")
        let size = try AppServerProcessSpawnRequest.terminalSize(from: params, required: true)
        try activeProcess(handle).resizePTY(to: try required(size, name: "size"))
        return .object([:])
    }

    func killProcess(_ value: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "process/kill")
        let handle = try AppServerParams(value).requiredString("processHandle")
        try activeProcess(handle).kill()
        return .object([:])
    }

    func launchProcessEventStream(_ handle: String) {
        guard processEventTasks[handle] == nil, let session = processSessions[handle] else { return }
        processEventTasks[handle] = Task { [weak self] in
            for await event in session.events {
                await self?.receiveProcessEvent(event, handle: handle)
            }
        }
    }

    func terminateAllProcesses() async {
        let sessions = Array(processSessions.values)
        let tasks = Array(processEventTasks.values)
        for session in sessions { session.terminateForDisconnect() }
        for task in tasks { await task.value }
        processSessions.removeAll()
        processEventTasks.removeAll()
    }

    private func receiveProcessEvent(_ event: AppServerProcessEvent, handle: String) async {
        switch event {
        case .output(let stream, let data, let capReached):
            guard !inputFinished else { return }
            await sendNotification("process/outputDelta", params: .object([
                "processHandle": .string(handle),
                "stream": .string(stream.rawValue),
                "deltaBase64": .string(data.base64EncodedString()),
                "capReached": .bool(capReached)
            ]))
        case .exited(let result):
            processSessions.removeValue(forKey: handle)
            processEventTasks.removeValue(forKey: handle)
            guard !inputFinished else { return }
            await sendNotification("process/exited", params: .object([
                "processHandle": .string(handle),
                "exitCode": .number(Double(result.exitCode)),
                "stdout": .string(String(decoding: result.stdout, as: UTF8.self)),
                "stdoutCapReached": .bool(result.stdoutCapReached),
                "stderr": .string(String(decoding: result.stderr, as: UTF8.self)),
                "stderrCapReached": .bool(result.stderrCapReached)
            ]))
        }
    }

    private func activeProcess(_ handle: String) throws -> AppServerProcessSession {
        guard let session = processSessions[handle] else {
            throw AppServerRPCError.invalidRequest(
                "no active process for process handle \(handle.debugDescription)"
            )
        }
        return session
    }

    func requireExperimentalAPI(for method: String) throws {
        guard experimentalAPIEnabled else {
            throw AppServerRPCError.invalidRequest(
                "\(method) requires capabilities.experimentalApi: true"
            )
        }
    }

    private func required<T>(_ value: T?, name: String) throws -> T {
        guard let value else { throw AppServerRPCError.invalidParams("\(name) is required") }
        return value
    }
}
