import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorktreeSetupScript: Equatable, Sendable {
    var relativePath: String
    var command: String
    var environment: [String: String]?
    var timeoutSeconds: Int?
    var environmentID: String?
}

enum WorktreeSetupResolution: Equatable, Sendable {
    case skipped
    case script(WorktreeSetupScript)
    case failure(String)
}

enum WorktreeSetupScriptLoader {
    static let defaultTimeoutSeconds = ProjectScriptMetadataLoader.maxTimeoutSeconds

    static func load(
        from worktreeRoot: URL,
        configuration: WorktreeSetupConfiguration,
        operatingSystem: HostOperatingSystem = .current,
        environmentID: String? = nil
    ) -> WorktreeSetupScript? {
        guard configuration.isValid else { return nil }
        let root = worktreeRoot.standardizedFileURL.resolvingSymlinksInPath()
        for relativePath in candidatePaths(configuration: configuration, operatingSystem: operatingSystem) {
            let scriptURL = root
                .appendingPathComponent(relativePath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard scriptURL.path.hasPrefix(root.path + "/"),
                  scriptURL.pathExtension == "sh",
                  let values = try? scriptURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                continue
            }

            let metadata = ProjectScriptMetadataLoader.load(root: root, scriptURL: scriptURL)
            let environment = metadata?.environment ?? [:]
            return WorktreeSetupScript(
                relativePath: relativePath,
                command: ProjectScriptMetadataLoader.shellScriptCommand(
                    relativePath: relativePath,
                    workingDirectory: metadata?.workingDirectory
                ),
                environment: environment.isEmpty ? nil : environment,
                timeoutSeconds: metadata?.timeoutSeconds ?? defaultTimeoutSeconds,
                environmentID: environmentID
            )
        }
        return nil
    }

    static func resolve(
        from worktreeRoot: URL,
        configuration: WorkspaceProjectConfiguration,
        selection: WorktreeSetupSelection,
        operatingSystem: HostOperatingSystem = .current
    ) -> WorktreeSetupResolution {
        switch selection {
        case .none:
            return .skipped
        case .automatic:
            if let defaultID = configuration.defaultLocalEnvironmentID {
                return resolveNamed(
                    defaultID,
                    from: worktreeRoot,
                    configuration: configuration,
                    operatingSystem: operatingSystem
                )
            }
            guard configuration.worktreeSetup.isValid else {
                return .failure(
                    "Worktree setup configuration is invalid. "
                        + "Paths must be relative .sh files inside the project."
                )
            }
            guard let script = load(
                from: worktreeRoot,
                configuration: configuration.worktreeSetup,
                operatingSystem: operatingSystem
            ) else {
                if configuration.worktreeSetup.isExplicitlyConfigured {
                    return .failure(
                        "The configured worktree setup script was not found for this platform. "
                            + "Check [worktree_setup] in .quillcode/config.toml."
                    )
                }
                return .skipped
            }
            return .script(script)
        case .named(let environmentID):
            return resolveNamed(
                environmentID,
                from: worktreeRoot,
                configuration: configuration,
                operatingSystem: operatingSystem
            )
        }
    }

    private static func resolveNamed(
        _ rawEnvironmentID: String,
        from worktreeRoot: URL,
        configuration: WorkspaceProjectConfiguration,
        operatingSystem: HostOperatingSystem
    ) -> WorktreeSetupResolution {
        guard let environmentID = WorktreeLocalEnvironment.normalizedID(rawEnvironmentID),
              let environment = configuration.localEnvironments.first(where: { $0.id == environmentID })
        else {
            return .failure("The selected local environment '\(rawEnvironmentID)' is not configured in this checkout.")
        }
        guard environment.setup.isValid else {
            return .failure(
                "The local environment '\(environment.title)' has invalid setup paths. "
                    + "Paths must be relative .sh files inside the project."
            )
        }
        guard let script = load(
            from: worktreeRoot,
            configuration: environment.setup,
            operatingSystem: operatingSystem,
            environmentID: environment.id
        ) else {
            return .failure(
                "The local environment '\(environment.title)' has no setup script for this platform."
            )
        }
        return .script(script)
    }

    private static func candidatePaths(
        configuration: WorktreeSetupConfiguration,
        operatingSystem: HostOperatingSystem
    ) -> [String] {
        let platformPath: String?
        switch operatingSystem {
        case .macOS:
            platformPath = configuration.macOSScriptPath
        case .linux:
            platformPath = configuration.linuxScriptPath
        case .other:
            platformPath = nil
        }
        return [platformPath, configuration.scriptPath]
            .compactMap { $0 }
            .reduce(into: []) { paths, path in
                if !paths.contains(path) {
                    paths.append(path)
                }
            }
    }
}
