import Foundation
@testable import QuillCodeCLI
import QuillCodeTools
import XCTest

final class AppServerMCPConfigurationTests: XCTestCase {
    func testLoadsStdioRemoteAndOAuthConfigurationsFromCodexCompatibleTOML() throws {
        let root = try temporaryDirectory()
        let workingDirectory = root.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.toml")
        try Data("""
        [mcp_servers.local-server]
        command = "python3"
        args = ["server.py", "--stdio"]
        cwd = "tools"
        env = { STATIC = "configured" }
        env_vars = ["INHERITED", { name = "OPTIONAL", source = "local" }]
        startup_timeout_sec = 12
        tool_timeout_sec = 34
        required = true
        enabled_tools = ["read", "write"]
        disabled_tools = ["write"]

        [mcp_servers.remote_server]
        url = "https://mcp.example.com/api"
        http_headers = { "X-Static" = "static" }
        env_http_headers = { "X-Dynamic" = "HEADER_TOKEN" }
        bearer_token_env_var = "MCP_TOKEN"

        [mcp_servers.oauth]
        url = "https://oauth.example.com/mcp"
        scopes = ["tools:read"]
        oauth_client_id = "client-123"
        oauth_resource = "https://resource.example.com"

        [mcp_servers.disabled]
        command = "ignored"
        enabled = false
        """.utf8).write(to: config)

        let configurations = try AppServerMCPConfigurationLoader.load(
            globalConfig: config,
            projectRoot: nil,
            fallbackCWD: root,
            environment: [
                "INHERITED": "inherited-value",
                "HEADER_TOKEN": "dynamic-value",
                "MCP_TOKEN": "secret-token"
            ]
        )

        XCTAssertEqual(configurations.keys.sorted(), ["local-server", "oauth", "remote_server"])
        let local = try XCTUnwrap(configurations["local-server"])
        guard case let .stdio(command, arguments, environment, cwd) = local.transport else {
            return XCTFail("expected stdio transport")
        }
        XCTAssertEqual(command, "python3")
        XCTAssertEqual(arguments, ["server.py", "--stdio"])
        XCTAssertEqual(environment, ["STATIC": "configured", "INHERITED": "inherited-value"])
        XCTAssertEqual(cwd, workingDirectory.standardizedFileURL)
        XCTAssertEqual(local.startupTimeout, 12)
        XCTAssertEqual(local.toolTimeout, 34)
        XCTAssertTrue(local.required)
        XCTAssertTrue(local.permitsTool(named: "read"))
        XCTAssertFalse(local.permitsTool(named: "write"))
        XCTAssertFalse(local.permitsTool(named: "other"))
        XCTAssertEqual(local.authStatus, .unsupported)

        let remote = try XCTUnwrap(configurations["remote_server"])
        guard case let .remote(url, headers, bearerToken) = remote.transport else {
            return XCTFail("expected remote transport")
        }
        XCTAssertEqual(url.absoluteString, "https://mcp.example.com/api")
        XCTAssertEqual(headers, ["X-Static": "static", "X-Dynamic": "dynamic-value"])
        XCTAssertEqual(bearerToken, "secret-token")
        XCTAssertEqual(remote.authStatus, .bearerToken)
        XCTAssertFalse(remote.required)
        guard case let .remote(_, requestHeaders, _, authorization) = remote.launchRequest().transport else {
            return XCTFail("expected remote launch request")
        }
        XCTAssertEqual(requestHeaders, headers)
        XCTAssertEqual(authorization.currentAuthorizationHeader(), "Bearer secret-token")

        let oauth = try XCTUnwrap(configurations["oauth"])
        XCTAssertEqual(oauth.authStatus, .notLoggedIn)
        XCTAssertEqual(oauth.oauthClientID, "client-123")
        XCTAssertEqual(oauth.oauthScopes, ["tools:read"])
        XCTAssertEqual(oauth.oauthResource, "https://resource.example.com")
    }

    func testProjectConfigurationsOverrideGlobalServersByExactName() throws {
        let root = try temporaryDirectory()
        let global = root.appendingPathComponent("config.toml")
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(".codex", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(".quillcode", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("""
        [mcp_servers.shared]
        command = "global"

        [mcp_servers.global-only]
        command = "global-only"
        """.utf8).write(to: global)
        try Data("""
        [mcp_servers.shared]
        command = "codex"

        [mcp_servers.codex-only]
        command = "codex-only"
        """.utf8).write(to: project.appendingPathComponent(".codex/config.toml"))
        try Data("""
        [mcp_servers.shared]
        command = "quillcode"
        """.utf8).write(to: project.appendingPathComponent(".quillcode/config.toml"))

        let configurations = try AppServerMCPConfigurationLoader.load(
            globalConfig: global,
            projectRoot: project,
            fallbackCWD: project,
            environment: [:]
        )

        XCTAssertEqual(configurations.keys.sorted(), ["codex-only", "global-only", "shared"])
        guard case let .stdio(command, _, _, _) = configurations["shared"]?.transport else {
            return XCTFail("expected shared stdio server")
        }
        XCTAssertEqual(command, "quillcode")
    }

    func testRejectsAmbiguousTransportUnsafeHeadersAndInvalidTimeouts() throws {
        let invalidDocuments: [(String, String)] = [
            ("""
            [mcp_servers.invalid]
            command = "server"
            url = "https://example.com/mcp"
            """, "must define exactly one of command or url"),
            ("""
            [mcp_servers.invalid]
            url = "https://example.com/mcp"
            http_headers = { Host = "spoofed.example" }
            """, "contains an invalid header"),
            ("""
            [mcp_servers.invalid]
            url = "https://example.com/mcp"
            http_headers = { "X-Unsafe" = "value\\nInjected: true" }
            """, "contains an invalid header"),
            ("""
            [mcp_servers.invalid]
            url = "https://example.com/mcp"
            env_http_headers = { "Invalid Header" = "TOKEN" }
            """, "contains an invalid header"),
            ("""
            [mcp_servers.invalid]
            url = "https://example.com/mcp"
            env_http_headers = { "X-Token" = "" }
            """, "must name an environment variable"),
            ("""
            [mcp_servers.invalid]
            command = "server"
            startup_timeout_sec = 0
            """, "startup_timeout_sec must be between 1 and 300"),
            ("""
            [mcp_servers.invalid]
            command = "server"
            required = "yes"
            """, "required must be a boolean"),
            ("""
            [mcp_servers.invalid]
            url = "https://example.com/mcp"
            oauth_client_id = " "
            """, "oauth_client_id must be a non-empty string"),
            ("""
            [mcp_servers.invalid]
            url = "https://example.com/mcp"
            oauth_resource = 42
            """, "oauth_resource must be a string"),
            ("""
            [mcp_servers.invalid]
            url = "https://example.com/mcp"
            scopes = ["tools:read", ""]
            """, "scopes must contain non-empty strings")
        ]

        for (index, invalid) in invalidDocuments.enumerated() {
            let root = try temporaryDirectory(suffix: "-\(index)")
            let config = root.appendingPathComponent("config.toml")
            try Data(invalid.0.utf8).write(to: config)
            XCTAssertThrowsError(
                try AppServerMCPConfigurationLoader.load(
                    globalConfig: config,
                    projectRoot: nil,
                    fallbackCWD: root,
                    environment: [:]
                )
            ) { error in
                XCTAssertTrue(
                    (error as? AppServerRPCError)?.message.contains(invalid.1) == true,
                    "unexpected error: \(error)"
                )
            }
        }
    }

    func testRejectsUnsafeEnvironmentHeaderValueAndReportsConfiguredBearerAuth() throws {
        let root = try temporaryDirectory()
        let config = root.appendingPathComponent("config.toml")
        try Data("""
        [mcp_servers.remote]
        url = "https://example.com/mcp"
        env_http_headers = { "X-Token" = "HEADER_TOKEN" }
        bearer_token_env_var = "MISSING_TOKEN"
        """.utf8).write(to: config)

        XCTAssertThrowsError(
            try AppServerMCPConfigurationLoader.load(
                globalConfig: config,
                projectRoot: nil,
                fallbackCWD: root,
                environment: ["HEADER_TOKEN": "safe\r\nInjected: true"]
            )
        ) { error in
            XCTAssertTrue((error as? AppServerRPCError)?.message.contains("invalid header") == true)
        }

        let configurations = try AppServerMCPConfigurationLoader.load(
            globalConfig: config,
            projectRoot: nil,
            fallbackCWD: root,
            environment: [:]
        )
        XCTAssertEqual(configurations["remote"]?.authStatus, .bearerToken)
    }

    func testStoredOAuthDrivesStatusAndLaunchAuthorizationWithoutOverridingConfiguredBearer() throws {
        let root = try temporaryDirectory()
        let config = root.appendingPathComponent("config.toml")
        try Data("""
        [mcp_servers.oauth]
        url = "https://oauth.example.com/mcp"
        scopes = ["tools:read"]

        [mcp_servers.bearer]
        url = "https://bearer.example.com/mcp"
        bearer_token_env_var = "MCP_TOKEN"
        """.utf8).write(to: config)
        let configurations = try AppServerMCPConfigurationLoader.load(
            globalConfig: config,
            projectRoot: nil,
            fallbackCWD: root,
            environment: ["MCP_TOKEN": "configured-token"]
        )
        let secretStore = AppServerMCPSecretStore(
            directory: root.appendingPathComponent("secrets", isDirectory: true)
        )
        try MCPTokenStore(serverID: "mcp_server:oauth", secretStore: secretStore).saveTokens(
            MCPOAuthTokens(accessToken: "stored-oauth-token")
        )
        try MCPTokenStore(serverID: "mcp_server:bearer", secretStore: secretStore).saveTokens(
            MCPOAuthTokens(accessToken: "ignored-oauth-token")
        )

        let oauth = try XCTUnwrap(configurations["oauth"])
        XCTAssertEqual(oauth.reportingStoredOAuth(secretStore: secretStore).authStatus, .oAuth)
        guard case let .remote(_, _, _, oauthAuthorization) = oauth.launchRequest(
            secretStore: secretStore,
            httpClient: ConfigurationMCPHTTPClient()
        ).transport else {
            return XCTFail("expected remote OAuth request")
        }
        XCTAssertEqual(oauthAuthorization.currentAuthorizationHeader(), "Bearer stored-oauth-token")

        let bearer = try XCTUnwrap(configurations["bearer"])
        XCTAssertEqual(bearer.reportingStoredOAuth(secretStore: secretStore).authStatus, .bearerToken)
        guard case let .remote(_, _, _, bearerAuthorization) = bearer.launchRequest(
            secretStore: secretStore,
            httpClient: ConfigurationMCPHTTPClient()
        ).transport else {
            return XCTFail("expected remote bearer request")
        }
        XCTAssertEqual(bearerAuthorization.currentAuthorizationHeader(), "Bearer configured-token")
    }

    private func temporaryDirectory(suffix: String = "") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-app-server-mcp-config-\(UUID().uuidString)\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct ConfigurationMCPHTTPClient: MCPHTTPClient {
    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        _ = request
        throw MCPHTTPClientError.transport("unexpected request")
    }

    func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        _ = request
        throw MCPHTTPClientError.transport("unexpected stream")
    }
}
