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
    var hooksFeatureOverride: Bool?
    var allowManagedHooksOnly: Bool?
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
            guard let data = loadDocument(document),
                  let configuration = decode(data, format: document.format)
            else { continue }
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
    ) -> CodexHookConfiguration? {
        switch format {
        case .json:
            return CodexHookConfigurationDecoder.decodeJSON(data)
        case .toml:
            return CodexHookConfigurationDecoder.decodeTOML(data)
        }
    }

    private static func loadDocument(_ document: CodexHookDocument) -> Data? {
        let root = document.root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root
            .appendingPathComponent(document.fileName)
            .standardizedFileURL
        guard WorkspaceBoundary.isWithin(candidate, root: root),
              let values = try? candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= maxDocumentBytes
        else { return nil }

        let resolved = candidate.resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(resolved, root: root) else { return nil }
        return try? Data(contentsOf: resolved, options: [.mappedIfSafe])
    }
}

enum ProjectHookConfigurationLoader {
    static let maxDocumentBytes = CodexHookDocumentLoader.maxDocumentBytes
    static let maxHooks = 96

    static func load(from projectRoot: URL) -> [ProjectPluginHook] {
        CodexHookDocumentLoader.load(
            documents(for: projectRoot),
            maxHooks: maxHooks
        ).hooks
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
