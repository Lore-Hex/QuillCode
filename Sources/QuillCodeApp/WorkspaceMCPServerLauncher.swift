import Foundation
import QuillCodeCore
import QuillCodeTools

typealias WorkspaceMCPSession = MCPClientSession
typealias WorkspaceMCPProcessControlling = MCPProcessControlling
typealias WorkspaceMCPProcessLaunchConfiguration = MCPProcessLaunchConfiguration

extension WorkspaceMCPSession {
    func callTool(toolName: String, argumentsJSON: String) throws -> ToolResult {
        try callTool(toolName: toolName, argumentsJSON: argumentsJSON, timeout: 10.0)
    }

    func readResource(uri: String) throws -> ToolResult {
        try readResource(uri: uri, timeout: 10.0)
    }

    func getPrompt(name: String, argumentsJSON: String) throws -> ToolResult {
        try getPrompt(name: name, argumentsJSON: argumentsJSON, timeout: 10.0)
    }
}

struct WorkspaceMCPLaunchRequest: Sendable, Hashable {
    /// The two connection shapes a server can take: a spawned stdio child process, or a remote
    /// HTTP/SSE endpoint. `command`/`arguments` are populated only for `.stdio`.
    enum Transport: Sendable, Hashable {
        case stdio
        /// `http` uses StreamableHTTP with SSE failover; `sse` forces the legacy HTTP+SSE transport.
        case remote(url: URL, headers: [String: String], preferSSE: Bool, oauthClientID: String?)
    }

    var serverID: String
    var transport: Transport
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
    var workspaceRoot: URL

    static func make(
        manifest: ProjectExtensionManifest,
        workspaceRoot: URL
    ) throws -> WorkspaceMCPLaunchRequest {
        guard manifest.isEnabled else {
            throw WorkspaceMCPLaunchRequestError.disabled(name: manifest.name)
        }

        switch manifest.transport {
        case .http, .sse:
            guard let rawURL = manifest.serverURL, !rawURL.isEmpty else {
                throw WorkspaceMCPLaunchRequestError.missingURL(name: manifest.name)
            }
            guard let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty
            else {
                throw WorkspaceMCPLaunchRequestError.invalidURL(name: manifest.name, url: rawURL)
            }
            // Embedded credentials in the URL are a parser-differential/leak risk — refuse them;
            // auth belongs in headers or the OAuth flow.
            guard (url.user ?? "").isEmpty, url.password == nil else {
                throw WorkspaceMCPLaunchRequestError.invalidURL(name: manifest.name, url: rawURL)
            }
            return WorkspaceMCPLaunchRequest(
                serverID: manifest.id,
                transport: .remote(
                    url: url,
                    headers: manifest.headers ?? [:],
                    preferSSE: manifest.transport == .sse,
                    oauthClientID: manifest.oauthClientID
                ),
                command: "",
                arguments: [],
                environment: [:],
                workingDirectory: workspaceRoot,
                workspaceRoot: workspaceRoot
            )
        case .stdio, .none:
            guard let command = manifest.launchExecutable,
                  !command.isEmpty
            else {
                throw WorkspaceMCPLaunchRequestError.missingCommand(name: manifest.name)
            }
            let workingDirectory = try packageRoot(
                manifest.packageRootRelativePath,
                workspaceRoot: workspaceRoot,
                extensionName: manifest.name
            )
            let pluginRoot = workingDirectory.path
            let expand: (String) -> String = {
                $0.replacingOccurrences(of: "${CODEX_PLUGIN_ROOT}", with: pluginRoot)
            }
            var environment = (manifest.launchEnvironment ?? [:]).mapValues(expand)
            for name in manifest.inheritedEnvironmentVariableNames ?? [] {
                if let value = ProcessInfo.processInfo.environment[name] {
                    environment[name] = value
                }
            }
            if manifest.packageRootRelativePath != nil {
                environment["CODEX_PLUGIN_ROOT"] = pluginRoot
            }
            return WorkspaceMCPLaunchRequest(
                serverID: manifest.id,
                transport: .stdio,
                command: expand(command),
                arguments: (manifest.launchArguments ?? []).map(expand),
                environment: environment,
                workingDirectory: workingDirectory,
                workspaceRoot: workspaceRoot
            )
        }
    }

    private static func packageRoot(
        _ relativePath: String?,
        workspaceRoot: URL,
        extensionName: String
    ) throws -> URL {
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard let relativePath else { return root }
        let components = relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw WorkspaceMCPLaunchRequestError.invalidPackageRoot(name: extensionName)
        }
        let candidate = components.reduce(root) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard WorkspaceBoundary.isWithin(candidate, root: root),
              values?.isDirectory == true,
              values?.isSymbolicLink != true
        else {
            throw WorkspaceMCPLaunchRequestError.invalidPackageRoot(name: extensionName)
        }
        return candidate
    }
}

enum WorkspaceMCPLaunchRequestError: Error, LocalizedError, Equatable {
    case disabled(name: String)
    case missingCommand(name: String)
    case missingURL(name: String)
    case invalidURL(name: String, url: String)
    case invalidPackageRoot(name: String)

    var errorDescription: String? {
        switch self {
        case .disabled(let name):
            return "\(name) is disabled."
        case .missingCommand(let name):
            return "\(name) does not define a launch command."
        case .missingURL(let name):
            return "\(name) does not define a server URL for its HTTP transport."
        case .invalidURL(let name, let url):
            return "\(name) has an invalid server URL: \(url)"
        case .invalidPackageRoot(let name):
            return "\(name) references a plugin package outside this workspace."
        }
    }
}

struct WorkspaceMCPLaunchedServer: Sendable {
    var process: any WorkspaceMCPProcessControlling
    var session: any WorkspaceMCPSession
}

protocol WorkspaceMCPServerLaunching: Sendable {
    func launch(
        request: WorkspaceMCPLaunchRequest,
        onTermination: @escaping @MainActor @Sendable (_ id: String, _ terminationStatus: Int32) -> Void
    ) throws -> WorkspaceMCPLaunchedServer
}

struct DefaultWorkspaceMCPServerLauncher: WorkspaceMCPServerLaunching {
    /// Secret store used to resolve stored OAuth tokens for remote servers. Nil disables auth
    /// (open servers still connect; servers requiring auth surface a 401 at probe time).
    var secretStore: (any MCPSecretStore)?
    /// HTTP transport for remote servers. Defaults to the real `URLSession` client.
    var httpClient: any MCPHTTPClient
    private let clientLauncher: any MCPClientLaunching

    init(
        secretStore: (any MCPSecretStore)? = nil,
        httpClient: any MCPHTTPClient = URLSessionMCPHTTPClient(),
        clientLauncher: (any MCPClientLaunching)? = nil
    ) {
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.clientLauncher = clientLauncher ?? DefaultMCPClientLauncher(httpClient: httpClient)
    }

    func launch(
        request: WorkspaceMCPLaunchRequest,
        onTermination: @escaping @MainActor @Sendable (_ id: String, _ terminationStatus: Int32) -> Void
    ) throws -> WorkspaceMCPLaunchedServer {
        let transport: MCPClientLaunchRequest.Transport
        switch request.transport {
        case .stdio:
            transport = .stdio
        case let .remote(url, headers, preferSSE, oauthClientID):
            transport = .remote(
                url: url,
                headers: headers,
                mode: preferSSE ? .httpSSE : .automatic,
                authorization: WorkspaceMCPRemoteAuthResolver.authorization(
                    serverID: request.serverID,
                    serverURL: url,
                    oauthClientID: oauthClientID,
                    serverHeaders: headers,
                    secretStore: secretStore,
                    httpClient: httpClient
                )
            )
        }
        let launched = try clientLauncher.launch(
            request: MCPClientLaunchRequest(
                transport: transport,
                command: request.command,
                arguments: request.arguments,
                environment: request.environment,
                workingDirectory: request.workingDirectory
            ),
            onTermination: { status in
                Task { @MainActor in onTermination(request.serverID, status) }
            }
        )
        return WorkspaceMCPLaunchedServer(process: launched.process, session: launched.session)
    }
}
