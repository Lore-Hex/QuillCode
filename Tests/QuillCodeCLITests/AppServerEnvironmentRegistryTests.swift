import Foundation
@testable import QuillCodeCLI
import XCTest

final class AppServerEnvironmentRegistryTests: XCTestCase {
    func testLocalEnvironmentInfoUsesConfiguredShellAndWorkingDirectory() async throws {
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-local-environment")
        let registry = AppServerEnvironmentRegistry(
            localCWD: cwd,
            environment: ["SHELL": "/opt/homebrew/bin/fish"]
        )

        let value = try await registry.info(.object([
            "environmentId": .string("local")
        ]))

        XCTAssertEqual(value.objectValue?["shell"]?.objectValue?["name"]?.stringValue, "fish")
        XCTAssertEqual(
            value.objectValue?["shell"]?.objectValue?["path"]?.stringValue,
            "/opt/homebrew/bin/fish"
        )
        XCTAssertEqual(value.objectValue?["cwd"]?.stringValue, cwd.standardizedFileURL.absoluteString)

        let status = try await registry.status(.object(["environmentId": .string("local")]))
        XCTAssertEqual(status.objectValue?["status"]?.stringValue, "ready")
        XCTAssertEqual(status.objectValue?["error"], .null)
    }

    func testStatusReportsPendingReadyDisconnectedAndUnknownWithoutReconnecting() async throws {
        let client = AppServerFakeExecServerClient(connectDelay: .milliseconds(80))
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = registry(factory: factory)
        _ = try await registry.add(registration(id: "remote", url: "ws://example.test"))

        var status = try await registry.status(.object(["environmentId": .string("remote")]))
        XCTAssertEqual(status.objectValue?["status"]?.stringValue, "pending")
        XCTAssertEqual(status.objectValue?["error"], .null)

        try await waitUntil {
            let value = try? await registry.status(.object([
                "environmentId": .string("remote")
            ]))
            return value?.objectValue?["status"]?.stringValue == "ready"
        }
        await client.setConnectionSnapshot(.disconnected("transport closed"))
        status = try await registry.status(.object(["environmentId": .string("remote")]))
        XCTAssertEqual(status.objectValue?["status"]?.stringValue, "disconnected")
        XCTAssertEqual(status.objectValue?["error"]?.stringValue, "transport closed")
        let clientSnapshot = await client.snapshot()
        XCTAssertEqual(clientSnapshot.connectCount, 1)

        status = try await registry.status(.object(["environmentId": .string("missing")]))
        XCTAssertEqual(status.objectValue?["status"]?.stringValue, "unknown")
        XCTAssertEqual(
            status.objectValue?["error"]?.stringValue,
            "unknown environment id `missing`"
        )
        await registry.closeAll()
    }

    func testAddIsLazyAndInfoSurfacesRemoteConnectionFailure() async throws {
        let client = AppServerFakeExecServerClient(
            connectError: .disconnected("offline"),
            infoError: .disconnected("offline")
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = registry(factory: factory)

        let result = try await registry.add(.object([
            "environmentId": .string("cloud"),
            "execServerUrl": .string("wss://executor.example/ws"),
            "connectTimeoutMs": .number(1_500)
        ]))

        XCTAssertEqual(result, .object([:]))
        let registration = try XCTUnwrap(factory.snapshot().first)
        XCTAssertEqual(registration.websocketURL, "wss://executor.example/ws")
        XCTAssertEqual(registration.connectTimeout, 1.5)

        do {
            _ = try await registry.info(.object(["environmentId": .string("cloud")]))
            XCTFail("environment/info should surface the remote failure")
        } catch let error as AppServerRPCError {
            XCTAssertEqual(error.code, -32_603)
            XCTAssertTrue(error.message.contains("failed to get info for environment `cloud`"))
            XCTAssertTrue(error.message.contains("offline"))
        }
    }

    func testReplacingEnvironmentClosesOldClientAndResolvesNewClient() async throws {
        let first = AppServerFakeExecServerClient(info: info(shell: "bash"))
        let second = AppServerFakeExecServerClient(info: info(shell: "zsh"))
        let factory = AppServerFakeExecServerFactory(clients: [first, second])
        let registry = registry(factory: factory)

        _ = try await registry.add(registration(id: "remote", url: "ws://first.example"))
        _ = try await registry.add(registration(id: "remote", url: "ws://second.example"))
        try await waitUntil { await first.snapshot().closeCount == 1 }

        let value = try await registry.info(.object(["environmentId": .string("remote")]))
        XCTAssertEqual(value.objectValue?["shell"]?.objectValue?["name"]?.stringValue, "zsh")
        XCTAssertEqual(factory.snapshot().map(\.websocketURL), [
            "ws://first.example",
            "ws://second.example"
        ])
    }

    func testRegistrationAndSelectionValidationFailClosed() async throws {
        let registry = AppServerEnvironmentRegistry(
            localCWD: URL(fileURLWithPath: "/tmp"),
            environment: [:]
        )

        try await assertInvalidRequest(contains: "environment id cannot be empty") {
            _ = try await registry.add(self.registration(id: "", url: "ws://example.test"))
        }
        try await assertInvalidRequest(contains: "requires an exec-server url") {
            _ = try await registry.add(self.registration(id: "remote", url: "  "))
        }
        try await assertInvalidRequest(contains: "unsigned integer") {
            _ = try await registry.add(.object([
                "environmentId": .string("remote"),
                "execServerUrl": .string("ws://example.test"),
                "connectTimeoutMs": .number(-1)
            ]))
        }
        try await assertInvalidRequest(contains: "unsigned integer") {
            _ = try await registry.add(.object([
                "environmentId": .string("remote"),
                "execServerUrl": .string("ws://example.test"),
                "connectTimeoutMs": .number(Double(UInt64.max))
            ]))
        }
        try await assertInvalidRequest(contains: "unknown turn environment id") {
            try await registry.validate([
                .init(environmentID: "missing", cwd: "/workspace")
            ])
        }
    }

    private func registry(
        factory: AppServerFakeExecServerFactory
    ) -> AppServerEnvironmentRegistry {
        AppServerEnvironmentRegistry(
            localCWD: URL(fileURLWithPath: "/tmp"),
            environment: [:],
            monitorInterval: .milliseconds(5),
            clientFactory: { factory.make(websocketURL: $0, connectTimeout: $1) }
        )
    }

    private func info(shell: String) -> AppServerEnvironmentInfo {
        .init(
            shell: .init(name: shell, path: "/bin/\(shell)"),
            cwd: "file:///workspace"
        )
    }

    private func registration(id: String, url: String) -> CLIJSONValue {
        .object([
            "environmentId": .string(id),
            "execServerUrl": .string(url)
        ])
    }

    private func assertInvalidRequest(
        contains expected: String,
        operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
            XCTFail("Expected an invalid request error")
        } catch let error as AppServerRPCError {
            XCTAssertEqual(error.code, -32_600)
            XCTAssertTrue(error.message.contains(expected), error.message)
        }
    }

    private func waitUntil(
        _ condition: @escaping () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for asynchronous registry cleanup")
    }
}
