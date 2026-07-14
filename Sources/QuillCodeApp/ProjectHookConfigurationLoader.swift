import Foundation
import QuillCodeCore

enum ProjectHookConfigurationLoader {
    static let maxDocumentBytes = 64 * 1024
    static let maxHooks = 96

    private enum DocumentFormat {
        case json
        case toml
    }

    private struct Document {
        var relativePath: String
        var sourceID: String
        var ownerName: String
        var format: DocumentFormat
    }

    private static let documents = [
        Document(
            relativePath: ".quillcode/hooks.json",
            sourceID: "quillcode-json",
            ownerName: "Project hooks",
            format: .json
        ),
        Document(
            relativePath: ".quillcode/config.toml",
            sourceID: "quillcode-config",
            ownerName: "Project config hooks",
            format: .toml
        ),
        Document(
            relativePath: ".codex/hooks.json",
            sourceID: "codex-json",
            ownerName: "Codex project hooks",
            format: .json
        ),
        Document(
            relativePath: ".codex/config.toml",
            sourceID: "codex-config",
            ownerName: "Codex project config hooks",
            format: .toml
        )
    ]

    static func load(from projectRoot: URL) -> [ProjectPluginHook] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        var hooks: [ProjectPluginHook] = []
        for document in documents {
            let remaining = maxHooks - hooks.count
            guard remaining > 0 else { break }
            guard let data = loadDocument(document.relativePath, inside: root),
                  let configuration = decode(data, format: document.format)
            else { continue }
            hooks.append(contentsOf: CodexHookDefinitionBuilder.definitions(
                from: configuration,
                source: CodexHookDefinitionSource(
                    idPrefix: "config_hook:\(document.sourceID)",
                    ownerID: "hook-source:\(document.sourceID)",
                    ownerName: document.ownerName,
                    relativePath: document.relativePath,
                    pluginRootRelativePath: nil
                ),
                limit: remaining
            ))
        }
        return hooks
    }

    private static func decode(
        _ data: Data,
        format: DocumentFormat
    ) -> CodexHookConfiguration? {
        switch format {
        case .json:
            return CodexHookConfigurationDecoder.decodeJSON(data)
        case .toml:
            return CodexHookConfigurationDecoder.decodeTOML(data)
        }
    }

    private static func loadDocument(_ relativePath: String, inside root: URL) -> Data? {
        let candidate = root
            .appendingPathComponent(relativePath)
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
