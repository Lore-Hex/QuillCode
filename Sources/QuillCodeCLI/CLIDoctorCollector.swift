import Foundation
import QuillCodeCore
import QuillCodePersistence

struct CLIDoctor: Sendable {
    private let gitProbe: any CLIDoctorGitProbing
    private let networkProbe: any CLIDoctorNetworkProbing
    private let runtimeProvider: @Sendable (Bool) -> CLIDoctorRuntimeSnapshot
    private let now: @Sendable () -> Date

    init(
        gitProbe: any CLIDoctorGitProbing = LiveCLIDoctorGitProbe(),
        networkProbe: any CLIDoctorNetworkProbing = LiveCLIDoctorNetworkProbe(),
        runtimeProvider: @escaping @Sendable (Bool) -> CLIDoctorRuntimeSnapshot = {
            CLIDoctorRuntimeSnapshot.live(inputIsTerminal: $0)
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.gitProbe = gitProbe
        self.networkProbe = networkProbe
        self.runtimeProvider = runtimeProvider
        self.now = now
    }

    func collect(
        request: CLIDoctorRequest,
        environment: [String: String],
        currentDirectory: URL,
        inputIsTerminal: Bool
    ) async -> CLIDoctorReport {
        let paths = request.home.map { QuillCodePaths(home: $0) } ?? QuillCodePaths()
        let runtime = runtimeProvider(inputIsTerminal)
        let configurationStartedAt = Date()
        var configuration = self.configuration(paths: paths)
        configuration.check.durationMs = elapsedMilliseconds(since: configurationStartedAt)
        let credentialsStartedAt = Date()
        var credentials = self.credentials(paths: paths, environment: environment)
        credentials.check.durationMs = elapsedMilliseconds(since: credentialsStartedAt)
        let mcp = timed {
            mcpConfiguration(
                paths: paths,
                currentDirectory: currentDirectory,
                environment: environment
            )
        }

        var checks = [
            timed { CLIDoctorLocalChecks.system(runtime: runtime, environment: environment) },
            timed { CLIDoctorLocalChecks.runtime(runtime) },
            timed { CLIDoctorLocalChecks.installation(runtime: runtime, environment: environment) },
            timed { CLIDoctorLocalChecks.search(environment: environment) },
            timed { CLIDoctorLocalChecks.git(gitProbe.inspect(currentDirectory: currentDirectory)) },
            timed { CLIDoctorLocalChecks.terminal(runtime: runtime, environment: environment) },
            configuration.check,
            credentials.check,
            mcp,
            timed { CLIDoctorLocalChecks.sandbox() },
            timed { CLIDoctorStateChecks.paths(paths) },
            timed { CLIDoctorStateChecks.threadInventory(paths) },
            timed { CLIDoctorLocalChecks.networkEnvironment(environment) },
            timed { CLIDoctorLocalChecks.appServer(paths: paths) }
        ]

        let networkStartedAt = Date()
        let networkResult = await networkProbe.probe(
            apiBaseURL: configuration.config.apiBaseURL,
            apiKey: credentials.apiKey
        )
        var reachability = reachabilityCheck(networkResult, apiKey: credentials.apiKey)
        reachability.durationMs = elapsedMilliseconds(since: networkStartedAt)
        checks.append(reachability)

        return CLIDoctorReport(
            generatedAt: Self.timestamp(now()),
            quillCodeVersion: QuillCodeCommandRunner.version,
            checks: checks
        )
    }

    private func configuration(paths: QuillCodePaths) -> ConfigurationResult {
        let exists = FileManager.default.fileExists(atPath: paths.configFile.path)
        guard exists else {
            return ConfigurationResult(
                config: AppConfig(),
                check: CLIDoctorCheck(
                    id: "config.load",
                    category: "config",
                    status: .ok,
                    summary: "built-in defaults loaded",
                    details: configurationDetails(
                        config: AppConfig(),
                        path: paths.configFile,
                        state: "missing"
                    )
                )
            )
        }

        do {
            _ = try ConfigDocumentStore(fileURL: paths.configFile).load()
            let config = try ConfigStore(fileURL: paths.configFile).load()
            return ConfigurationResult(
                config: config,
                check: CLIDoctorCheck(
                    id: "config.load",
                    category: "config",
                    status: .ok,
                    summary: "config loaded",
                    details: configurationDetails(
                        config: config,
                        path: paths.configFile,
                        state: "loaded"
                    )
                )
            )
        } catch {
            do {
                let config = try ConfigStore(fileURL: paths.configFile).load()
                return ConfigurationResult(
                    config: config,
                    check: CLIDoctorCheck(
                        id: "config.load",
                        category: "config",
                        status: .warning,
                        summary: "legacy config loaded with compatibility parsing",
                        details: configurationDetails(
                            config: config,
                            path: paths.configFile,
                            state: "strict TOML rejected; compatibility parser succeeded"
                        ),
                        remediation: "Open Settings and save once to rewrite strict TOML."
                    )
                )
            } catch {
                return ConfigurationResult(
                    config: AppConfig(),
                    check: CLIDoctorCheck(
                        id: "config.load",
                        category: "config",
                        status: .fail,
                        summary: "config could not be loaded",
                        details: .doctorDetails([
                            "config.toml": paths.configFile.path,
                            "error type": String(reflecting: type(of: error))
                        ]),
                        remediation: "Repair config.toml or move it aside and retry."
                    )
                )
            }
        }
    }

    private func configurationDetails(
        config: AppConfig,
        path: URL,
        state: String
    ) -> [String: CLIDoctorDetail] {
        .doctorDetails([
            "config.toml": "\(path.path) (\(state))",
            "model": config.defaultModel,
            "mode": config.mode.rawValue,
            "TrustedRouter base URL": CLIDoctorSanitizer.safeURL(config.apiBaseURL),
            "maximum tool steps": String(config.maxToolSteps)
        ])
    }

    private func credentials(
        paths: QuillCodePaths,
        environment: [String: String]
    ) -> CredentialResult {
        for name in ["QUILLCODE_API_KEY", "TRUSTEDROUTER_API_KEY"] {
            if let key = normalized(environment[name]) {
                return configuredCredentials(key: key, source: name)
            }
        }
        do {
            let store = FileSecretStore(directory: paths.secretsDirectory)
            if let key = normalized(try store.read(QuillSecretKeys.trustedRouterAPIKey)) {
                return configuredCredentials(key: key, source: "QuillCode secret store")
            }
            return CredentialResult(
                apiKey: nil,
                check: CLIDoctorCheck(
                    id: "auth.credentials",
                    category: "auth",
                    status: .fail,
                    summary: "no TrustedRouter credential was found",
                    details: .doctorDetails(["credential source": "none"]),
                    remediation: "Run `quill-code auth set-key KEY` or sign in from QuillCode Settings."
                )
            )
        } catch {
            return CredentialResult(
                apiKey: nil,
                check: CLIDoctorCheck(
                    id: "auth.credentials",
                    category: "auth",
                    status: .fail,
                    summary: "TrustedRouter credentials could not be read",
                    details: .doctorDetails([
                        "credential source": "QuillCode secret store",
                        "error type": String(reflecting: type(of: error))
                    ]),
                    remediation: "Repair secret-store ownership and permissions."
                )
            )
        }
    }

    private func configuredCredentials(key: String, source: String) -> CredentialResult {
        CredentialResult(
            apiKey: key,
            check: CLIDoctorCheck(
                id: "auth.credentials",
                category: "auth",
                status: .ok,
                summary: "TrustedRouter credential is configured",
                details: .doctorDetails(["credential source": source])
            )
        )
    }

    private func mcpConfiguration(
        paths: QuillCodePaths,
        currentDirectory: URL,
        environment: [String: String]
    ) -> CLIDoctorCheck {
        do {
            let secretStore = AppServerMCPSecretStore(directory: paths.secretsDirectory)
            let configurations = try AppServerMCPConfigurationLoader.load(
                globalConfig: paths.configFile,
                projectRoot: currentDirectory,
                fallbackCWD: currentDirectory,
                environment: environment
            ).mapValues { configuration in
                configuration.reportingStoredOAuth(secretStore: secretStore)
            }
            let required = configurations.values.filter(\.required).count
            let serverRows = configurations.keys.sorted().compactMap { name -> String? in
                guard let configuration = configurations[name] else { return nil }
                return CLIDoctorSanitizer.singleLine(
                    "\(name) (\(configuration.required ? "required" : "optional"), \(configuration.authStatus.rawValue))"
                )
            }
            return CLIDoctorCheck(
                id: "mcp.config",
                category: "mcp",
                status: .ok,
                summary: configurations.isEmpty
                    ? "no MCP servers configured"
                    : "\(configurations.count) MCP server\(configurations.count == 1 ? "" : "s") configured",
                details: [
                    "servers": .list(serverRows),
                    "required servers": .text(String(required))
                ]
            )
        } catch {
            return CLIDoctorCheck(
                id: "mcp.config",
                category: "mcp",
                status: .fail,
                summary: "MCP configuration could not be loaded",
                details: .doctorDetails(["error type": String(reflecting: type(of: error))]),
                remediation: "Repair the global or project MCP configuration and retry."
            )
        }
    }

    private func reachabilityCheck(
        _ result: CLIDoctorNetworkResult,
        apiKey: String?
    ) -> CLIDoctorCheck {
        let hasCredential = apiKey != nil
        let endpoint = CLIDoctorSanitizer.safeURL(result.endpoint)
        let details: [String: CLIDoctorDetail] = [
            "endpoint": .text(endpoint),
            "HTTP status": .text(result.statusCode.map(String.init) ?? "no response"),
            "credential sent": .text(String(hasCredential))
        ]
        if let error = result.error {
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .fail,
                summary: "TrustedRouter is unreachable",
                details: details.merging([
                    "error": .text(CLIDoctorSanitizer.redacted(error, secrets: [apiKey]))
                ]) { current, _ in current },
                remediation: "Check DNS, proxy, VPN, firewall, and custom CA configuration."
            )
        }
        guard let statusCode = result.statusCode else {
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .fail,
                summary: "TrustedRouter returned no HTTP status",
                details: details,
                remediation: "Check the configured TrustedRouter base URL."
            )
        }
        switch statusCode {
        case 200..<300:
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .ok,
                summary: "TrustedRouter model endpoint is reachable",
                details: details
            )
        case 401 where !hasCredential, 403 where !hasCredential:
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .ok,
                summary: "TrustedRouter is reachable and requires authentication",
                details: details
            )
        case 401, 403:
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .fail,
                summary: "TrustedRouter rejected the configured credential",
                details: details,
                remediation: "Sign in again or replace the TrustedRouter API key."
            )
        case 429:
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .warning,
                summary: "TrustedRouter is reachable but rate limited",
                details: details,
                remediation: "Wait for the rate-limit window to reset or switch models."
            )
        case 500...599:
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .warning,
                summary: "TrustedRouter is reachable but currently unavailable",
                details: details,
                remediation: "Retry after the provider recovers."
            )
        default:
            return CLIDoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .warning,
                summary: "TrustedRouter returned HTTP \(statusCode)",
                details: details,
                remediation: "Check the configured base URL and account access."
            )
        }
    }

    private func timed(_ body: () -> CLIDoctorCheck) -> CLIDoctorCheck {
        let startedAt = Date()
        var check = body()
        check.durationMs = elapsedMilliseconds(since: startedAt)
        return check
    }

    private func elapsedMilliseconds(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1_000))
    }

    private func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct ConfigurationResult {
    var config: AppConfig
    var check: CLIDoctorCheck
}

private struct CredentialResult {
    var apiKey: String?
    var check: CLIDoctorCheck
}
