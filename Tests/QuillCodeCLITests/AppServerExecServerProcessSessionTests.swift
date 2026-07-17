import Foundation
@testable import QuillCodeCLI
import QuillCodePlatform
import XCTest

final class AppServerExecServerProcessSessionTests: AppServerExecServerWebSocketTestCase {
    func testProcessSessionStreamsBeforeExitAndTerminatesTheStableProcessID() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let requestedProcessID = "2147483647"
        let server = Task.detached { @Sendable [listener, requestedProcessID] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "streaming-process-session")

            let start = try await peer.readJSON()
            XCTAssertEqual(start["method"]?.stringValue, "process/start")
            XCTAssertEqual(
                start["params"]?.objectValue?["processId"]?.stringValue,
                requestedProcessID
            )
            try await peer.respond(to: start, result: .object([
                "processId": .string(requestedProcessID)
            ]))

            let firstRead = try await peer.readJSON()
            XCTAssertEqual(firstRead["method"]?.stringValue, "process/read")
            try await peer.respond(to: firstRead, result: .object([
                "chunks": .array([
                    .object([
                        "seq": .number(1),
                        "stream": .string("stdout"),
                        "chunk": .string(Data("live\n".utf8).base64EncodedString())
                    ])
                ]),
                "nextSeq": .number(2),
                "exited": .bool(false),
                "closed": .bool(false)
            ]))

            let pending = [try await peer.readJSON(), try await peer.readJSON()]
            let terminalRead = try XCTUnwrap(pending.first {
                $0["method"]?.stringValue == "process/read"
            })
            let terminate = try XCTUnwrap(pending.first {
                $0["method"]?.stringValue == "process/terminate"
            })
            XCTAssertEqual(
                terminate["params"]?.objectValue?["processId"]?.stringValue,
                requestedProcessID
            )
            try await peer.respond(to: terminate, result: .object([:]))
            try await peer.respond(to: terminalRead, result: .object([
                "chunks": .array([]),
                "nextSeq": .number(2),
                "exited": .bool(true),
                "exitCode": .number(143),
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
            let session = try await client.startProcess(.init(
                processID: requestedProcessID,
                argv: ["/bin/zsh", "-lc", "printf live; sleep 30"],
                cwdURI: "file:///workspace",
                environment: [:],
                sandbox: try Self.sandbox(),
                timeoutSeconds: 2
            ))
            XCTAssertEqual(session.processID, requestedProcessID)
            let events = try await session.events()
            var iterator = events.makeAsyncIterator()
            let firstEvent = try await iterator.next()
            XCTAssertEqual(firstEvent, .stdout("live\n"))
            let cancelledTermination = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                await session.terminate()
            }
            await cancelledTermination.value
            guard case .finished(let result) = try await iterator.next() else {
                return XCTFail("Expected the terminal process result after live output")
            }
            XCTAssertEqual(result.stdout, "live\n")
            XCTAssertEqual(result.exitCode, 143)
            let exhaustedEvent = try await iterator.next()
            XCTAssertNil(exhaustedEvent)
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

    func testCancelledProcessReadIgnoresLateReplyWithoutResettingSharedConnection() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        let server = Task.detached { @Sendable [listener] in
            let connection = try await listener.accept()
            defer { connection.close() }
            let peer = try await Self.acceptPeer(connection)
            try await peer.completeHandshake(sessionID: "cancelled-read-session")

            let firstStart = try await peer.readJSON()
            let firstProcessID = try XCTUnwrap(
                firstStart["params"]?.objectValue?["processId"]?.stringValue
            )
            try await peer.respond(to: firstStart, result: .object([
                "processId": .string(firstProcessID)
            ]))
            let firstRead = try await peer.readJSON()
            try await peer.respond(to: firstRead, result: .object([
                "chunks": .array([
                    .object([
                        "seq": .number(1),
                        "stream": .string("stdout"),
                        "chunk": .string(Data("first-live\n".utf8).base64EncodedString())
                    ])
                ]),
                "nextSeq": .number(2),
                "exited": .bool(false),
                "closed": .bool(false)
            ]))

            let pending = [try await peer.readJSON(), try await peer.readJSON()]
            let abandonedRead = try XCTUnwrap(pending.first {
                $0["method"]?.stringValue == "process/read"
            })
            let terminate = try XCTUnwrap(pending.first {
                $0["method"]?.stringValue == "process/terminate"
            })
            try await peer.respond(to: terminate, result: .object([:]))
            try await Task.sleep(for: .milliseconds(50))
            try await peer.respond(to: abandonedRead, result: .object([
                "chunks": .array([]),
                "nextSeq": .number(2),
                "exited": .bool(true),
                "exitCode": .number(143),
                "closed": .bool(true),
                "failure": .null,
                "sandboxDenied": .bool(false)
            ]))

            let secondStart = try await peer.readJSON()
            XCTAssertEqual(secondStart["method"]?.stringValue, "process/start")
            let secondProcessID = try XCTUnwrap(
                secondStart["params"]?.objectValue?["processId"]?.stringValue
            )
            try await peer.respond(to: secondStart, result: .object([
                "processId": .string(secondProcessID)
            ]))
            let secondRead = try await peer.readJSON()
            try await peer.respond(to: secondRead, result: .object([
                "chunks": .array([]),
                "nextSeq": .number(1),
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
            let firstSession = try await client.startProcess(.init(
                argv: ["/bin/zsh", "-lc", "printf first-live; sleep 30"],
                cwdURI: "file:///workspace",
                environment: [:],
                sandbox: try Self.sandbox(),
                timeoutSeconds: 2
            ))
            let output = AsyncStream<String>.makeStream()
            let consumer = Task {
                do {
                    let events = try await firstSession.events()
                    for try await event in events {
                        if case .stdout(let text) = event {
                            output.continuation.yield(text)
                        }
                    }
                } catch {
                    // Cancellation is the behavior under test.
                }
            }
            var outputIterator = output.stream.makeAsyncIterator()
            let firstOutput = await outputIterator.next()
            XCTAssertEqual(firstOutput, "first-live\n")
            await firstSession.terminate()
            consumer.cancel()
            await consumer.value
            output.continuation.finish()
            try await Task.sleep(for: .milliseconds(100))

            let secondResult = try await client.runProcess(.init(
                argv: ["/bin/zsh", "-lc", "true"],
                cwdURI: "file:///workspace",
                environment: [:],
                sandbox: try Self.sandbox(),
                timeoutSeconds: 2
            ))
            XCTAssertEqual(secondResult.exitCode, 0)
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
}
