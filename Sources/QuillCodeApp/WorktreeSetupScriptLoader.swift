import Foundation
import QuillCodeTools

struct WorktreeSetupScript: Equatable, Sendable {
    var relativePath: String
    var command: String
    var environment: [String: String]?
    var timeoutSeconds: Int?
}

enum WorktreeSetupScriptLoader {
    static let defaultTimeoutSeconds = ProjectScriptMetadataLoader.maxTimeoutSeconds

    static func load(
        from worktreeRoot: URL,
        configuration: WorktreeSetupConfiguration,
        operatingSystem: HostOperatingSystem = .current
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
                timeoutSeconds: metadata?.timeoutSeconds ?? defaultTimeoutSeconds
            )
        }
        return nil
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
