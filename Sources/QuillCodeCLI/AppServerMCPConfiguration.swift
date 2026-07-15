import Foundation
import QuillCodePersistence
import QuillCodeTools

struct AppServerMCPServerConfiguration: Sendable, Hashable {
    enum Transport: Sendable, Hashable {
        case stdio(command: String, arguments: [String], environment: [String: String], cwd: URL)
        case remote(url: URL, headers: [String: String], bearerToken: String?)
    }

    enum AuthStatus: String, Sendable, Hashable {
        case unsupported
        case notLoggedIn
        case bearerToken
        case oAuth
    }

    var name: String
    var transport: Transport
    var startupTimeout: TimeInterval
    var toolTimeout: TimeInterval
    var enabledTools: Set<String>?
    var disabledTools: Set<String>
    var authStatus: AuthStatus

    func launchRequest() -> MCPClientLaunchRequest {
        switch transport {
        case let .stdio(command, arguments, environment, cwd):
            return MCPClientLaunchRequest(
                transport: .stdio,
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: cwd
            )
        case let .remote(url, headers, bearerToken):
            let authorization: any MCPRemoteAuthorizing
            if let bearerToken {
                authorization = MCPStaticAuthorization(bearerToken: bearerToken)
            } else {
                authorization = MCPNoAuthorization()
            }
            return MCPClientLaunchRequest(
                transport: .remote(
                    url: url,
                    headers: headers,
                    mode: .automatic,
                    authorization: authorization
                ),
                workingDirectory: URL(fileURLWithPath: "/")
            )
        }
    }

    func permitsTool(named name: String) -> Bool {
        !disabledTools.contains(name) && (enabledTools?.contains(name) ?? true)
    }
}

enum AppServerMCPConfigurationLoader {
    static func load(
        globalConfig: URL,
        projectRoot: URL?,
        fallbackCWD: URL,
        environment: [String: String]
    ) throws -> [String: AppServerMCPServerConfiguration] {
        var tables: [String: ConfigValue] = [:]
        for file in configFiles(globalConfig: globalConfig, projectRoot: projectRoot) {
            let document = try ConfigDocumentStore(fileURL: file).load()
            guard let servers = document.values["mcp_servers"]?.objectValue else { continue }
            for (name, value) in servers { tables[name] = value }
        }

        var configurations: [String: AppServerMCPServerConfiguration] = [:]
        for name in tables.keys.sorted() {
            guard let value = tables[name] else { continue }
            guard let table = value.objectValue else {
                throw error(name, "configuration must be a table")
            }
            if table["enabled"]?.boolValue == false { continue }
            configurations[name] = try configuration(
                name: name,
                table: table,
                fallbackCWD: fallbackCWD,
                environment: environment
            )
        }
        return configurations
    }

    private static func configFiles(globalConfig: URL, projectRoot: URL?) -> [URL] {
        guard let projectRoot else { return [globalConfig] }
        return [
            globalConfig,
            projectRoot.appendingPathComponent(".codex/config.toml"),
            projectRoot.appendingPathComponent(".quillcode/config.toml")
        ]
    }

    private static func configuration(
        name: String,
        table: [String: ConfigValue],
        fallbackCWD: URL,
        environment: [String: String]
    ) throws -> AppServerMCPServerConfiguration {
        let command = table["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlText = table["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (command?.isEmpty == false) != (urlText?.isEmpty == false) else {
            throw error(name, "must define exactly one of command or url")
        }

        let startupTimeout = try seconds(
            table["startup_timeout_sec"],
            name: name,
            field: "startup_timeout_sec",
            defaultValue: 10,
            range: 1...300
        )
        let toolTimeout = try seconds(
            table["tool_timeout_sec"],
            name: name,
            field: "tool_timeout_sec",
            defaultValue: 60,
            range: 1...3_600
        )
        let enabledTools = try stringSet(table["enabled_tools"], name: name, field: "enabled_tools")
        let disabledTools = try stringSet(table["disabled_tools"], name: name, field: "disabled_tools") ?? []

        if let command, !command.isEmpty {
            let arguments = try strings(table["args"], name: name, field: "args") ?? []
            var launchEnvironment = try stringMap(table["env"], name: name, field: "env") ?? [:]
            for inheritedName in try inheritedEnvironmentNames(table["env_vars"], serverName: name) {
                if let value = environment[inheritedName] { launchEnvironment[inheritedName] = value }
            }
            let cwd = try workingDirectory(
                table["cwd"]?.stringValue,
                name: name,
                fallback: fallbackCWD
            )
            return AppServerMCPServerConfiguration(
                name: name,
                transport: .stdio(
                    command: command,
                    arguments: arguments,
                    environment: launchEnvironment,
                    cwd: cwd
                ),
                startupTimeout: startupTimeout,
                toolTimeout: toolTimeout,
                enabledTools: enabledTools,
                disabledTools: disabledTools,
                authStatus: .unsupported
            )
        }

        guard let urlText,
              let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil
        else {
            throw error(name, "url must be an http(s) URL without embedded credentials")
        }
        var headers = try headerMap(table["http_headers"], name: name, field: "http_headers") ?? [:]
        let environmentHeaders = try environmentHeaderMap(
            table["env_http_headers"],
            name: name,
            environment: environment
        )
        headers.merge(environmentHeaders) { _, environmentValue in environmentValue }
        let bearerVariable = table["bearer_token_env_var"]?.stringValue
        let bearerToken = bearerVariable.flatMap { environment[$0] }.flatMap { $0.isEmpty ? nil : $0 }
        let hasAuthorizationHeader = headers.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame }
        let requestsOAuth = table["oauth"] != nil || table["scopes"] != nil
        let authStatus: AppServerMCPServerConfiguration.AuthStatus = bearerVariable != nil || hasAuthorizationHeader
            ? .bearerToken
            : (requestsOAuth ? .notLoggedIn : .unsupported)
        return AppServerMCPServerConfiguration(
            name: name,
            transport: .remote(url: url, headers: headers, bearerToken: bearerToken),
            startupTimeout: startupTimeout,
            toolTimeout: toolTimeout,
            enabledTools: enabledTools,
            disabledTools: disabledTools,
            authStatus: authStatus
        )
    }

    private static func workingDirectory(_ raw: String?, name: String, fallback: URL) throws -> URL {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback.standardizedFileURL
        }
        let expanded = NSString(string: raw).expandingTildeInPath
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : fallback.appendingPathComponent(expanded)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { throw error(name, "cwd is not a directory") }
        return url.standardizedFileURL
    }

    private static func seconds(
        _ value: ConfigValue?,
        name: String,
        field: String,
        defaultValue: Double,
        range: ClosedRange<Double>
    ) throws -> Double {
        guard let value else { return defaultValue }
        guard let number = value.numberValue, number.isFinite, range.contains(number) else {
            throw error(name, "\(field) must be between \(Int(range.lowerBound)) and \(Int(range.upperBound))")
        }
        return number
    }

    private static func strings(_ value: ConfigValue?, name: String, field: String) throws -> [String]? {
        guard let value else { return nil }
        guard let array = value.arrayValue else { throw error(name, "\(field) must be an array") }
        return try array.map { item in
            guard let string = item.stringValue else { throw error(name, "\(field) must contain strings") }
            return string
        }
    }

    private static func stringSet(_ value: ConfigValue?, name: String, field: String) throws -> Set<String>? {
        try strings(value, name: name, field: field).map(Set.init)
    }

    private static func stringMap(
        _ value: ConfigValue?,
        name: String,
        field: String
    ) throws -> [String: String]? {
        guard let value else { return nil }
        guard let object = value.objectValue else { throw error(name, "\(field) must be a table") }
        var result: [String: String] = [:]
        for (key, value) in object {
            guard let string = value.stringValue else { throw error(name, "\(field).\(key) must be a string") }
            result[key] = string
        }
        return result
    }

    private static func headerMap(
        _ value: ConfigValue?,
        name: String,
        field: String
    ) throws -> [String: String]? {
        guard let values = try stringMap(value, name: name, field: field) else { return nil }
        for (key, value) in values {
            try validateHeader(name: key, value: value, serverName: name, field: field)
        }
        return values
    }

    private static func environmentHeaderMap(
        _ value: ConfigValue?,
        name: String,
        environment: [String: String]
    ) throws -> [String: String] {
        let field = "env_http_headers"
        guard let variables = try stringMap(value, name: name, field: field) else { return [:] }
        var headers: [String: String] = [:]
        for (header, variable) in variables {
            guard !variable.isEmpty, !variable.contains("=") else {
                throw error(name, "\(field).\(header) must name an environment variable")
            }
            guard let value = environment[variable], !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                try validateHeaderName(header, serverName: name, field: field)
                continue
            }
            try validateHeader(name: header, value: value, serverName: name, field: field)
            headers[header] = value
        }
        return headers
    }

    private static func validateHeader(
        name: String,
        value: String,
        serverName: String,
        field: String
    ) throws {
        try validateHeaderName(name, serverName: serverName, field: field)
        let validValue = !value.isEmpty
            && value.count <= 8_192
            && value.unicodeScalars.allSatisfy { scalar in
                scalar.value == 9 || (scalar.value >= 32 && scalar.value != 127)
            }
        guard validValue else { throw error(serverName, "\(field) contains an invalid header") }
    }

    private static func validateHeaderName(
        _ header: String,
        serverName: String,
        field: String
    ) throws {
        let tokenCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~"
        )
        let forbidden = ["host", "content-length", "transfer-encoding"]
        let validName = !header.isEmpty
            && header.count <= 200
            && header.unicodeScalars.allSatisfy(tokenCharacters.contains)
            && !forbidden.contains(header.lowercased())
        guard validName else { throw error(serverName, "\(field) contains an invalid header") }
    }

    private static func inheritedEnvironmentNames(
        _ value: ConfigValue?,
        serverName: String
    ) throws -> [String] {
        guard let value else { return [] }
        guard let array = value.arrayValue else { throw error(serverName, "env_vars must be an array") }
        return try array.map { item in
            if let name = item.stringValue { return name }
            guard let object = item.objectValue,
                  let name = object["name"]?.stringValue,
                  [nil, "local"].contains(object["source"]?.stringValue)
            else { throw error(serverName, "env_vars entries must name local environment variables") }
            return name
        }
    }

    private static func error(_ name: String, _ message: String) -> AppServerRPCError {
        .invalidParams("mcp_servers.\(name) \(message)")
    }
}
