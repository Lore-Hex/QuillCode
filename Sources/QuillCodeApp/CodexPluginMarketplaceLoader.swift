import Foundation
import QuillCodeCore

/// Loads repository-local entries from the standard Codex plugin marketplace contract.
/// This path is data-only: only explicit `./` local package sources are exposed, and installation
/// uses a typed copy tool rather than marketplace-provided commands or package lifecycle scripts.
enum CodexPluginMarketplaceLoader {
    static let defaultCatalogPaths = [
        ".agents/plugins/marketplace.json",
        ".claude-plugin/marketplace.json"
    ]
    static let maxCatalogBytes = 100_000
    static let maxPlugins = 128

    static func load(
        from projectRoot: URL,
        installedManifests: [ProjectExtensionManifest],
        catalogPaths: [String] = defaultCatalogPaths,
        maxPlugins: Int = maxPlugins,
        maxCatalogBytes: Int = maxCatalogBytes,
        maxPluginManifestBytes: Int = ProjectExtensionManifestLoader.maxManifestBytes
    ) -> [ProjectExtensionManifest] {
        guard maxPlugins > 0, maxCatalogBytes > 0 else { return [] }
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        var seenIDs = Set(installedManifests.map(\.id))
        var manifests: [ProjectExtensionManifest] = []

        for catalogPath in catalogPaths where manifests.count < maxPlugins {
            guard let catalog = catalog(at: catalogPath, root: root, maxBytes: maxCatalogBytes) else {
                continue
            }
            for entry in catalog.plugins where manifests.count < maxPlugins {
                guard entry.policy?.isAvailable != false,
                      let source = entry.source.localRelativePath,
                      source.hasPrefix("./"),
                      let entryID = normalizedIdentifier(entry.name),
                      let package = CodexPluginPackageLoader.loadPackage(
                        at: source,
                        in: root,
                        maxManifestBytes: maxPluginManifestBytes
                      ),
                      package.plugin.id == "plugin:\(entryID)",
                      seenIDs.insert(package.plugin.id).inserted
                else { continue }

                var manifest = package.plugin
                manifest.relativePath = "\(catalogPath)#\(entry.name)"
                manifest.packageRootRelativePath = nil
                manifest.skillDirectoryRelativePaths = nil
                manifest.localInstallSourceRelativePath = source
                manifest.installCommand = nil
                manifest.updateCommand = nil
                manifests.append(manifest)
            }
        }
        return manifests
    }

    private static func catalog(at relativePath: String, root: URL, maxBytes: Int) -> MarketplaceCatalog? {
        guard let url = WorkspaceBoundary.safeURL(relativePath, root: root) else { return nil }
        let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= maxBytes,
              let data = try? Data(contentsOf: url),
              data.count <= maxBytes
        else { return nil }
        return try? JSONDecoder().decode(MarketplaceCatalog.self, from: data)
    }

    private static func normalizedIdentifier(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !result.isEmpty,
              result.count <= 128,
              result.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" })
        else { return nil }
        return result
    }
}

private struct MarketplaceCatalog: Decodable {
    var name: String
    var plugins: [MarketplacePlugin]
}

private struct MarketplacePlugin: Decodable {
    var name: String
    var source: MarketplaceSource
    var policy: MarketplacePolicy?
}

private struct MarketplacePolicy: Decodable {
    var installation: String?

    var isAvailable: Bool {
        installation?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "NOT_AVAILABLE"
    }
}

private enum MarketplaceSource: Decodable {
    case local(String)
    case unsupported

    var localRelativePath: String? {
        guard case .local(let path) = self else { return nil }
        return path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case path
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            self = .local(value)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decodeIfPresent(String.self, forKey: .source)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard source == "local",
              let path = try container.decodeIfPresent(String.self, forKey: .path)
        else {
            self = .unsupported
            return
        }
        self = .local(path)
    }
}
