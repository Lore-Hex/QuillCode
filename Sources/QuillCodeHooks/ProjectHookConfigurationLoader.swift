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
    var definitions: [HookCatalogDefinition] = []
    var hookStates: [String: HookConfigurationState] = [:]
    var diagnostics: [HookConfigurationDiagnostic] = []
    var hooksFeatureOverride: Bool?
    var allowManagedHooksOnly: Bool?

    var hooks: [ProjectPluginHook] {
        definitions.map(\.hook)
    }

    var warnings: [String] {
        diagnostics.map(\.description)
    }
}

public struct HookConfigurationDiscovery: Sendable, Hashable {
    public var hooks: [ProjectPluginHook]
    public var warnings: [String]
    public var definitions: [HookCatalogDefinition]
    public var hookStates: [String: HookConfigurationState]
    public var diagnostics: [HookConfigurationDiagnostic]
    public var hooksFeatureOverride: Bool?
    public var allowManagedHooksOnly: Bool?

    public init(
        hooks: [ProjectPluginHook] = [],
        warnings: [String] = [],
        definitions: [HookCatalogDefinition] = [],
        hookStates: [String: HookConfigurationState] = [:],
        diagnostics: [HookConfigurationDiagnostic] = [],
        hooksFeatureOverride: Bool? = nil,
        allowManagedHooksOnly: Bool? = nil
    ) {
        self.hooks = hooks
        self.warnings = warnings
        self.definitions = definitions
        self.hookStates = hookStates
        self.diagnostics = diagnostics
        self.hooksFeatureOverride = hooksFeatureOverride
        self.allowManagedHooksOnly = allowManagedHooksOnly
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
            case .failure(let diagnostic):
                result.diagnostics.append(diagnostic)
                continue
            case .success(let loaded):
                data = loaded
            }
            let configuration: CodexHookConfiguration
            do {
                configuration = try decode(data, format: document.format)
            } catch {
                result.diagnostics.append(HookConfigurationDiagnostic(
                    path: documentURL(document).path,
                    message: "failed to parse hooks config: \(error.localizedDescription)"
                ))
                continue
            }
            let remaining = max(0, maxHooks - result.definitions.count)
            if remaining > 0 {
                var source = document.source
                let sourcePath = documentURL(document)
                source.sourcePath = sourcePath
                source.keyPrefix = source.keyPrefix ?? sourcePath.path
                result.definitions.append(contentsOf: CodexHookDefinitionBuilder.catalogDefinitions(
                    from: configuration,
                    source: source,
                    limit: remaining
                ))
            }
            for (key, state) in configuration.hookStates {
                result.hookStates[key] = state
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
        case failure(HookConfigurationDiagnostic)
    }

    private static func loadDocument(_ document: CodexHookDocument) -> DocumentReadResult {
        let root = document.root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = documentURL(document)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
            return .failure(HookConfigurationDiagnostic(
                path: candidate.path,
                message: "refusing symlinked hooks config"
            ))
        }
        guard WorkspaceBoundary.isWithin(candidate, root: root) else {
            return .failure(HookConfigurationDiagnostic(
                path: candidate.path,
                message: "refusing hooks config outside its source root"
            ))
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return .missing }

        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
        } catch {
            return .failure(HookConfigurationDiagnostic(
                path: candidate.path,
                message: "failed to inspect hooks config: \(error.localizedDescription)"
            ))
        }
        guard values.isRegularFile == true else {
            return .failure(HookConfigurationDiagnostic(
                path: candidate.path,
                message: "hooks config is not a regular file"
            ))
        }
        guard let fileSize = values.fileSize, fileSize <= maxDocumentBytes else {
            return .failure(HookConfigurationDiagnostic(
                path: candidate.path,
                message: "hooks config exceeds the \(maxDocumentBytes)-byte limit"
            ))
        }

        let resolved = candidate.resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(resolved, root: root) else {
            return .failure(HookConfigurationDiagnostic(
                path: candidate.path,
                message: "refusing hooks config outside its source root"
            ))
        }
        do {
            let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
            guard data.count <= maxDocumentBytes else {
                return .failure(HookConfigurationDiagnostic(
                    path: candidate.path,
                    message: "hooks config exceeds the \(maxDocumentBytes)-byte limit"
                ))
            }
            return .success(data)
        } catch {
            return .failure(HookConfigurationDiagnostic(
                path: candidate.path,
                message: "failed to read hooks config: \(error.localizedDescription)"
            ))
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
        return HookConfigurationDiscovery(
            hooks: result.hooks,
            warnings: result.warnings,
            definitions: result.definitions,
            hookStates: result.hookStates,
            diagnostics: result.diagnostics,
            hooksFeatureOverride: result.hooksFeatureOverride,
            allowManagedHooksOnly: result.allowManagedHooksOnly
        )
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
                format: .toml,
                readsActivationPolicy: true
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
                format: .toml,
                readsActivationPolicy: true
            )
        ]
    }

    private static func document(
        root: URL,
        fileName: String,
        sourceID: String,
        ownerName: String,
        format: CodexHookDocumentFormat,
        readsActivationPolicy: Bool = false
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
                trustScope: .workspace,
                catalogSource: .project
            ),
            readsActivationPolicy: readsActivationPolicy
        )
    }
}
