import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension AppServerExecServerWebSocketClient {
    static var requestTimeout: TimeInterval { 30 }
    static var environmentStatusTimeout: TimeInterval { 10 }
    static var maximumMessageBytes: Int { 8 * 1_024 * 1_024 }

    func environmentInfo() async throws -> AppServerEnvironmentInfo {
        let result = try await request(method: "environment/info", params: .null)
        guard let object = result.objectValue,
              let shell = object["shell"]?.objectValue,
              let shellName = shell["name"]?.stringValue,
              let shellPath = shell["path"]?.stringValue,
              Self.isValidProtocolString(shellName),
              Self.isValidProtocolString(shellPath) else {
            throw AppServerExecServerError.invalidResponse(
                "environment/info did not return shell.name and shell.path"
            )
        }
        let cwd: String?
        if let value = object["cwd"], value != .null {
            guard let string = value.stringValue else {
                throw AppServerExecServerError.invalidResponse(
                    "environment/info cwd must be a file URI or null"
                )
            }
            cwd = string
        } else {
            cwd = nil
        }
        return AppServerEnvironmentInfo(
            shell: .init(name: shellName, path: shellPath),
            cwd: cwd
        )
    }

    static func messageData(_ message: URLSessionWebSocketTask.Message) throws -> Data {
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default:
            throw AppServerExecServerError.invalidResponse("unsupported WebSocket message type")
        }
        guard data.count <= maximumMessageBytes else {
            throw AppServerExecServerError.invalidResponse(
                "WebSocket message exceeds \(maximumMessageBytes) bytes"
            )
        }
        return data
    }

    static func redactedURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return "<invalid>" }
        components.user = nil
        components.password = nil
        components.query = components.queryItems?.isEmpty == false ? "<redacted>" : nil
        return components.string ?? "<invalid>"
    }

    static func decodeRequestID(_ value: CLIJSONValue) -> Int64? {
        guard let number = value.numberValue,
              number.isFinite,
              number.rounded() == number,
              number >= Double(Int64.min),
              number < Double(Int64.max) else {
            return nil
        }
        return Int64(number)
    }

    static func errorDetail(_ error: Error) -> String {
        (error as? any LocalizedError)?.errorDescription
            ?? String(describing: error)
    }

    static func decodeConnectionSnapshot(
        _ value: CLIJSONValue
    ) throws -> AppServerEnvironmentConnectionSnapshot {
        guard let object = value.objectValue,
              let rawStatus = object["status"]?.stringValue,
              let status = AppServerEnvironmentStatus(rawValue: rawStatus),
              status != .unknown else {
            throw AppServerExecServerError.invalidResponse(
                "environment/status did not return ready, pending, or disconnected"
            )
        }
        let error: String?
        if let value = object["error"], value != .null {
            guard let detail = value.stringValue else {
                throw AppServerExecServerError.invalidResponse(
                    "environment/status error must be a string or null"
                )
            }
            error = detail
        } else {
            error = nil
        }
        return AppServerEnvironmentConnectionSnapshot(status: status, error: error)
    }

    static func decodeUInt64(
        _ value: Double,
        malformedResponse: String
    ) throws -> UInt64 {
        guard value.isFinite,
              value >= 0,
              value.rounded() == value,
              value < Double(UInt64.max) else {
            throw AppServerExecServerError.invalidResponse(malformedResponse)
        }
        return UInt64(value)
    }

    static func decodeJSONRPCErrorCode(_ value: Double) -> Int? {
        guard value.isFinite,
              value.rounded() == value,
              value >= Double(Int32.min),
              value <= Double(Int32.max) else {
            return nil
        }
        return Int(value)
    }

    static func isValidProtocolString(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.contains("\0")
            && value.rangeOfCharacter(from: .newlines) == nil
    }

    static func isValidDirectoryEntryName(_ value: String) -> Bool {
        isValidProtocolString(value)
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }
}

func appServerDuration(seconds: TimeInterval) -> Duration {
    // A century is effectively unbounded for a process lifetime while remaining comfortably
    // inside ContinuousClock and Duration arithmetic on every supported platform.
    let maximumMilliseconds: Double = 100 * 365.25 * 24 * 60 * 60 * 1_000
    let requestedMilliseconds = max(0, seconds) * 1_000
    let boundedMilliseconds = min(
        requestedMilliseconds.isFinite
            ? requestedMilliseconds.rounded(.up)
            : maximumMilliseconds,
        maximumMilliseconds
    )
    return .milliseconds(Int64(boundedMilliseconds))
}

func appServerWithTimeout<Value: Sendable>(
    operation: String,
    seconds: TimeInterval,
    body: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: body)
        group.addTask {
            try await Task.sleep(for: appServerDuration(seconds: seconds))
            throw AppServerExecServerError.timedOut(operation: operation, seconds: seconds)
        }
        guard let value = try await group.next() else {
            throw AppServerExecServerError.disconnected("timeout race ended without a result")
        }
        group.cancelAll()
        return value
    }
}
