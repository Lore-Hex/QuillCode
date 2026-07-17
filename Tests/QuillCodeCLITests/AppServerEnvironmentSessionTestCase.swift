import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

class AppServerEnvironmentSessionTestCase: XCTestCase {
    var remoteInfo: AppServerEnvironmentInfo {
        .init(
            shell: .init(name: "zsh", path: "/bin/zsh"),
            cwd: "file:///workspace"
        )
    }

    func remoteSandbox(
        _ policy: AppServerSandboxPolicy
    ) throws -> AppServerExecServerSandboxContext {
        try AppServerExecServerSandboxContext(
            policy: policy,
            workspace: .init(cwd: "/workspace", fallbackCWDURI: nil)
        )
    }

    func makeRegistry(
        factory: AppServerFakeExecServerFactory
    ) -> AppServerEnvironmentRegistry {
        AppServerEnvironmentRegistry(
            localCWD: URL(fileURLWithPath: "/tmp"),
            environment: [:],
            clientFactory: { factory.make(websocketURL: $0, connectTimeout: $1) }
        )
    }

    func registration(id: String) -> CLIJSONValue {
        .object([
            "environmentId": .string(id),
            "execServerUrl": .string("ws://remote.example")
        ])
    }

    func threadParameters(
        environments: [[String: Any]],
        workspace: URL,
        sandbox: String = "read-only",
        approvalPolicy: String? = nil
    ) -> [String: Any] {
        var parameters: [String: Any] = [
            "cwd": workspace.path,
            "model": "trustedrouter/fast",
            "sandbox": sandbox,
            "environments": environments
        ]
        if let approvalPolicy { parameters["approvalPolicy"] = approvalPolicy }
        return parameters
    }

    func makeSession(
        llm: any LLMClient,
        registry: AppServerEnvironmentRegistry
    ) throws -> EnvironmentSessionFixture {
        let home = try temporaryDirectory(prefix: "environment-home")
        let workspace = try temporaryDirectory(prefix: "environment-workspace")
        let output = EnvironmentSessionOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: false,
                    compaction: AgentCompactionPolicy(compactor: ThreadCompactor())
                )
            },
            environmentRegistry: registry,
            sink: { line in await output.append(line) }
        )
        return .init(session: session, output: output, workspace: workspace)
    }

    func initialize(_ session: AppServerSession) async throws {
        try await sendRequest(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "EnvironmentTests", "version": "1"]],
            to: session
        )
        try await sendNotification(method: "initialized", params: [:], to: session)
    }

    func sendRequest(
        id: Int,
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: session)
    }

    func sendNotification(
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["method": method, "params": params], to: session)
    }

    func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?
            .objectValue?["code"]?.numberValue
    }

    func errorMessage(for id: Int, in records: [[String: CLIJSONValue]]) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?
            .objectValue?["message"]?.stringValue
    }

    func waitUntil(
        _ condition: @escaping () async -> Bool
    ) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for environment lifecycle notification")
    }

    private func send(_ object: [String: Any], to session: AppServerSession) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
