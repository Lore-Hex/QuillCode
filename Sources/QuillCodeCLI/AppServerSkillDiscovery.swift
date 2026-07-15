import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

extension AppServerSession {
    private static let maximumSkillPathBytes = 4_096

    func listSkills(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let forceReload = try params.optionalBool("forceReload") ?? false
        let requestedCWDs = try stringArray(
            params.optionalArray("cwds") ?? [],
            field: "cwds",
            maximumCount: 32
        )
        let cwdRequests: [SkillCatalogCWDRequest]
        if requestedCWDs.isEmpty {
            cwdRequests = [SkillCatalogCWDRequest(
                responsePath: currentDirectory.path,
                resolvedURL: currentDirectory
            )]
        } else {
            cwdRequests = requestedCWDs.map { path in
                do {
                    return SkillCatalogCWDRequest(
                        responsePath: path,
                        resolvedURL: try resolvedCWD(path, fallback: currentDirectory)
                    )
                } catch {
                    return SkillCatalogCWDRequest(
                        responsePath: path,
                        errorMessage: "cwd must name an existing directory"
                    )
                }
            }
        }

        let data = cwdRequests.map { request -> CLIJSONValue in
            guard let cwd = request.resolvedURL else {
                return .object([
                    "cwd": .string(request.responsePath),
                    "skills": .array([]),
                    "errors": .array([.object([
                        "path": .string(request.responsePath),
                        "message": .string(request.errorMessage ?? "skill discovery failed")
                    ])])
                ])
            }
            let cacheKey = cwd.standardizedFileURL.path
            let snapshot: SkillCatalogSnapshot
            if !forceReload, let cached = cachedSkillSnapshots[cacheKey] {
                snapshot = cached
            } else {
                let resolver = SkillResolver(roots: SkillResolver.roots(
                    workspaceRoot: cwd,
                    locations: skillRootLocations,
                    extraRoots: skillExtraRoots
                ))
                snapshot = resolver.catalogSnapshot()
                cachedSkillSnapshots[cacheKey] = snapshot
            }
            return skillListEntry(cwd: request.responsePath, snapshot: snapshot)
        }
        refreshSkillWatcher(cwds: cwdRequests.compactMap(\.resolvedURL))
        return .object(["data": .array(data)])
    }

    func setSkillExtraRoots(_ value: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        guard let rawRoots = try params.optionalArray("extraRoots") else {
            throw AppServerRPCError.invalidParams("extraRoots is required")
        }
        let rootPaths = try stringArray(
            rawRoots,
            field: "extraRoots",
            maximumCount: SkillCatalog.maximumRoots
        )
        var seen = Set<String>()
        skillExtraRoots = try rootPaths.compactMap { path in
            guard NSString(string: path).isAbsolutePath else {
                throw AppServerRPCError.invalidParams("extraRoots must contain absolute paths")
            }
            let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            return seen.insert(root.path).inserted ? root : nil
        }
        cachedSkillSnapshots.removeAll(keepingCapacity: true)
        refreshSkillWatcher()
        await sendNotification("skills/changed", params: .object([:]))
        return .object([:])
    }

    func writeSkillConfig(_ value: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        guard let enabled = try params.optionalBool("enabled") else {
            throw AppServerRPCError.invalidParams("enabled is required")
        }
        let path = try params.optionalString("path")
        let name = try params.optionalString("name")
        guard (path == nil) != (name == nil) else {
            throw AppServerRPCError.invalidParams(
                "skills/config/write requires exactly one of path or name"
            )
        }

        var nextConfig = appConfig
        let changed: Bool
        if let path {
            guard SkillConfiguration.normalizedPath(path) != nil else {
                throw AppServerRPCError.invalidParams("path must be a bounded absolute path")
            }
            changed = nextConfig.skillConfiguration.setPath(path, enabled: enabled)
        } else if let name {
            guard SkillConfiguration.normalizedName(name) != nil else {
                throw AppServerRPCError.invalidParams("name must be a bounded non-empty string")
            }
            changed = nextConfig.skillConfiguration.setName(name, enabled: enabled)
        } else {
            throw AppServerRPCError.invalidParams(
                "skills/config/write requires exactly one of path or name"
            )
        }

        if changed {
            do {
                try ConfigStore(fileURL: paths.configFile).save(nextConfig)
            } catch {
                throw AppServerRPCError.internalError(
                    "failed to update skill settings: \(error.localizedDescription)"
                )
            }
            appConfig = nextConfig
            cachedSkillSnapshots.removeAll(keepingCapacity: true)
            await sendNotification("skills/changed", params: .object([:]))
        }
        return .object(["effectiveEnabled": .bool(enabled)])
    }

    var skillRootLocations: SkillRootLocations {
        if request.home != nil {
            return .isolated(quillCodeHome: paths.home)
        }
        return .live(quillCodeHome: paths.home)
    }

    private func skillListEntry(
        cwd: String,
        snapshot: SkillCatalogSnapshot
    ) -> CLIJSONValue {
        .object([
            "cwd": .string(cwd),
            "skills": .array(snapshot.skills.map(skillMetadata)),
            "errors": .array(snapshot.errors.map { error in
                .object([
                    "path": .string(error.path.standardizedFileURL.path),
                    "message": .string(error.message)
                ])
            })
        ])
    }

    private func skillMetadata(_ skill: SkillCatalogMetadata) -> CLIJSONValue {
        .object([
            "name": .string(skill.name),
            "description": .string(skill.description),
            "shortDescription": optionalString(skill.shortDescription),
            "interface": skill.interface.map(skillInterface) ?? .null,
            "dependencies": skill.dependencies.isEmpty
                ? .null
                : .object(["tools": .array(skill.dependencies.map(skillDependency))]),
            "path": .string(skill.path.standardizedFileURL.path),
            "scope": .string(skill.scope.protocolScope),
            "enabled": .bool(appConfig.skillConfiguration.isEnabled(
                name: skill.name,
                manifestPath: skill.path
            ))
        ])
    }

    private func skillInterface(_ interface: SkillInterfaceMetadata) -> CLIJSONValue {
        .object([
            "displayName": optionalString(interface.displayName),
            "shortDescription": optionalString(interface.shortDescription),
            "iconSmall": optionalString(interface.iconSmall?.standardizedFileURL.path),
            "iconLarge": optionalString(interface.iconLarge?.standardizedFileURL.path),
            "brandColor": optionalString(interface.brandColor),
            "defaultPrompt": optionalString(interface.defaultPrompt)
        ])
    }

    private func skillDependency(_ dependency: SkillToolDependencyMetadata) -> CLIJSONValue {
        .object([
            "type": .string(dependency.type),
            "value": .string(dependency.value),
            "description": optionalString(dependency.description),
            "transport": optionalString(dependency.transport),
            "command": optionalString(dependency.command),
            "url": optionalString(dependency.url)
        ])
    }

    private func optionalString(_ value: String?) -> CLIJSONValue {
        value.map(CLIJSONValue.string) ?? .null
    }

    private func stringArray(
        _ values: [CLIJSONValue],
        field: String,
        maximumCount: Int
    ) throws -> [String] {
        guard values.count <= maximumCount else {
            throw AppServerRPCError.invalidParams(
                "\(field) cannot contain more than \(maximumCount) entries"
            )
        }
        return try values.enumerated().map { index, value in
            guard let string = value.stringValue,
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppServerRPCError.invalidParams(
                    "\(field)[\(index)] must be a non-empty string"
                )
            }
            guard string.utf8.count <= Self.maximumSkillPathBytes else {
                throw AppServerRPCError.invalidParams(
                    "\(field)[\(index)] exceeds the \(Self.maximumSkillPathBytes)-byte limit"
                )
            }
            return string
        }
    }
}

private struct SkillCatalogCWDRequest {
    var responsePath: String
    var resolvedURL: URL?
    var errorMessage: String?

    init(responsePath: String, resolvedURL: URL? = nil, errorMessage: String? = nil) {
        self.responsePath = responsePath
        self.resolvedURL = resolvedURL
        self.errorMessage = errorMessage
    }
}
