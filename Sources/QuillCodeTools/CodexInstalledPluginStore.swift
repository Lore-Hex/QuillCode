import Foundation
import QuillCodeCore

public struct CodexInstalledPluginPackage: Sendable, Hashable {
    public var id: String
    public var pluginName: String
    public var marketplaceName: String
    public var root: URL
    public var metadata: CodexPluginPackageMetadata

    public init(
        id: String,
        pluginName: String,
        marketplaceName: String,
        root: URL,
        metadata: CodexPluginPackageMetadata
    ) {
        self.id = id
        self.pluginName = pluginName
        self.marketplaceName = marketplaceName
        self.root = root
        self.metadata = metadata
    }
}

/// Owns the Codex-compatible global plugin cache under `plugins/cache/<marketplace>/<plugin>`.
public struct CodexInstalledPluginStore: Sendable {
    public static let maximumMarketplaces = 64
    public static let maximumPluginsPerMarketplace = 128

    public var home: URL

    public init(home: URL) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
    }

    @discardableResult
    public func install(
        source: URL,
        pluginName: String,
        marketplaceName: String
    ) throws -> CodexInstalledPluginPackage {
        let pluginName = try BoundedPluginPackageInstaller.normalizedIdentifier(pluginName)
        let marketplaceName = try BoundedPluginPackageInstaller.normalizedIdentifier(marketplaceName)
        let marketplaceRoot = cacheRoot.appendingPathComponent(marketplaceName, isDirectory: true)
        let destination = marketplaceRoot.appendingPathComponent(pluginName, isDirectory: true)
        let installedRoot = try BoundedPluginPackageInstaller.install(
            source: source,
            expectedPluginName: pluginName,
            destination: destination,
            destinationRoot: marketplaceRoot,
            replaceExisting: true
        )
        guard let metadata = CodexPluginMarketplaceCatalogLoader.loadPackageMetadata(at: installedRoot),
              metadata.name == pluginName
        else {
            try? FileManager.default.removeItem(at: installedRoot)
            throw PluginPackageInstallError.invalidManifest
        }
        return CodexInstalledPluginPackage(
            id: "\(pluginName)@\(marketplaceName)",
            pluginName: pluginName,
            marketplaceName: marketplaceName,
            root: installedRoot,
            metadata: metadata
        )
    }

    /// Uninstall is intentionally idempotent, matching the app-server contract.
    public func uninstall(pluginID: String) throws {
        let identity = try Self.parse(pluginID: pluginID)
        let marketplaceRoot = cacheRoot.appendingPathComponent(
            identity.marketplace,
            isDirectory: true
        )
        let destination = marketplaceRoot.appendingPathComponent(identity.plugin, isDirectory: true)
        guard WorkspaceBoundary.isWithin(destination, root: cacheRoot),
              destination.deletingLastPathComponent().path == marketplaceRoot.path
        else {
            throw PluginPackageInstallError.invalidDestination
        }
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        let values = try? destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              destination.resolvingSymlinksInPath().path == destination.path
        else {
            throw PluginPackageInstallError.invalidDestination
        }
        try FileManager.default.removeItem(at: destination)
        removeMarketplaceIfEmpty(marketplaceRoot)
    }

    public func packages() -> [CodexInstalledPluginPackage] {
        Self.packages(in: home)
    }

    public static func packages(in home: URL) -> [CodexInstalledPluginPackage] {
        let store = CodexInstalledPluginStore(home: home)
        guard let marketplaceRoots = boundedDirectories(
            in: store.cacheRoot,
            root: store.home,
            limit: maximumMarketplaces
        ) else { return [] }

        return marketplaceRoots.flatMap { marketplaceRoot -> [CodexInstalledPluginPackage] in
            guard let marketplace = try? BoundedPluginPackageInstaller.normalizedIdentifier(
                marketplaceRoot.lastPathComponent
            ),
            marketplace == marketplaceRoot.lastPathComponent,
            let pluginRoots = boundedDirectories(
                in: marketplaceRoot,
                root: store.home,
                limit: maximumPluginsPerMarketplace
            ) else { return [] }

            return pluginRoots.compactMap { pluginRoot in
                guard let plugin = try? BoundedPluginPackageInstaller.normalizedIdentifier(
                    pluginRoot.lastPathComponent
                ),
                plugin == pluginRoot.lastPathComponent,
                let metadata = CodexPluginMarketplaceCatalogLoader.loadPackageMetadata(at: pluginRoot),
                metadata.name == plugin
                else { return nil }
                return CodexInstalledPluginPackage(
                    id: "\(plugin)@\(marketplace)",
                    pluginName: plugin,
                    marketplaceName: marketplace,
                    root: pluginRoot,
                    metadata: metadata
                )
            }
        }
        .sorted { $0.id < $1.id }
    }

    public static func marketplaceDirectories(in home: URL) -> [URL] {
        var seen = Set<String>()
        return packages(in: home).compactMap { package in
            let directory = package.root.deletingLastPathComponent()
            return seen.insert(directory.path).inserted ? directory : nil
        }
    }

    public var cacheRoot: URL {
        home
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
    }

    private static func parse(pluginID: String) throws -> (plugin: String, marketplace: String) {
        let components = pluginID.split(separator: "@", omittingEmptySubsequences: false)
        guard components.count == 2 else {
            throw PluginPackageInstallError.invalidPluginName
        }
        return (
            try BoundedPluginPackageInstaller.normalizedIdentifier(String(components[0])),
            try BoundedPluginPackageInstaller.normalizedIdentifier(String(components[1]))
        )
    }

    private static func boundedDirectories(in directory: URL, root: URL, limit: Int) -> [URL]? {
        let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              directory.resolvingSymlinksInPath().path == directory.path,
              WorkspaceBoundary.isWithin(directory, root: root)
        else { return nil }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(limit).compactMap {
            // Foundation may enumerate a `/var` child as `/private/var` on macOS. Rebuild
            // the direct child from the validated parent so boundary checks use one spelling.
            let candidate = directory.appendingPathComponent($0.lastPathComponent, isDirectory: true)
            let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true,
                  values?.isSymbolicLink != true,
                  candidate.resolvingSymlinksInPath().path == candidate.path,
                  WorkspaceBoundary.isWithin(candidate, root: root)
            else { return nil }
            return candidate
        }
    }

    private func removeMarketplaceIfEmpty(_ marketplaceRoot: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: marketplaceRoot,
            includingPropertiesForKeys: nil,
            options: []
        ), entries.isEmpty else { return }
        try? FileManager.default.removeItem(at: marketplaceRoot)
    }
}
