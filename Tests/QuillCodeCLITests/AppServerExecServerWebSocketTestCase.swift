@testable import QuillCodeCLI
import QuillCodePlatform
import XCTest

class AppServerExecServerWebSocketTestCase: XCTestCase {
    static var info: AppServerEnvironmentInfo {
        .init(
            shell: .init(name: "zsh", path: "/bin/zsh"),
            cwd: "file:///workspace"
        )
    }

    static var infoValue: CLIJSONValue {
        .object([
            "shell": .object([
                "name": .string("zsh"),
                "path": .string("/bin/zsh")
            ]),
            "cwd": .string("file:///workspace")
        ])
    }

    static func sandbox() throws -> AppServerExecServerSandboxContext {
        try AppServerExecServerSandboxContext(
            policy: .init(mode: .readOnly),
            workspace: .init(cwd: "/workspace", fallbackCWDURI: nil)
        )
    }

    static func assertSandbox(
        _ sandbox: AppServerExecServerSandboxContext,
        on request: [String: CLIJSONValue],
        method: String
    ) throws {
        XCTAssertEqual(request["method"]?.stringValue, method)
        XCTAssertEqual(
            try XCTUnwrap(request["params"]?.objectValue?["sandbox"]),
            sandbox.rpcValue
        )
    }

    static func acceptPeer(
        _ connection: any SocketByteConnection
    ) async throws -> ExecServerLoopbackPeer {
        let reader = AppServerWebSocketReader(
            connection: connection,
            maximumMessageBytes: 1_048_576
        )
        let writer = AppServerWebSocketWriter(connection: connection)
        let request = try await reader.readHTTPRequest()
        let key = try XCTUnwrap(request.header("sec-websocket-key"))
        try await writer.acceptUpgrade(key: key)
        return .init(reader: reader, writer: writer)
    }
}

struct ExecServerLoopbackPeer: Sendable {
    var reader: AppServerWebSocketReader
    var writer: AppServerWebSocketWriter

    func readJSON() async throws -> [String: CLIJSONValue] {
        while true {
            switch try await reader.receiveEvent() {
            case .text(let data):
                guard let object = try CLIJSONCodec.decode(data).objectValue else {
                    throw ExecServerLoopbackError.invalidJSONEnvelope
                }
                return object
            case .ping(let data):
                try await writer.sendPong(data)
            case .binary:
                throw ExecServerLoopbackError.expectedTextFrame
            case .close:
                throw ExecServerLoopbackError.closed
            case .pong:
                continue
            }
        }
    }

    func respond(
        to request: [String: CLIJSONValue],
        result: CLIJSONValue
    ) async throws {
        guard let id = request["id"] else {
            throw ExecServerLoopbackError.missingRequestID
        }
        try await writer.sendText(try CLIJSONCodec.encode(.object([
            "id": id,
            "result": result
        ])))
    }

    func respond(
        to request: [String: CLIJSONValue],
        errorCode: Double,
        message: String
    ) async throws {
        guard let id = request["id"] else {
            throw ExecServerLoopbackError.missingRequestID
        }
        try await writer.sendText(try CLIJSONCodec.encode(.object([
            "id": id,
            "error": .object([
                "code": .number(errorCode),
                "message": .string(message)
            ])
        ])))
    }

    func completeHandshake(sessionID: String) async throws {
        let initialize = try await readJSON()
        guard initialize["method"]?.stringValue == "initialize" else {
            throw ExecServerLoopbackError.expectedInitialize
        }
        try await respond(to: initialize, result: .object([
            "sessionId": .string(sessionID)
        ]))
        let initialized = try await readJSON()
        guard initialized["method"]?.stringValue == "initialized" else {
            throw ExecServerLoopbackError.expectedInitialized
        }
    }
}

enum ExecServerLoopbackError: Error {
    case invalidJSONEnvelope
    case expectedTextFrame
    case closed
    case missingRequestID
    case expectedInitialize
    case expectedInitialized
}
