import Foundation
@testable import QuillCodeCLI
import QuillCodePlatform
import XCTest

final class AppServerExecServerWebSocketClientTests: AppServerExecServerWebSocketTestCase {
    func testRealWebSocketHandshakeInfoAndProcessRoundTrip() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            let initialize = try await peer.readJSON()
            XCTAssertEqual(initialize["method"]?.stringValue, "initialize")
            XCTAssertEqual(
                initialize["params"]?.objectValue?["clientName"]?.stringValue,
                "quillcode-environment"
            )
            XCTAssertEqual(
                initialize["params"]?.objectValue?["resumeSessionId"],
                .null
            )
            try await peer.respond(to: initialize, result: .object([
                "sessionId": .string("session-1")
            ]))
            let initialized = try await peer.readJSON()
            XCTAssertEqual(initialized["method"]?.stringValue, "initialized")

            let info = try await peer.readJSON()
            XCTAssertEqual(info["method"]?.stringValue, "environment/info")
            try await peer.respond(to: info, result: Self.infoValue)

            let start = try await peer.readJSON()
            XCTAssertEqual(start["method"]?.stringValue, "process/start")
            let processID = try XCTUnwrap(
                start["params"]?.objectValue?["processId"]?.stringValue
            )
            XCTAssertEqual(
                start["params"]?.objectValue?["argv"]?.arrayValue?.compactMap(\.stringValue),
                ["/bin/zsh", "-lc", "whoami"]
            )
            XCTAssertEqual(
                start["params"]?.objectValue?["sandbox"],
                try Self.sandbox().rpcValue
            )
            XCTAssertEqual(
                start["params"]?.objectValue?["enforceManagedNetwork"],
                .bool(false)
            )
            XCTAssertEqual(start["params"]?.objectValue?["managedNetwork"], .null)
            try await peer.respond(to: start, result: .object([
                "processId": .string(processID)
            ]))

            let read = try await peer.readJSON()
            XCTAssertEqual(read["method"]?.stringValue, "process/read")
            try await peer.respond(to: read, result: .object([
                "chunks": .array([
                    .object([
                        "seq": .number(1),
                        "stream": .string("stdout"),
                        "chunk": .string(Data("quill\n".utf8).base64EncodedString())
                    ])
                ]),
                "nextSeq": .number(2),
                "exited": .bool(true),
                "exitCode": .number(0),
                "closed": .bool(true),
                "failure": .null,
                "sandboxDenied": .bool(false)
            ]))
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            let info = try await client.environmentInfo()
            XCTAssertEqual(info, Self.info)
            let process = try await client.runProcess(.init(
                argv: ["/bin/zsh", "-lc", "whoami"],
                cwdURI: "file:///workspace",
                environment: [:],
                sandbox: try Self.sandbox(),
                timeoutSeconds: 2
            ))
            XCTAssertEqual(process.stdout, "quill\n")
            XCTAssertEqual(process.exitCode, 0)
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testFileSystemRequestsForwardSandboxContext() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let sandbox = try Self.sandbox()
        let server = Task.detached { @Sendable [listener, sandbox] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "filesystem-session")

            let read = try await peer.readJSON()
            try Self.assertSandbox(sandbox, on: read, method: "fs/readFile")
            try await peer.respond(to: read, result: .object([
                "dataBase64": .string(Data("hello".utf8).base64EncodedString())
            ]))

            let write = try await peer.readJSON()
            try Self.assertSandbox(sandbox, on: write, method: "fs/writeFile")
            try await peer.respond(to: write, result: .object([:]))

            let create = try await peer.readJSON()
            try Self.assertSandbox(sandbox, on: create, method: "fs/createDirectory")
            try await peer.respond(to: create, result: .object([:]))

            let metadata = try await peer.readJSON()
            try Self.assertSandbox(sandbox, on: metadata, method: "fs/getMetadata")
            try await peer.respond(to: metadata, result: .object([
                "isDirectory": .bool(false),
                "isFile": .bool(true),
                "isSymlink": .bool(false),
                "size": .number(5)
            ]))

            let canonicalize = try await peer.readJSON()
            try Self.assertSandbox(sandbox, on: canonicalize, method: "fs/canonicalize")
            try await peer.respond(to: canonicalize, result: .object([
                "path": .string("file:///workspace/file.txt")
            ]))

            let directory = try await peer.readJSON()
            try Self.assertSandbox(sandbox, on: directory, method: "fs/readDirectory")
            try await peer.respond(to: directory, result: .object([
                "entries": .array([])
            ]))

            let remove = try await peer.readJSON()
            try Self.assertSandbox(sandbox, on: remove, method: "fs/remove")
            try await peer.respond(to: remove, result: .object([:]))
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            let path = "file:///workspace/file.txt"
            let data = try await client.readFile(at: path, sandbox: sandbox)
            XCTAssertEqual(data, Data("hello".utf8))
            try await client.writeFile(Data("hello".utf8), at: path, sandbox: sandbox)
            try await client.createDirectory(
                at: "file:///workspace/new",
                recursive: true,
                sandbox: sandbox
            )
            let metadata = try await client.metadata(at: path, sandbox: sandbox)
            XCTAssertEqual(metadata.size, 5)
            let canonicalPath = try await client.canonicalize(path, sandbox: sandbox)
            XCTAssertEqual(canonicalPath, path)
            let entries = try await client.readDirectory(
                at: "file:///workspace",
                sandbox: sandbox
            )
            XCTAssertEqual(entries, [])
            try await client.remove(
                at: path,
                recursive: false,
                force: false,
                sandbox: sandbox
            )
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testConnectionSnapshotProbesExistingSocketAndNeverReconnects() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "status-session")
            let status = try await peer.readJSON()
            XCTAssertEqual(status["method"]?.stringValue, "environment/status")
            try await peer.respond(to: status, result: .object([
                "error": .null,
                "status": .string("ready")
            ]))
            try await peer.writer.sendClose()
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            let initial = await client.connectionSnapshot()
            XCTAssertEqual(initial, .pending)
            try await client.connect()
            let ready = await client.connectionSnapshot()
            XCTAssertEqual(ready, .ready)
            try await server.value

            let disconnected = await client.connectionSnapshot()
            XCTAssertEqual(disconnected.status, .disconnected)
            XCTAssertNotNil(disconnected.error)
            let stillDisconnected = await client.connectionSnapshot()
            XCTAssertEqual(stillDisconnected.status, .disconnected)
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testConfiguredConnectTimeoutBoundsInitializeHandshake() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            let initialize = try await peer.readJSON()
            XCTAssertEqual(initialize["method"]?.stringValue, "initialize")
            try await Task.sleep(for: .milliseconds(150))
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 0.02
        )

        do {
            do {
                _ = try await client.environmentInfo()
                XCTFail("The initialize handshake must honor connectTimeout")
            } catch let error as AppServerExecServerError {
                XCTAssertEqual(error, .timedOut(operation: "response", seconds: 0.02))
            }
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testProcessReadsAdvanceWithLastObservedSequenceWithoutSkippingOutput() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "cursor-session")

            let start = try await peer.readJSON()
            let processID = try XCTUnwrap(
                start["params"]?.objectValue?["processId"]?.stringValue
            )
            try await peer.respond(to: start, result: .object([
                "processId": .string(processID)
            ]))

            let firstRead = try await peer.readJSON()
            XCTAssertEqual(firstRead["method"]?.stringValue, "process/read")
            XCTAssertEqual(firstRead["params"]?.objectValue?["afterSeq"], .null)
            try await peer.respond(to: firstRead, result: .object([
                "chunks": .array([
                    .object([
                        "seq": .number(1),
                        "stream": .string("stdout"),
                        "chunk": .string(Data("first\n".utf8).base64EncodedString())
                    ])
                ]),
                "nextSeq": .number(2),
                "exited": .bool(false),
                "closed": .bool(false)
            ]))

            let secondRead = try await peer.readJSON()
            XCTAssertEqual(secondRead["method"]?.stringValue, "process/read")
            XCTAssertEqual(
                secondRead["params"]?.objectValue?["afterSeq"]?.numberValue,
                1
            )
            try await peer.respond(to: secondRead, result: .object([
                "chunks": .array([]),
                "nextSeq": .number(3),
                "exited": .bool(true),
                "exitCode": .number(0),
                "closed": .bool(false),
                "failure": .null,
                "sandboxDenied": .bool(false)
            ]))

            let terminalRead = try await peer.readJSON()
            XCTAssertEqual(
                terminalRead["params"]?.objectValue?["afterSeq"]?.numberValue,
                2
            )
            try await peer.respond(to: terminalRead, result: .object([
                "chunks": .array([
                    .object([
                        "seq": .number(3),
                        "stream": .string("stderr"),
                        "chunk": .string(Data("late\n".utf8).base64EncodedString())
                    ])
                ]),
                "nextSeq": .number(4),
                "exited": .bool(true),
                "exitCode": .number(0),
                "closed": .bool(false),
                "failure": .null,
                "sandboxDenied": .bool(false)
            ]))

            let closedRead = try await peer.readJSON()
            XCTAssertEqual(
                closedRead["params"]?.objectValue?["afterSeq"]?.numberValue,
                3
            )
            try await peer.respond(to: closedRead, result: .object([
                "chunks": .array([]),
                "nextSeq": .number(5),
                "exited": .bool(true),
                "exitCode": .number(0),
                "closed": .bool(true),
                "failure": .null,
                "sandboxDenied": .bool(false)
            ]))
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            let process = try await client.runProcess(.init(
                argv: ["/bin/zsh", "-lc", "printf output"],
                cwdURI: "file:///workspace",
                environment: [:],
                sandbox: try Self.sandbox(),
                timeoutSeconds: 2
            ))
            XCTAssertEqual(process.stdout, "first\n")
            XCTAssertEqual(process.stderr, "late\n")
            XCTAssertEqual(process.exitCode, 0)
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testConcurrentRPCsRouteResponsesAndReconnectResumesSession() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let requestCount = 24
        let server = Task.detached { @Sendable [listener, requestCount] in
            let firstConnection = try await listener.accept()
            let firstPeer = try await Self.acceptPeer(firstConnection)
            let firstInitialize = try await firstPeer.readJSON()
            try await firstPeer.respond(to: firstInitialize, result: .object([
                "sessionId": .string("session-1")
            ]))
            _ = try await firstPeer.readJSON()
            for _ in 0..<requestCount {
                let request = try await firstPeer.readJSON()
                XCTAssertEqual(request["method"]?.stringValue, "environment/info")
                try await firstPeer.respond(to: request, result: Self.infoValue)
            }
            try await firstPeer.writer.sendClose()
            firstConnection.close()

            let secondConnection = try await listener.accept()
            defer { secondConnection.close() }
            let secondPeer = try await Self.acceptPeer(secondConnection)
            let secondInitialize = try await secondPeer.readJSON()
            XCTAssertEqual(
                secondInitialize["params"]?.objectValue?["resumeSessionId"]?.stringValue,
                "session-1"
            )
            try await secondPeer.respond(to: secondInitialize, result: .object([
                "sessionId": .string("session-2")
            ]))
            _ = try await secondPeer.readJSON()
            let info = try await secondPeer.readJSON()
            try await secondPeer.respond(to: info, result: Self.infoValue)
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )
        let connectionEvents = await client.connectionEvents()

        do {
            let values = try await withThrowingTaskGroup(
                of: AppServerEnvironmentInfo.self,
                returning: [AppServerEnvironmentInfo].self
            ) { group in
                for _ in 0..<requestCount {
                    group.addTask { try await client.environmentInfo() }
                }
                var values: [AppServerEnvironmentInfo] = []
                for try await value in group { values.append(value) }
                return values
            }
            XCTAssertEqual(values, Array(repeating: Self.info, count: requestCount))
            var eventIterator = connectionEvents.makeAsyncIterator()
            let connectedEvent = await eventIterator.next()
            let disconnectedEvent = await eventIterator.next()
            XCTAssertEqual(connectedEvent?.state, .connected)
            XCTAssertEqual(disconnectedEvent?.state, .disconnected)

            // The transport observed closure before this operation was dispatched, so reconnecting
            // is safe. Requests lost after dispatch still fail without replay.
            let reconnectedInfo = try await client.environmentInfo()
            XCTAssertEqual(reconnectedInfo, Self.info)
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testStatusProbeUsesExistingConnectionAndIdleClosePublishesFutureTransitions() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "status-session")
            let status = try await peer.readJSON()
            XCTAssertEqual(status["method"]?.stringValue, "environment/status")
            try await peer.respond(to: status, result: .object([
                "status": .string("ready")
            ]))
            try await peer.writer.sendClose()
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )
        let allEvents = await client.connectionEvents()

        do {
            let pendingStatus = await client.connectionSnapshot()
            XCTAssertEqual(pendingStatus, .pending)
            try await client.connect()
            let futureEvents = await client.connectionEvents()
            let readyStatus = await client.connectionSnapshot()
            XCTAssertEqual(readyStatus, .ready)

            var allIterator = allEvents.makeAsyncIterator()
            let connectedEvent = await allIterator.next()
            let disconnectedEvent = await allIterator.next()
            XCTAssertEqual(connectedEvent?.state, .connected)
            XCTAssertEqual(disconnectedEvent?.state, .disconnected)
            var futureIterator = futureEvents.makeAsyncIterator()
            let futureDisconnectedEvent = await futureIterator.next()
            XCTAssertEqual(
                futureDisconnectedEvent?.state,
                .disconnected,
                "Subscribing after connect must not replay current state"
            )
            let disconnectedStatus = await client.connectionSnapshot()
            XCTAssertEqual(disconnectedStatus.status, .disconnected)
            XCTAssertFalse(disconnectedStatus.error?.isEmpty ?? true)
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testOversizedMetadataSizeIsRejectedWithoutNumericTrap() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "metadata-session")
            let request = try await peer.readJSON()
            XCTAssertEqual(request["method"]?.stringValue, "fs/getMetadata")
            try await peer.respond(to: request, result: .object([
                "isDirectory": .bool(false),
                "isFile": .bool(true),
                "isSymlink": .bool(false),
                // Double(UInt64.max) rounds up to 2^64 and used to pass validation before
                // trapping in UInt64.init.
                "size": .number(Double(UInt64.max))
            ]))
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            do {
                _ = try await client.metadata(
                    at: "file:///workspace/file",
                    sandbox: try Self.sandbox()
                )
                XCTFail("Oversized metadata must be rejected")
            } catch let error as AppServerExecServerError {
                XCTAssertEqual(
                    error,
                    .invalidResponse("fs/getMetadata returned malformed metadata")
                )
            }
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testOversizedProcessSequenceIsRejectedWithoutNumericTrap() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "process-session")

            let start = try await peer.readJSON()
            let processID = try XCTUnwrap(
                start["params"]?.objectValue?["processId"]?.stringValue
            )
            try await peer.respond(to: start, result: .object([
                "processId": .string(processID)
            ]))

            let read = try await peer.readJSON()
            try await peer.respond(to: read, result: .object([
                "chunks": .array([]),
                "nextSeq": .number(Double(UInt64.max)),
                "exited": .bool(false),
                "closed": .bool(false)
            ]))
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            do {
                _ = try await client.runProcess(.init(
                    argv: ["/bin/zsh", "-lc", "whoami"],
                    cwdURI: "file:///workspace",
                    environment: [:],
                    sandbox: try Self.sandbox(),
                    timeoutSeconds: 2
                ))
                XCTFail("Oversized process sequence must be rejected")
            } catch let error as AppServerExecServerError {
                XCTAssertEqual(
                    error,
                    .invalidResponse("process/read returned a malformed response")
                )
            }
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testTerminalProcessResponseRequiresExitStatus() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "terminal-session")

            let start = try await peer.readJSON()
            let processID = try XCTUnwrap(
                start["params"]?.objectValue?["processId"]?.stringValue
            )
            try await peer.respond(to: start, result: .object([
                "processId": .string(processID)
            ]))
            let read = try await peer.readJSON()
            try await peer.respond(to: read, result: .object([
                "chunks": .array([]),
                "nextSeq": .number(0),
                "exited": .bool(true),
                "closed": .bool(true),
                "failure": .null,
                "sandboxDenied": .bool(false)
            ]))
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            do {
                _ = try await client.runProcess(.init(
                    argv: ["/bin/zsh", "-lc", "whoami"],
                    cwdURI: "file:///workspace",
                    environment: [:],
                    sandbox: try Self.sandbox(),
                    timeoutSeconds: 2
                ))
                XCTFail("A terminal response without status must not become exit code zero")
            } catch let error as AppServerExecServerError {
                XCTAssertEqual(
                    error,
                    .invalidResponse(
                        "process/read reached a terminal state without an exit status"
                    )
                )
            }
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testMalformedJSONRPCErrorCodeIsReportedWithoutNumericTrap() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "error-session")
            let request = try await peer.readJSON()
            try await peer.respond(
                to: request,
                errorCode: Double.greatestFiniteMagnitude,
                message: "remote rejected request"
            )
        }
        let client = AppServerExecServerWebSocketClient(
            websocketURL: "ws://127.0.0.1:\(listener.port)",
            connectTimeout: 2
        )

        do {
            do {
                _ = try await client.environmentInfo()
                XCTFail("The remote JSON-RPC error must be surfaced")
            } catch let error as AppServerExecServerError {
                XCTAssertEqual(
                    error,
                    .remoteRPC(code: nil, message: "remote rejected request")
                )
            }
            try await server.value
        } catch {
            server.cancel()
            listener.close()
            await client.close()
            throw error
        }
        listener.close()
        await client.close()
    }

    func testHugeTimeoutDescriptionDoesNotTrap() {
        let error = AppServerExecServerError.timedOut(
            operation: "connect",
            seconds: Double.greatestFiniteMagnitude
        )

        XCTAssertTrue(error.localizedDescription.hasPrefix("exec-server connect timed out after "))
        XCTAssertTrue(error.localizedDescription.hasSuffix("s"))
    }

}
