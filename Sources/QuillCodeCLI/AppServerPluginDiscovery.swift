import Foundation
import QuillCodeTools

extension AppServerSession {
    private static let maximumPluginCWDs = 32
    private static let maximumPluginPathBytes = 4_096
    private static let maximumInstallSuggestions = 64
    private static let supportedPluginMarketplaceKinds: Set<String> = [
        "local",
        "vertical",
        "workspace-directory",
        "shared-with-me",
        "created-by-me-remote"
    ]

    func listPlugins(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let roots = try pluginDiscoveryRoots(params)
        guard try pluginMarketplaceKinds(params).contains("local") else {
            return pluginDiscoveryResponse(marketplaces: [], errors: [], includesFeatured: true)
        }
        return pluginDiscoveryResponse(
            roots: roots,
            installSuggestions: nil,
            includesFeatured: true
        )
    }

    func listInstalledPlugins(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let roots = try pluginDiscoveryRoots(params)
        let suggestions = try pluginInstallSuggestions(params)
        return pluginDiscoveryResponse(
            roots: roots,
            installSuggestions: suggestions,
            includesFeatured: false
        )
    }

    private func pluginDiscoveryResponse(
        roots: [URL],
        installSuggestions: Set<String>?,
        includesFeatured: Bool
    ) -> CLIJSONValue {
        let discovery = CodexPluginMarketplaceCatalogLoader.load(from: roots)
        let installed = AppServerInstalledPluginStateLoader.load(
            roots: roots,
            quillCodeHome: paths.home
        )
        let marketplaces = mergePluginMarketplaces(
            discovery.marketplaces,
            installed: installed,
            installSuggestions: installSuggestions
        )
        return pluginDiscoveryResponse(
            marketplaces: marketplaces,
            errors: discovery.errors,
            includesFeatured: includesFeatured
        )
    }

    private func pluginDiscoveryResponse(
        marketplaces: [AppServerPluginMarketplace],
        errors: [CodexPluginMarketplaceCatalogError],
        includesFeatured: Bool
    ) -> CLIJSONValue {
        var result: [String: CLIJSONValue] = [
            "marketplaces": .array(marketplaces.map(pluginMarketplaceValue)),
            "marketplaceLoadErrors": .array(errors.map { error in
                .object([
                    "marketplacePath": .string(error.marketplacePath.standardizedFileURL.path),
                    "message": .string(error.message)
                ])
            })
        ]
        if includesFeatured {
            result["featuredPluginIds"] = .array([])
        }
        return .object(result)
    }

    private func pluginDiscoveryRoots(_ params: AppServerParams) throws -> [URL] {
        let requested = try params.optionalArray("cwds") ?? []
        guard requested.count <= Self.maximumPluginCWDs else {
            throw AppServerRPCError.invalidParams(
                "cwds cannot contain more than \(Self.maximumPluginCWDs) entries"
            )
        }

        var roots = [paths.home.standardizedFileURL.resolvingSymlinksInPath()]
        var seen = Set(roots.map(\.path))
        for (index, value) in requested.enumerated() {
            guard let path = value.stringValue,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  path.utf8.count <= Self.maximumPluginPathBytes,
                  NSString(string: path).isAbsolutePath
            else {
                throw AppServerRPCError.invalidRequest(
                    "cwds[\(index)] must be a bounded absolute path"
                )
            }
            let root = URL(fileURLWithPath: path, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if seen.insert(root.path).inserted { roots.append(root) }
        }
        return roots
    }

    private func pluginMarketplaceKinds(_ params: AppServerParams) throws -> Set<String> {
        guard let values = try params.optionalArray("marketplaceKinds") else {
            return ["local"]
        }
        guard values.count <= Self.supportedPluginMarketplaceKinds.count else {
            throw AppServerRPCError.invalidParams("marketplaceKinds contains too many entries")
        }
        return try Set(values.enumerated().map { index, value in
            guard let kind = value.stringValue,
                  Self.supportedPluginMarketplaceKinds.contains(kind)
            else {
                throw AppServerRPCError.invalidParams(
                    "marketplaceKinds[\(index)] is not a supported marketplace kind"
                )
            }
            return kind
        })
    }

    private func pluginInstallSuggestions(_ params: AppServerParams) throws -> Set<String> {
        guard let values = try params.optionalArray("installSuggestionPluginNames") else {
            return []
        }
        guard values.count <= Self.maximumInstallSuggestions else {
            throw AppServerRPCError.invalidParams(
                "installSuggestionPluginNames cannot contain more than "
                    + "\(Self.maximumInstallSuggestions) entries"
            )
        }
        return try Set(values.enumerated().map { index, value in
            guard let name = value.stringValue,
                  let normalized = normalizedPluginIdentifier(name)
            else {
                throw AppServerRPCError.invalidParams(
                    "installSuggestionPluginNames[\(index)] must be a bounded plugin identifier"
                )
            }
            return normalized
        })
    }

    private func mergePluginMarketplaces(
        _ catalogs: [CodexPluginMarketplaceCatalog],
        installed: [String: AppServerInstalledPluginState],
        installSuggestions: Set<String>?
    ) -> [AppServerPluginMarketplace] {
        var marketplaces: [AppServerPluginMarketplace] = []
        var marketplaceIndexes: [String: Int] = [:]

        for catalog in catalogs {
            let marketplaceIndex: Int
            if let existing = marketplaceIndexes[catalog.name] {
                marketplaceIndex = existing
            } else {
                marketplaceIndex = marketplaces.count
                marketplaceIndexes[catalog.name] = marketplaceIndex
                marketplaces.append(AppServerPluginMarketplace(
                    name: catalog.name,
                    path: catalog.path,
                    displayName: catalog.displayName,
                    plugins: []
                ))
            }

            for entry in catalog.plugins {
                let state = installed[entry.name]
                let shouldInclude = installSuggestions.map { suggestions in
                    state != nil || suggestions.contains(entry.name)
                } ?? true
                guard shouldInclude else { continue }

                let row = AppServerPluginRow(entry: entry, installedState: state)
                if let existingIndex = marketplaces[marketplaceIndex].plugins.firstIndex(
                    where: { $0.entry.name == entry.name }
                ) {
                    marketplaces[marketplaceIndex].plugins[existingIndex].merge(row)
                } else {
                    marketplaces[marketplaceIndex].plugins.append(row)
                }
            }
        }
        return marketplaces.filter { !$0.plugins.isEmpty }
    }

    private func pluginMarketplaceValue(_ marketplace: AppServerPluginMarketplace) -> CLIJSONValue {
        .object([
            "name": .string(marketplace.name),
            "path": .string(marketplace.path.standardizedFileURL.path),
            "interface": marketplace.displayName.map { displayName in
                .object(["displayName": .string(displayName)])
            } ?? .null,
            "plugins": .array(marketplace.plugins.map {
                pluginSummaryValue($0, marketplaceName: marketplace.name)
            })
        ])
    }

    private func pluginSummaryValue(
        _ row: AppServerPluginRow,
        marketplaceName: String
    ) -> CLIJSONValue {
        let installed = row.installedState != nil
        return .object([
            "id": .string("\(row.entry.name)@\(marketplaceName)"),
            "remotePluginId": .null,
            "localVersion": pluginOptionalString(
                row.installedState?.version ?? row.entry.package?.version
            ),
            "name": .string(row.entry.name),
            "shareContext": .null,
            "source": .object([
                "type": .string("local"),
                "path": .string(row.entry.source.localPath.standardizedFileURL.path)
            ]),
            "installed": .bool(installed),
            "enabled": .bool(installed && row.installedState?.enabled == true),
            "installPolicy": .string(row.entry.installPolicy.rawValue),
            "authPolicy": .string(row.entry.authPolicy.rawValue),
            "availability": .string("AVAILABLE"),
            "interface": pluginInterfaceValue(row.entry),
            "keywords": .array((row.entry.package?.keywords ?? []).map(CLIJSONValue.string))
        ])
    }

    private func pluginInterfaceValue(_ entry: CodexPluginMarketplaceEntry) -> CLIJSONValue {
        guard let metadata = entry.package?.interface ?? entry.category.map({ _ in
            CodexPluginInterfaceMetadata()
        }) else { return .null }
        return .object([
            "displayName": pluginOptionalString(metadata.displayName),
            "shortDescription": pluginOptionalString(metadata.shortDescription),
            "longDescription": pluginOptionalString(metadata.longDescription),
            "developerName": pluginOptionalString(metadata.developerName),
            "category": pluginOptionalString(entry.category ?? metadata.category),
            "capabilities": .array(metadata.capabilities.map(CLIJSONValue.string)),
            "websiteUrl": pluginOptionalString(metadata.websiteURL),
            "privacyPolicyUrl": pluginOptionalString(metadata.privacyPolicyURL),
            "termsOfServiceUrl": pluginOptionalString(metadata.termsOfServiceURL),
            "defaultPrompt": metadata.defaultPrompts.map {
                .array($0.map(CLIJSONValue.string))
            } ?? .null,
            "brandColor": pluginOptionalString(metadata.brandColor),
            "composerIcon": pluginOptionalPath(metadata.composerIcon),
            "composerIconUrl": pluginOptionalString(metadata.composerIconURL),
            "logo": pluginOptionalPath(metadata.logo),
            "logoDark": pluginOptionalPath(metadata.logoDark),
            "logoUrl": pluginOptionalString(metadata.logoURL),
            "logoUrlDark": pluginOptionalString(metadata.logoURLDark),
            "screenshots": .array(metadata.screenshots.map {
                .string($0.standardizedFileURL.path)
            }),
            "screenshotUrls": .array(metadata.screenshotURLs.map(CLIJSONValue.string))
        ])
    }

    private func pluginOptionalString(_ value: String?) -> CLIJSONValue {
        value.map(CLIJSONValue.string) ?? .null
    }

    private func pluginOptionalPath(_ value: URL?) -> CLIJSONValue {
        value.map { .string($0.standardizedFileURL.path) } ?? .null
    }

    private func normalizedPluginIdentifier(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !result.isEmpty,
              result.count <= 128,
              result.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
              })
        else { return nil }
        return result
    }
}

private struct AppServerPluginMarketplace {
    var name: String
    var path: URL
    var displayName: String?
    var plugins: [AppServerPluginRow]
}

private struct AppServerPluginRow {
    var entry: CodexPluginMarketplaceEntry
    var installedState: AppServerInstalledPluginState?

    mutating func merge(_ other: AppServerPluginRow) {
        if entry.package == nil, other.entry.package != nil {
            entry = other.entry
        }
        guard let otherState = other.installedState else { return }
        if let state = installedState {
            installedState = AppServerInstalledPluginState(
                version: state.version ?? otherState.version,
                enabled: state.enabled || otherState.enabled
            )
        } else {
            installedState = otherState
        }
    }
}
