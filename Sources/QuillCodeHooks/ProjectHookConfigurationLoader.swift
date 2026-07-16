import Foundation
import QuillCodeCore

enum CodexHookDocumentFormat: Sendable, Hashable {
    case json
    case toml
}

struct CodexHookDocument: Sendable, Hashable {
    var root: URL
    var fileName: String
    var format: CodexHookDocumentFormat
    var source: CodexHookDefinitionSource
    var readsActivationPolicy: Bool

    init(
        root: URL,
        fileName: String,
        format: CodexHookDocumentFormat,
        source: CodexHookDefinitionSource,
        readsActivationPolicy: Bool = false
    ) {
        self.root = root
        self.fileName = fileName
        self.format = format
        self.source = source
        self.readsActivationPolicy = readsActivationPolicy
    }
}

struct CodexHookDocumentLoadResult: Sendable, Hashable {
    var hooks: [ProjectPluginHook] = []
    var warnings: [String] = []
    var hooksFeatureOverride: Bool?
    var allowManagedHooksOnly: Bool?
}

public struct HookConfigurationDiscovery: Sendable, Hashable {
    public var hooks: [ProjectPluginHook]
    public var warnings: [String]

    public init(hooks: [ProjectPluginHook] = [], warnings: [String] = []) {
        self.hooks = hooks
        self.warnings = warnings
    }
}

/// Shared data-only loader for project, user, system, and managed hook documents.
/// Every caller supplies canonical roots and stable source identities; discovery never executes code.
enum CodexHookDocumentLoader {
    static let maxDocumentBytes = 64 * 1024

    static func load(
        _ documents: [CodexHookDocument],
        maxHooks: Int
    ) -> CodexHookDocumentLoadResult {
        var result = CodexHookDocumentLoadResult()
        for document in documents {
            let data: Data
            switch loadDocument(document) {
            case .missing:
                continue
            case .failure(let warning):
                result.warnings.append(warning)
                continue
            case .success(let loaded):
                data = loaded
            }
            let configuration: CodexHookConfiguration
            do {
                configuration = try decode(data, format: document.format)
            } catch {
                result.warnings.append(
                    "failed to parse hooks config \(documentURL(document).path): \(error.localizedDescription)"
                )
                continue
            }
            let remaining = max(0, maxHooks - result.hooks.count)
            if remaining > 0 {
                result.hooks.append(contentsOf: CodexHookDefinitionBuilder.definitions(
                    from: configuration,
                    source: document.source,
                    limit: remaining
                ))
            }
            if document.readsActivationPolicy {
                if let override = configuration.hooksFeatureOverride {
                    result.hooksFeatureOverride = override
                }
                if let managedOnly = configuration.allowManagedHooksOnly {
                    result.allowManagedHooksOnly = managedOnly
                }
            }
        }
        return result
    }

    private static func decode(
        _ data: Data,
        format: CodexHookDocumentFormat
    ) throws -> CodexHookConfiguration {
        switch format {
        case .json:
            return try CodexHookConfigurationDecoder.decodeJSONThrowing(data)
        case .toml:
            return try CodexHookConfigurationDecoder.decodeTOMLThrowing(data)
        }
    }

    private enum DocumentReadResult {
        case missing
        case success(Data)
        case failure(String)
    }

    private static func loadDocument(_ document: CodexHookDocument) -> DocumentReadResult {
        let root = document.root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = documentURL(document)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
            return .failure("refusing symlinked hooks config: \(candidate.path)")
        }
        guard WorkspaceBoundary.isWithin(candidate, root: root) else {
            return .failure("refusing hooks config outside its source root: \(candidate.path)")
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return .missing }

        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
        } catch {
            return .failure("failed to inspect hooks config \(candidate.path): \(error.localizedDescription)")
        }
        guard values.isRegularFile == true else {
            return .failure("hooks config is not a regular file: \(candidate.path)")
        }
        guard let fileSize = values.fileSize, fileSize <= maxDocumentBytes else {
            return .failure(
                "hooks config exceeds the \(maxDocumentBytes)-byte limit: \(candidate.path)"
            )
        }

        let resolved = candidate.resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(resolved, root: root) else {
            return .failure("refusing hooks config outside its source root: \(candidate.path)")
        }
        do {
            let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
            guard data.count <= maxDocumentBytes else {
                return .failure(
                    "hooks config exceeds the \(maxDocumentBytes)-byte limit: \(candidate.path)"
                )
            }
            return .success(data)
        } catch {
            return .failure("failed to read hooks config \(candidate.path): \(error.localizedDescription)")
        }
    }

    private static func documentURL(_ document: CodexHookDocument) -> URL {
        document.root
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .appendingPathComponent(document.fileName)
            .standardizedFileURL
    }
}

public enum ProjectHookConfigurationLoader {
    public static let maxDocumentBytes = CodexHookDocumentLoader.maxDocumentBytes
    public static let maxHooks = 96

    public static func load(from projectRoot: URL) -> [ProjectPluginHook] {
        discover(from: projectRoot).hooks
    }

    public static func discover(from projectRoot: URL) -> HookConfigurationDiscovery {
        let result = CodexHookDocumentLoader.load(
            documents(for: projectRoot),
            maxHooks: maxHooks
        )
        return HookConfigurationDiscovery(hooks: result.hooks, warnings: result.warnings)
    }

    private static func documents(for projectRoot: URL) -> [CodexHookDocument] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        return [
            document(
                root: root,
                fileName: ".quillcode/hooks.json",
                sourceID: "quillcode-json",
                ownerName: "Project hooks",
                format: .json
            ),
            document(
                root: root,
                fileName: ".quillcode/config.toml",
                sourceID: "quillcode-config",
                ownerName: "Project config hooks",
                format: .toml
            ),
            document(
                root: root,
                fileName: ".codex/hooks.json",
                sourceID: "codex-json",
                ownerName: "Codex project hooks",
                format: .json
            ),
            document(
                root: root,
                fileName: ".codex/config.toml",
                sourceID: "codex-config",
                ownerName: "Codex project config hooks",
                format: .toml
            )
        ]
    }

    private static func document(
        root: URL,
        fileName: String,
        sourceID: String,
        ownerName: String,
        format: CodexHookDocumentFormat
    ) -> CodexHookDocument {
        CodexHookDocument(
            root: root,
            fileName: fileName,
            format: format,
            source: CodexHookDefinitionSource(
                idPrefix: "config_hook:\(sourceID)",
                ownerID: "hook-source:\(sourceID)",
                ownerName: ownerName,
                relativePath: fileName,
                pluginRootRelativePath: nil,
                trustScope: .workspace
            )
        )
    }
}
