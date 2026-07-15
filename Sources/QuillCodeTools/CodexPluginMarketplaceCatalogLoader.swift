import Foundation
import QuillCodeCore

/// Reads the data-only portion of the Codex plugin marketplace contract.
///
/// The loader never clones repositories or executes plugin code. Local package references are
/// bounded to their marketplace workspace, and package metadata is treated as optional so a
/// catalog can still advertise an entry whose package has not been materialized yet.
public enum CodexPluginMarketplaceCatalogLoader {
    public static let defaultCatalogPaths = [
        ".agents/plugins/marketplace.json",
        ".claude-plugin/marketplace.json"
    ]
    public static let maximumCatalogBytes = 100_000
    public static let maximumPackageManifestBytes = 20_000
    public static let maximumMarketplaces = 64
    public static let maximumPluginsPerMarketplace = 128

    private static let packageManifestPaths = [
        ".codex-plugin/plugin.json",
        ".claude-plugin/plugin.json"
    ]

    public static func load(
        from roots: [URL],
        catalogPaths: [String] = defaultCatalogPaths,
        maximumMarketplaces: Int = maximumMarketplaces,
        maximumPluginsPerMarketplace: Int = maximumPluginsPerMarketplace,
        maximumCatalogBytes: Int = maximumCatalogBytes,
        maximumPackageManifestBytes: Int = maximumPackageManifestBytes
    ) -> CodexPluginMarketplaceCatalogDiscovery {
        guard maximumMarketplaces > 0,
              maximumPluginsPerMarketplace > 0,
              maximumCatalogBytes > 0,
              maximumPackageManifestBytes > 0
        else {
            return CodexPluginMarketplaceCatalogDiscovery(marketplaces: [], errors: [])
        }

        var marketplaces: [CodexPluginMarketplaceCatalog] = []
        var errors: [CodexPluginMarketplaceCatalogError] = []
        var seenCatalogPaths = Set<String>()

        for root in canonicalRoots(roots) where marketplaces.count < maximumMarketplaces {
            for relativePath in catalogPaths where marketplaces.count < maximumMarketplaces {
                guard let path = WorkspaceBoundary.safeURL(relativePath, root: root),
                      seenCatalogPaths.insert(path.path).inserted,
                      FileManager.default.fileExists(atPath: path.path)
                else { continue }

                switch readCatalog(
                    at: path,
                    root: root,
                    maximumPlugins: maximumPluginsPerMarketplace,
                    maximumCatalogBytes: maximumCatalogBytes,
                    maximumPackageManifestBytes: maximumPackageManifestBytes
                ) {
                case .success(let marketplace):
                    marketplaces.append(marketplace)
                case .failure(let message):
                    errors.append(CodexPluginMarketplaceCatalogError(
                        marketplacePath: path,
                        message: message
                    ))
                }
            }
        }

        return CodexPluginMarketplaceCatalogDiscovery(
            marketplaces: marketplaces,
            errors: errors
        )
    }

    public static func loadPackageMetadata(
        at pluginRoot: URL,
        maximumManifestBytes: Int = maximumPackageManifestBytes
    ) -> CodexPluginPackageMetadata? {
        guard maximumManifestBytes > 0 else { return nil }
        let root = pluginRoot.standardizedFileURL.resolvingSymlinksInPath()
        for relativePath in packageManifestPaths {
            guard let manifest = WorkspaceBoundary.safeURL(relativePath, root: root),
                  let data = regularFileData(at: manifest, maximumBytes: maximumManifestBytes),
                  let payload = try? JSONDecoder().decode(PackagePayload.self, from: data),
                  let name = normalizedIdentifier(payload.name)
            else { continue }

            let interface = payload.interface.map {
                interfaceMetadata($0, packageRoot: root)
            }
            return CodexPluginPackageMetadata(
                name: name,
                version: normalizedText(payload.version, maximumLength: 80),
                description: normalizedText(payload.description, maximumLength: 2_000),
                keywords: normalizedStrings(payload.keywords, maximumCount: 64, maximumLength: 80),
                interface: interface
            )
        }
        return nil
    }

    private static func canonicalRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.compactMap { root in
            let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
            return seen.insert(canonical.path).inserted ? canonical : nil
        }
    }

    private static func readCatalog(
        at path: URL,
        root: URL,
        maximumPlugins: Int,
        maximumCatalogBytes: Int,
        maximumPackageManifestBytes: Int
    ) -> CatalogReadResult {
        guard let data = regularFileData(at: path, maximumBytes: maximumCatalogBytes) else {
            return .failure("invalid marketplace file: expected a bounded regular file")
        }

        let payload: MarketplacePayload
        do {
            payload = try JSONDecoder().decode(MarketplacePayload.self, from: data)
        } catch {
            return .failure("invalid marketplace file: \(boundedErrorDescription(error))")
        }
        guard let name = normalizedIdentifier(payload.name) else {
            return .failure("invalid marketplace file: name must be a bounded identifier")
        }

        var plugins: [CodexPluginMarketplaceEntry] = []
        var seenPluginNames = Set<String>()
        for entry in payload.plugins where plugins.count < maximumPlugins {
            guard let pluginName = normalizedIdentifier(entry.name),
                  seenPluginNames.insert(pluginName).inserted,
                  let relativePath = entry.source.localRelativePath,
                  relativePath.hasPrefix("./"),
                  let packageRoot = WorkspaceBoundary.safeURL(relativePath, root: root)
            else { continue }

            let package = loadPackageMetadata(
                at: packageRoot,
                maximumManifestBytes: maximumPackageManifestBytes
            ).flatMap { metadata in
                normalizedIdentifier(metadata.name) == pluginName ? metadata : nil
            }
            plugins.append(CodexPluginMarketplaceEntry(
                name: pluginName,
                source: .local(path: packageRoot, relativePath: relativePath),
                installPolicy: entry.policy?.installPolicy ?? .available,
                authPolicy: entry.policy?.authPolicy ?? .onInstall,
                category: normalizedText(entry.category, maximumLength: 80),
                package: package
            ))
        }

        return .success(CodexPluginMarketplaceCatalog(
            name: name,
            path: path.standardizedFileURL,
            displayName: normalizedText(payload.interface?.displayName, maximumLength: 120),
            plugins: plugins
        ))
    }

    private static func regularFileData(at path: URL, maximumBytes: Int) -> Data? {
        let values = try? path.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= maximumBytes,
              let data = try? Data(contentsOf: path),
              data.count <= maximumBytes
        else { return nil }
        return data
    }

    private static func interfaceMetadata(
        _ payload: PackageInterfacePayload,
        packageRoot: URL
    ) -> CodexPluginInterfaceMetadata {
        let prompts = payload.defaultPrompts?.values ?? payload.defaultPrompt?.values
        return CodexPluginInterfaceMetadata(
            displayName: normalizedText(payload.displayName, maximumLength: 120),
            shortDescription: normalizedText(payload.shortDescription, maximumLength: 500),
            longDescription: normalizedText(payload.longDescription, maximumLength: 4_000),
            developerName: normalizedText(payload.developerName, maximumLength: 120),
            category: normalizedText(payload.category, maximumLength: 80),
            capabilities: normalizedStrings(
                payload.capabilities,
                maximumCount: 32,
                maximumLength: 80
            ),
            websiteURL: normalizedText(payload.websiteURL, maximumLength: 2_000),
            privacyPolicyURL: normalizedText(payload.privacyPolicyURL, maximumLength: 2_000),
            termsOfServiceURL: normalizedText(payload.termsOfServiceURL, maximumLength: 2_000),
            defaultPrompts: normalizedStrings(
                prompts,
                maximumCount: 3,
                maximumLength: 128
            ).nilIfEmpty,
            brandColor: normalizedText(payload.brandColor, maximumLength: 32),
            composerIcon: localAsset(payload.composerIcon, packageRoot: packageRoot),
            composerIconURL: normalizedText(payload.composerIconURL, maximumLength: 2_000),
            logo: localAsset(payload.logo, packageRoot: packageRoot),
            logoDark: localAsset(payload.logoDark, packageRoot: packageRoot),
            logoURL: normalizedText(payload.logoURL, maximumLength: 2_000),
            logoURLDark: normalizedText(payload.logoURLDark, maximumLength: 2_000),
            screenshots: localAssets(payload.screenshots, packageRoot: packageRoot),
            screenshotURLs: normalizedStrings(
                payload.screenshotURLs,
                maximumCount: 8,
                maximumLength: 2_000
            )
        )
    }

    private static func localAsset(_ value: String?, packageRoot: URL) -> URL? {
        guard let path = normalizedText(value, maximumLength: 4_096),
              !NSString(string: path).isAbsolutePath,
              let url = WorkspaceBoundary.safeURL(path, root: packageRoot)
        else { return nil }
        return url
    }

    private static func localAssets(_ values: [String]?, packageRoot: URL) -> [URL] {
        Array((values ?? []).lazy.compactMap {
            localAsset($0, packageRoot: packageRoot)
        }.prefix(8))
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let result = normalizedText(value, maximumLength: 128)?.lowercased(),
              result.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
              })
        else { return nil }
        return result
    }

    private static func normalizedText(_ value: String?, maximumLength: Int) -> String? {
        guard let result = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty,
              !result.contains("\0"),
              result.count <= maximumLength
        else { return nil }
        return result
    }

    private static func normalizedStrings(
        _ values: [String]?,
        maximumCount: Int,
        maximumLength: Int
    ) -> [String] {
        Array((values ?? []).lazy.compactMap {
            normalizedText($0, maximumLength: maximumLength)
        }.prefix(maximumCount))
    }

    private static func boundedErrorDescription(_ error: Error) -> String {
        String(error.localizedDescription.prefix(500))
    }
}

private struct MarketplacePayload: Decodable {
    var name: String
    var interface: MarketplaceInterfacePayload?
    var plugins: [MarketplacePluginPayload]
}

private enum CatalogReadResult {
    case success(CodexPluginMarketplaceCatalog)
    case failure(String)
}

private struct MarketplaceInterfacePayload: Decodable {
    var displayName: String?
}

private struct MarketplacePluginPayload: Decodable {
    var name: String
    var source: MarketplaceSourcePayload
    var policy: MarketplacePolicyPayload?
    var category: String?
}

private struct MarketplacePolicyPayload: Decodable {
    var installation: String?
    var authentication: String?

    var installPolicy: CodexPluginInstallPolicy? {
        installation.flatMap { CodexPluginInstallPolicy(rawValue: $0.uppercased()) }
    }

    var authPolicy: CodexPluginAuthPolicy? {
        authentication.flatMap { CodexPluginAuthPolicy(rawValue: $0.uppercased()) }
    }
}

private enum MarketplaceSourcePayload: Decodable {
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

private struct PackagePayload: Decodable {
    var name: String
    var version: String?
    var description: String?
    var keywords: [String]?
    var interface: PackageInterfacePayload?
}

private struct PackageInterfacePayload: Decodable {
    var displayName: String?
    var shortDescription: String?
    var longDescription: String?
    var developerName: String?
    var category: String?
    var capabilities: [String]?
    var websiteURL: String?
    var privacyPolicyURL: String?
    var termsOfServiceURL: String?
    var defaultPrompt: StringOrStringArray?
    var defaultPrompts: StringOrStringArray?
    var brandColor: String?
    var composerIcon: String?
    var composerIconURL: String?
    var logo: String?
    var logoDark: String?
    var logoURL: String?
    var logoURLDark: String?
    var screenshots: [String]?
    var screenshotURLs: [String]?
}

private struct StringOrStringArray: Decodable {
    var values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            values = [value]
        } else {
            values = try container.decode([String].self)
        }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
