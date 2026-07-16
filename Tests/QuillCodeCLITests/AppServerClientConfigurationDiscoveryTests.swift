import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerClientConfigurationDiscoveryTests: XCTestCase {
    func testDefaultDiscoveryMatchesCodexWireContractAndPagination() async throws {
        let fixture = try await makeFixture()

        try await request(fixture, id: 2, method: "permissionProfile/list")
        try await request(
            fixture,
            id: 3,
            method: "permissionProfile/list",
            params: ["limit": 1]
        )
        try await request(
            fixture,
            id: 4,
            method: "permissionProfile/list",
            params: ["cursor": "3"]
        )
        try await request(
            fixture,
            id: 5,
            method: "permissionProfile/list",
            params: ["cursor": "4"]
        )
        try await request(fixture, id: 6, method: "configRequirements/read")
        try await request(fixture, id: 7, method: "collaborationMode/list")
        try await request(
            fixture,
            id: 8,
            method: "permissionProfile/list",
            params: ["limit": 0]
        )
        try await request(
            fixture,
            id: 9,
            method: "permissionProfile/list",
            params: ["cursor": "bad"]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(2, records), [
            "data": .array([
                permissionProfile(":read-only", allowed: true),
                permissionProfile(":workspace", allowed: true),
                permissionProfile(":danger-full-access", allowed: true)
            ]),
            "nextCursor": .null
        ])
        XCTAssertEqual(result(3, records), [
            "data": .array([permissionProfile(":read-only", allowed: true)]),
            "nextCursor": .string("1")
        ])
        XCTAssertEqual(result(4, records), ["data": .array([]), "nextCursor": .null])
        XCTAssertEqual(
            error(5, records)?["message"]?.stringValue,
            "cursor 4 exceeds total permission profiles 3"
        )
        XCTAssertEqual(result(6, records), ["requirements": .null])
        XCTAssertEqual(
            error(7, records)?["message"]?.stringValue,
            "collaborationMode/list requires experimentalApi capability"
        )
        XCTAssertEqual(result(8, records), result(3, records))
        XCTAssertEqual(error(9, records)?["message"]?.stringValue, "invalid cursor: bad")
    }

    func testExperimentalCollaborationModesMatchCodexWireContract() async throws {
        let fixture = try await makeFixture(experimentalAPI: true)

        try await request(fixture, id: 2, method: "collaborationMode/list")

        let records = try await fixture.output.records()
        XCTAssertEqual(result(2, records), [
            "data": .array([
                .object([
                    "name": .string("Plan"),
                    "mode": .string("plan"),
                    "model": .null,
                    "reasoning_effort": .string("medium")
                ]),
                .object([
                    "name": .string("Default"),
                    "mode": .string("default"),
                    "model": .null,
                    "reasoning_effort": .null
                ])
            ])
        ])
    }

    func testManagedRequirementsProjectionFiltersExperimentalFields() async throws {
        let requirements = """
        allowed_approval_policies = ["on-request"]
        allowed_approvals_reviewers = ["user"]
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        default_permissions = ":workspace"
        allowed_web_search_modes = ["live"]
        allow_managed_hooks_only = true
        allow_appshots = false
        allow_remote_control = false
        enforce_residency = "us"

        [allowed_permission_profiles]
        ":read-only" = true
        ":workspace" = true
        ":danger-full-access" = false

        [computer_use]
        allow_locked_computer_use = false

        [features]
        memory = true

        [experimental_network]
        enabled = true
        http_port = 8123
        allowed_domains = ["example.com"]

        [hooks]
        managed_dir = "/managed/hooks"

        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "notify"
        """
        let stable = try await makeFixture(requirements: requirements)
        let experimental = try await makeFixture(
            experimentalAPI: true,
            requirements: requirements
        )

        try await request(stable, id: 2, method: "permissionProfile/list")
        try await request(stable, id: 3, method: "configRequirements/read")
        try await request(experimental, id: 2, method: "configRequirements/read")

        let stableRecords = try await stable.output.records()
        let profiles = try XCTUnwrap(result(2, stableRecords)?["data"]?.arrayValue)
        XCTAssertEqual(profiles, [
            permissionProfile(":read-only", allowed: true),
            permissionProfile(":workspace", allowed: true),
            permissionProfile(":danger-full-access", allowed: false)
        ])

        let stableRequirements = try XCTUnwrap(
            result(3, stableRecords)?["requirements"]?.objectValue
        )
        XCTAssertEqual(stableRequirements["defaultPermissions"], .string(":workspace"))
        XCTAssertEqual(
            stableRequirements["allowedWebSearchModes"],
            .array([.string("live"), .string("disabled")])
        )
        XCTAssertEqual(stableRequirements["allowManagedHooksOnly"], .bool(true))
        XCTAssertEqual(
            stableRequirements["computerUse"]?.objectValue?["allowLockedComputerUse"],
            .bool(false)
        )
        XCTAssertNil(stableRequirements["allowedApprovalsReviewers"])
        XCTAssertNil(stableRequirements["hooks"])
        XCTAssertNil(stableRequirements["network"])

        let experimentalRecords = try await experimental.output.records()
        let experimentalRequirements = try XCTUnwrap(
            result(2, experimentalRecords)?["requirements"]?.objectValue
        )
        XCTAssertEqual(
            experimentalRequirements["allowedApprovalsReviewers"],
            .array([.string("user")])
        )
        let hooks = try XCTUnwrap(experimentalRequirements["hooks"]?.objectValue)
        XCTAssertEqual(hooks["managedDir"], .string("/managed/hooks"))
        XCTAssertEqual(hooks["PreToolUse"], .array([]))
        XCTAssertEqual(hooks["Stop"]?.arrayValue?.count, 1)
        let network = try XCTUnwrap(experimentalRequirements["network"]?.objectValue)
        XCTAssertEqual(network["enabled"], .bool(true))
        XCTAssertEqual(network["httpPort"], .number(8123))
        XCTAssertEqual(network["allowedDomains"], .array([.string("example.com")]))
    }

    func testManagedPermissionRequirementsAreEnforcedAcrossThreadsAndCommands() async throws {
        let fixture = try await makeFixture(experimentalAPI: true, requirements: """
        allowed_approval_policies = ["on-request"]
        allowed_approvals_reviewers = ["user"]
        allowed_sandbox_modes = ["read-only"]
        default_permissions = ":read-only"

        [allowed_permission_profiles]
        ":read-only" = true
        ":workspace" = false
        ":danger-full-access" = false
        """)

        try await request(
            fixture,
            id: 2,
            method: "thread/start",
            params: ["cwd": fixture.workspace.path, "permissions": ":workspace"]
        )
        try await request(
            fixture,
            id: 3,
            method: "thread/start",
            params: ["cwd": fixture.workspace.path, "permissions": ":read-only"]
        )
        var records = try await fixture.output.records()
        XCTAssertTrue(error(2, records)?["message"]?.stringValue?.contains("disallowed") == true)
        let thread = try XCTUnwrap(result(3, records)?["thread"]?.objectValue)
        let threadID = try XCTUnwrap(thread["id"]?.stringValue)
        XCTAssertEqual(
            result(3, records)?["activePermissionProfile"],
            .object(["id": .string(":read-only"), "extends": .null])
        )

        try await request(
            fixture,
            id: 4,
            method: "thread/settings/update",
            params: ["threadId": threadID, "permissions": ":danger-full-access"]
        )
        try await request(
            fixture,
            id: 5,
            method: "command/exec",
            params: [
                "command": ["/usr/bin/whoami"],
                "permissionProfile": ":danger-full-access"
            ]
        )
        try await request(
            fixture,
            id: 6,
            method: "thread/resume",
            params: ["threadId": threadID, "permissions": ":workspace"]
        )
        try await request(
            fixture,
            id: 7,
            method: "thread/fork",
            params: ["threadId": threadID, "permissions": ":workspace"]
        )
        try await request(
            fixture,
            id: 8,
            method: "thread/start",
            params: [
                "cwd": fixture.workspace.path,
                "sandbox": "read-only",
                "permissions": ":read-only"
            ]
        )
        records = try await fixture.output.records()
        XCTAssertTrue(error(4, records)?["message"]?.stringValue?.contains("disallowed") == true)
        XCTAssertTrue(error(5, records)?["message"]?.stringValue?.contains("disallowed") == true)
        XCTAssertTrue(error(6, records)?["message"]?.stringValue?.contains("disallowed") == true)
        XCTAssertTrue(error(7, records)?["message"]?.stringValue?.contains("disallowed") == true)
        XCTAssertTrue(error(8, records)?["message"]?.stringValue?.contains("cannot be combined") == true)
    }

    func testManagedDefaultPermissionProfileAppliesToNewThreads() async throws {
        let fixture = try await makeFixture(requirements: """
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        default_permissions = ":workspace"

        [allowed_permission_profiles]
        ":read-only" = true
        ":workspace" = true
        ":danger-full-access" = false
        """)

        try await request(
            fixture,
            id: 2,
            method: "thread/start",
            params: ["cwd": fixture.workspace.path]
        )

        let records = try await fixture.output.records()
        let response = try XCTUnwrap(result(2, records))
        XCTAssertEqual(
            response["activePermissionProfile"],
            .object(["id": .string(":workspace"), "extends": .null])
        )
        XCTAssertEqual(
            response["sandbox"]?.objectValue?["type"],
            .string("workspaceWrite")
        )
    }
}

private extension AppServerClientConfigurationDiscoveryTests {
    func makeFixture(
        experimentalAPI: Bool = false,
        requirements: String? = nil
    ) async throws -> ClientConfigurationFixture {
        let home = try temporaryDirectory(prefix: "client-config-home")
        let workspace = try temporaryDirectory(prefix: "client-config-workspace")
        var hookPaths = HookConfigurationPaths(userQuillCodeDirectory: home)
        if let requirements {
            let file = home.appendingPathComponent("requirements.toml")
            try requirements.write(to: file, atomically: true, encoding: .utf8)
            hookPaths.managedRequirementFiles = [file]
        }
        let paths = QuillCodePaths(home: home, hookConfigurationPaths: hookPaths)
        let output = ClientConfigurationOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: MockLLMClient(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            paths: paths,
            sink: { line in await output.append(line) }
        )
        try await send([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "ClientConfigTests", "version": "1"],
                "capabilities": ["experimentalApi": experimentalAPI]
            ]
        ], to: session)
        try await send(["method": "initialized", "params": [:]], to: session)
        return ClientConfigurationFixture(
            session: session,
            output: output,
            workspace: workspace
        )
    }

    func request(
        _ fixture: ClientConfigurationFixture,
        id: Int,
        method: String,
        params: [String: Any] = [:]
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: fixture.session)
    }

    func send(_ object: [String: Any], to session: AppServerSession) async throws {
        await session.receive(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }

    func result(
        _ id: Int,
        _ records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    func error(
        _ id: Int,
        _ records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue
    }

    func permissionProfile(_ id: String, allowed: Bool) -> CLIJSONValue {
        .object(["id": .string(id), "description": .null, "allowed": .bool(allowed)])
    }

    func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct ClientConfigurationFixture {
    var session: AppServerSession
    var output: ClientConfigurationOutputCollector
    var workspace: URL
}

private actor ClientConfigurationOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw ClientConfigurationTestError.invalidRecord
            }
            return object
        }
    }
}

private enum ClientConfigurationTestError: Error {
    case invalidRecord
}
