import Foundation
import QuillCodeTools

extension AppServerSession {
    static let maximumPluginPathBytes = 4_096

    func pluginMarketplaceValue(_ marketplace: AppServerPluginMarketplace) -> CLIJSONValue {
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

    func pluginSummaryValue(
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

    func pluginInterfaceValue(_ entry: CodexPluginMarketplaceEntry) -> CLIJSONValue {
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

    func pluginOptionalString(_ value: String?) -> CLIJSONValue {
        value.map(CLIJSONValue.string) ?? .null
    }

    func pluginOptionalPath(_ value: URL?) -> CLIJSONValue {
        value.map { .string($0.standardizedFileURL.path) } ?? .null
    }

    func normalizedPluginIdentifier(_ value: String) -> String? {
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

struct AppServerPluginMarketplace {
    var name: String
    var path: URL
    var displayName: String?
    var plugins: [AppServerPluginRow]
}

struct AppServerPluginRow {
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
