import Foundation
import QuillCodeCore
import QuillCodeTools

/// Resolves app-server rich input against the same bounded skill catalog used by `skills/list` and
/// `host.skill.load`. A client-selected path must identify an enabled discovered skill exactly;
/// arbitrary paths are never read.
struct AppServerRichTurnInputResolver: Sendable {
    static let maximumNameBytes = 1_024
    static let maximumPathBytes = 8_192
    static let maximumContextBytes = 256 * 1_024

    var cwd: URL
    var skillResolver: SkillResolver

    func skill(name requestedName: String, path rawPath: String) throws -> ChatInputReference {
        let name = try boundedSingleLine(requestedName, field: "skill name", maximumBytes: Self.maximumNameBytes)
        let path = try boundedSingleLine(rawPath, field: "skill path", maximumBytes: Self.maximumPathBytes)
        let selectedPath = canonicalFileURL(path)
        let snapshot = skillResolver.catalogSnapshot()
        guard let skill = snapshot.skills.first(where: {
            $0.path.standardizedFileURL.resolvingSymlinksInPath() == selectedPath
                && skillResolver.isEnabled($0)
        }) else {
            throw AppServerRPCError.invalidParams(
                "selected skill \(name) is not an enabled skill returned by skills/list"
            )
        }

        let contents = try boundedSkillContents(at: skill.path)
        return ChatInputReference(
            kind: .skill,
            name: skill.name,
            path: skill.path.standardizedFileURL.resolvingSymlinksInPath().path,
            context: contents
        )
    }

    func mention(name rawName: String, path rawPath: String) throws -> ChatInputReference {
        ChatInputReference(
            kind: .mention,
            name: try boundedSingleLine(rawName, field: "mention name", maximumBytes: Self.maximumNameBytes),
            path: try boundedSingleLine(rawPath, field: "mention path", maximumBytes: Self.maximumPathBytes)
        )
    }

    private func canonicalFileURL(_ path: String) -> URL {
        let url = NSString(string: path).isAbsolutePath
            ? URL(fileURLWithPath: path, isDirectory: false)
            : cwd.appendingPathComponent(path, isDirectory: false)
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func boundedSkillContents(at url: URL) throws -> String {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw AppServerRPCError.invalidParams("selected skill is not a regular file")
            }
            guard let size = values.fileSize, size <= SkillCatalog.maximumManifestBytes else {
                throw AppServerRPCError.invalidParams("selected skill exceeds the manifest size limit")
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= SkillCatalog.maximumManifestBytes,
                  let contents = String(data: data, encoding: .utf8) else {
                throw AppServerRPCError.invalidParams("selected skill is not bounded UTF-8 text")
            }
            return contents
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw AppServerRPCError.invalidParams(
                "selected skill could not be read: \(error.localizedDescription)"
            )
        }
    }

    private func boundedSingleLine(
        _ raw: String,
        field: String,
        maximumBytes: Int
    ) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw AppServerRPCError.invalidParams("\(field) must be non-empty bounded single-line text")
        }
        return value
    }
}

extension AppServerSession {
    func richTurnInputResolver(cwd: URL) -> AppServerRichTurnInputResolver {
        AppServerRichTurnInputResolver(
            cwd: cwd,
            skillResolver: SkillResolver(
                roots: SkillResolver.roots(
                    workspaceRoot: cwd,
                    locations: skillRootLocations,
                    extraRoots: skillExtraRoots
                ),
                configuration: appConfig.skillConfiguration
            )
        )
    }
}
