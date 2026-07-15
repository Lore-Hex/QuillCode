import Foundation
import QuillCodeCore
import Yams

/// Discovers and parses Open Agent Skills without injecting their instruction bodies into context.
/// The bounded metadata snapshot is shared by the live resolver and the app-server catalog.
public struct SkillCatalog: Sendable {
    public static let maximumRoots = 64
    public static let maximumDirectoriesPerRoot = 2_000
    public static let maximumSkills = 2_000
    public static let maximumScanDepth = 6
    public static let maximumManifestBytes = 64_000
    public static let maximumMetadataBytes = 32_000

    public var roots: [SkillRoot]

    public init(roots: [SkillRoot]) {
        self.roots = Array(roots.prefix(Self.maximumRoots))
    }

    public func load() -> SkillCatalogSnapshot {
        var skills: [SkillCatalogMetadata] = []
        var errors: [SkillCatalogError] = []
        var seenManifestPaths = Set<String>()

        for root in roots where skills.count < Self.maximumSkills {
            let discovery = discoverManifests(in: root)
            errors.append(contentsOf: discovery.errors)
            for manifest in discovery.manifests where skills.count < Self.maximumSkills {
                let identity = manifest.standardizedFileURL.resolvingSymlinksInPath().path
                guard seenManifestPaths.insert(identity).inserted else { continue }
                do {
                    skills.append(try parseSkill(at: manifest, scope: root.kind))
                } catch {
                    errors.append(SkillCatalogError(path: manifest, message: String(describing: error)))
                }
            }
        }

        return SkillCatalogSnapshot(skills: skills, errors: errors)
    }

    private func discoverManifests(in root: SkillRoot) -> SkillManifestDiscovery {
        let fileManager = FileManager.default
        let rootURL = root.url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            return SkillManifestDiscovery()
        }
        guard isDirectory.boolValue else {
            return SkillManifestDiscovery(errors: [
                SkillCatalogError(path: rootURL, message: "skill root is not a directory")
            ])
        }

        var manifests: [URL] = []
        var errors: [SkillCatalogError] = []
        var visitedDirectories = Set<String>()
        var directoryCount = 0

        func walk(_ directory: URL, depth: Int) {
            guard depth <= Self.maximumScanDepth,
                  manifests.count < Self.maximumSkills,
                  directoryCount < Self.maximumDirectoriesPerRoot
            else { return }

            let canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
            guard visitedDirectories.insert(canonicalDirectory.path).inserted else { return }
            directoryCount += 1

            let entries: [URL]
            do {
                entries = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                errors.append(SkillCatalogError(
                    path: directory,
                    message: "failed to read skill directory: \(error.localizedDescription)"
                ))
                return
            }

            for entry in entries where manifests.count < Self.maximumSkills {
                let values = try? entry.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ])
                let isSymbolicLink = values?.isSymbolicLink == true
                if entry.lastPathComponent == SkillResolver.manifestFileName,
                   values?.isRegularFile == true,
                   !isSymbolicLink {
                    manifests.append(entry.standardizedFileURL.resolvingSymlinksInPath())
                    continue
                }
                let resolvedDirectory = entry.standardizedFileURL.resolvingSymlinksInPath()
                let targetIsDirectory = isSymbolicLink
                    ? (try? resolvedDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    : values?.isDirectory == true
                guard depth < Self.maximumScanDepth,
                      targetIsDirectory,
                      (!isSymbolicLink || root.kind.followsDirectorySymlinks)
                else { continue }
                walk(isSymbolicLink ? resolvedDirectory : entry, depth: depth + 1)
            }
        }

        walk(rootURL, depth: 0)
        return SkillManifestDiscovery(manifests: manifests, errors: errors)
    }

    private func parseSkill(at manifest: URL, scope: SkillRootKind) throws -> SkillCatalogMetadata {
        let contents = try boundedUTF8(at: manifest, maximumBytes: Self.maximumManifestBytes)
        let frontmatterText = try SkillFrontmatter.extract(from: contents)
        let frontmatter: SkillFrontmatter
        do {
            frontmatter = try YAMLDecoder().decode(SkillFrontmatter.self, from: frontmatterText)
        } catch {
            throw SkillCatalogParseError.invalidFrontmatter(error.localizedDescription)
        }

        let defaultName = manifest.deletingLastPathComponent().lastPathComponent
        let name = Self.singleLine(frontmatter.name) ?? defaultName
        guard SkillResolver.isSafeSkillName(name), name.count <= 64 else {
            throw SkillCatalogParseError.invalidName
        }
        guard let description = Self.singleLine(frontmatter.description),
              !description.isEmpty else {
            throw SkillCatalogParseError.missingDescription
        }
        guard description.count <= 1_024 else {
            throw SkillCatalogParseError.descriptionTooLong
        }
        let shortDescription = Self.limitedSingleLine(
            frontmatter.shortDescription ?? frontmatter.metadata?.shortDescription,
            maximum: 1_024
        )
        let optionalMetadata = loadOptionalMetadata(for: manifest)

        return SkillCatalogMetadata(
            name: name,
            description: description,
            shortDescription: shortDescription,
            interface: optionalMetadata.interface,
            dependencies: optionalMetadata.dependencies,
            productRestrictions: optionalMetadata.productRestrictions,
            path: manifest.standardizedFileURL.resolvingSymlinksInPath(),
            scope: scope
        )
    }

    private func loadOptionalMetadata(for manifest: URL) -> LoadedOptionalMetadata {
        let skillDirectory = manifest.deletingLastPathComponent().standardizedFileURL
        let metadataURL = skillDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("openai.yaml", isDirectory: false)
        guard WorkspaceBoundary.isWithin(metadataURL, root: skillDirectory),
              let contents = try? boundedUTF8(
            at: metadataURL,
            maximumBytes: Self.maximumMetadataBytes
        ),
              let payload = try? YAMLDecoder().decode(SkillMetadataPayload.self, from: contents)
        else { return LoadedOptionalMetadata() }

        let interface = payload.interface.flatMap { payload in
            let value = SkillInterfaceMetadata(
                displayName: Self.limitedSingleLine(payload.displayName, maximum: 64),
                shortDescription: Self.limitedSingleLine(payload.shortDescription, maximum: 1_024),
                iconSmall: Self.resolveIcon(payload.iconSmall, inside: skillDirectory),
                iconLarge: Self.resolveIcon(payload.iconLarge, inside: skillDirectory),
                brandColor: Self.validBrandColor(payload.brandColor),
                defaultPrompt: Self.limitedSingleLine(payload.defaultPrompt, maximum: 1_024)
            )
            return value.isEmpty ? nil : value
        }
        let dependencyPayloads: [SkillMetadataPayload.ToolPayload] = payload.dependencies?.tools ?? []
        let dependencies: [SkillToolDependencyMetadata] = dependencyPayloads.compactMap { dependency in
            guard let type = Self.limitedSingleLine(dependency.type, maximum: 64),
                  let value = Self.limitedSingleLine(dependency.value, maximum: 1_024)
            else { return nil }
            return SkillToolDependencyMetadata(
                type: type,
                value: value,
                description: Self.limitedSingleLine(dependency.description, maximum: 1_024),
                transport: Self.limitedSingleLine(dependency.transport, maximum: 64),
                command: Self.limitedSingleLine(dependency.command, maximum: 1_024),
                url: Self.limitedSingleLine(dependency.url, maximum: 1_024)
            )
        }
        let productRestrictions = Array(Set((payload.policy?.products ?? []).compactMap {
            Self.limitedSingleLine($0, maximum: 64)?.uppercased()
        }).sorted().prefix(32))
        return LoadedOptionalMetadata(
            interface: interface,
            dependencies: dependencies,
            productRestrictions: productRestrictions
        )
    }

    private func boundedUTF8(at url: URL, maximumBytes: Int) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw SkillCatalogParseError.notARegularFile
        }
        guard (values.fileSize ?? maximumBytes + 1) <= maximumBytes else {
            throw SkillCatalogParseError.fileTooLarge(maximumBytes)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else {
            throw SkillCatalogParseError.fileTooLarge(maximumBytes)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw SkillCatalogParseError.invalidUTF8
        }
        return string
    }

    private static func resolveIcon(_ rawPath: String?, inside skillDirectory: URL) -> URL? {
        guard let rawPath = limitedSingleLine(rawPath, maximum: 1_024),
              !NSString(string: rawPath).isAbsolutePath else { return nil }
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.first == "assets",
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let candidate = components.reduce(skillDirectory) { url, component in
            url.appendingPathComponent(component, isDirectory: false)
        }.standardizedFileURL
        guard WorkspaceBoundary.isWithin(candidate, root: skillDirectory) else { return nil }
        return candidate
    }

    private static func validBrandColor(_ raw: String?) -> String? {
        guard let value = singleLine(raw), value.count == 7, value.first == "#" else { return nil }
        guard value.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return value
    }

    private static func singleLine(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return value.isEmpty ? nil : value
    }

    private static func limitedSingleLine(_ raw: String?, maximum: Int) -> String? {
        guard let value = singleLine(raw), value.count <= maximum else { return nil }
        return value
    }
}

private struct SkillManifestDiscovery {
    var manifests: [URL] = []
    var errors: [SkillCatalogError] = []
}

private struct LoadedOptionalMetadata {
    var interface: SkillInterfaceMetadata?
    var dependencies: [SkillToolDependencyMetadata] = []
    var productRestrictions: [String] = []
}

private struct SkillFrontmatter: Decodable {
    var name: String?
    var description: String?
    var shortDescription: String?
    var metadata: LegacyMetadata?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case shortDescription = "short_description"
        case metadata
    }

    struct LegacyMetadata: Decodable {
        var shortDescription: String?

        enum CodingKeys: String, CodingKey {
            case shortDescription = "short-description"
        }
    }

    static func extract(from contents: String) throws -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let opening = lines.popFirst(), opening.trimmingCharacters(in: .whitespaces) == "---" else {
            throw SkillCatalogParseError.missingFrontmatter
        }
        var frontmatter: [Substring] = []
        while let line = lines.popFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                guard !frontmatter.isEmpty else { throw SkillCatalogParseError.missingFrontmatter }
                return frontmatter.joined(separator: "\n")
            }
            frontmatter.append(line)
        }
        throw SkillCatalogParseError.missingFrontmatter
    }
}

private struct SkillMetadataPayload: Decodable {
    var interface: InterfacePayload?
    var dependencies: DependenciesPayload?
    var policy: PolicyPayload?

    struct InterfacePayload: Decodable {
        var displayName: String?
        var shortDescription: String?
        var iconSmall: String?
        var iconLarge: String?
        var brandColor: String?
        var defaultPrompt: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case shortDescription = "short_description"
            case iconSmall = "icon_small"
            case iconLarge = "icon_large"
            case brandColor = "brand_color"
            case defaultPrompt = "default_prompt"
        }
    }

    struct DependenciesPayload: Decodable {
        var tools: [ToolPayload] = []
    }

    struct PolicyPayload: Decodable {
        var products: [String] = []
    }

    struct ToolPayload: Decodable {
        var type: String?
        var value: String?
        var description: String?
        var transport: String?
        var command: String?
        var url: String?
    }
}

private enum SkillCatalogParseError: Error, CustomStringConvertible {
    case missingFrontmatter
    case invalidFrontmatter(String)
    case invalidName
    case missingDescription
    case descriptionTooLong
    case notARegularFile
    case fileTooLarge(Int)
    case invalidUTF8

    var description: String {
        switch self {
        case .missingFrontmatter:
            return "missing YAML frontmatter delimited by ---"
        case .invalidFrontmatter(let detail):
            return "invalid YAML frontmatter: \(detail)"
        case .invalidName:
            return "skill name must be a safe single component of at most 64 characters"
        case .missingDescription:
            return "missing field `description`"
        case .descriptionTooLong:
            return "description exceeds 1024 characters"
        case .notARegularFile:
            return "skill manifest is not a regular file"
        case .fileTooLarge(let maximum):
            return "skill metadata exceeds the \(maximum)-byte limit"
        case .invalidUTF8:
            return "skill metadata is not valid UTF-8"
        }
    }
}

private extension SkillInterfaceMetadata {
    var isEmpty: Bool {
        displayName == nil
            && shortDescription == nil
            && iconSmall == nil
            && iconLarge == nil
            && brandColor == nil
            && defaultPrompt == nil
    }
}
