import Foundation
import QuillCodeCore
import QuillCodeTools

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
        let discovery = CodexPluginMarketplaceCatalogLoader.load(
            from: [root],
            catalogPaths: catalogPaths,
            maximumMarketplaces: catalogPaths.count,
            maximumPluginsPerMarketplace: CodexPluginMarketplaceCatalogLoader.maximumPluginsPerMarketplace,
            maximumCatalogBytes: maxCatalogBytes,
            maximumPackageManifestBytes: maxPluginManifestBytes
        )

        for catalog in discovery.marketplaces where manifests.count < maxPlugins {
            guard let catalogPath = WorkspaceBoundary.safeRelativePath(catalog.path.path, root: root) else {
                continue
            }
            for entry in catalog.plugins where manifests.count < maxPlugins {
                let source = entry.source.localRelativePath
                guard entry.installPolicy != .notAvailable,
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

    private static func normalizedIdentifier(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !result.isEmpty,
              result.count <= 128,
              result.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" })
        else { return nil }
        return result
    }
}
