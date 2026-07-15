import Foundation
import QuillCodeTools

extension AppServerSession {
    func refreshSkillWatcher(cwds: [URL]? = nil) {
        if let cwds {
            skillWatchCWDs = deduplicatedSkillWatchCWDs(cwds)
        }
        let roots = deduplicatedSkillWatchRoots(skillWatchCWDs.flatMap { cwd in
            SkillResolver.roots(
                workspaceRoot: cwd,
                locations: skillRootLocations,
                extraRoots: skillExtraRoots
            )
        })
        guard roots != skillWatchRoots else { return }

        skillWatchGeneration &+= 1
        skillWatchTask?.cancel()
        skillWatchTask = nil
        skillWatchRoots = roots
        guard !roots.isEmpty, !inputFinished else { return }

        let generation = skillWatchGeneration
        skillWatchTask = AppServerSkillWatcher.monitor(roots: roots) { [weak self] in
            await self?.skillRootsChanged(generation: generation)
        }
    }

    func cancelSkillWatcher() {
        skillWatchGeneration &+= 1
        skillWatchTask?.cancel()
        skillWatchTask = nil
        skillWatchRoots = []
        skillWatchCWDs = []
    }

    private func skillRootsChanged(generation: UInt64) async {
        guard generation == skillWatchGeneration, !inputFinished else { return }
        cachedSkillSnapshots.removeAll(keepingCapacity: true)
        await sendNotification("skills/changed", params: .object([:]))
    }

    private func deduplicatedSkillWatchCWDs(_ cwds: [URL]) -> [URL] {
        var seen = Set<String>()
        return cwds.compactMap { cwd in
            let value = cwd.standardizedFileURL
            return seen.insert(value.path).inserted ? value : nil
        }
    }

    private func deduplicatedSkillWatchRoots(_ roots: [SkillRoot]) -> [SkillRoot] {
        var indices: [String: Int] = [:]
        var result: [SkillRoot] = []
        for root in roots {
            let normalized = SkillRoot(kind: root.kind, url: root.url.standardizedFileURL)
            let path = normalized.url.path
            if let index = indices[path] {
                if !result[index].kind.followsDirectorySymlinks,
                   normalized.kind.followsDirectorySymlinks {
                    result[index] = normalized
                }
                continue
            }
            guard result.count < AppServerSkillWatcher.maximumRoots else { break }
            indices[path] = result.count
            result.append(normalized)
        }
        return result
    }
}

enum AppServerSkillWatcher {
    static let maximumRoots = SkillCatalog.maximumRoots
    fileprivate static let maximumEntriesPerRoot = 4_000
    fileprivate static let maximumEntriesAcrossRoots = 20_000
    private static let pollNanoseconds: UInt64 = 500_000_000
    private static let debounceInterval: TimeInterval = 0.3

    static func monitor(
        roots: [SkillRoot],
        onChange: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let roots = Array(roots.prefix(maximumRoots))
        let initialSnapshot = AppServerSkillTreeSnapshot.capture(roots: roots)
        return Task {
            var snapshot = initialSnapshot
            var debounceDeadline: Date?

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: pollNanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }

                let next = AppServerSkillTreeSnapshot.capture(roots: roots)
                if next != snapshot {
                    snapshot = next
                    debounceDeadline = Date().addingTimeInterval(debounceInterval)
                }
                if let deadline = debounceDeadline, Date() >= deadline {
                    debounceDeadline = nil
                    await onChange()
                }
            }
        }
    }

    fileprivate static func captureRoot(
        _ root: SkillRoot,
        maximumDescendants: Int
    ) -> AppServerSkillRootSnapshot {
        let rootURL = root.url.standardizedFileURL
        guard let rootIdentity = AppServerSkillWatchIdentity.capture(rootURL) else {
            return AppServerSkillRootSnapshot(path: rootURL.path, entries: [:], truncated: false)
        }

        var entries = ["": rootIdentity]
        var visitedDirectories = Set<String>()
        var directoryCount = 0
        var descendantCount = 0
        var truncated = false

        func walk(_ directory: URL, logicalPath: String, depth: Int) {
            guard descendantCount < maximumDescendants,
                  depth <= SkillCatalog.maximumScanDepth,
                  directoryCount < SkillCatalog.maximumDirectoriesPerRoot else {
                truncated = true
                return
            }

            let canonical = directory.standardizedFileURL.resolvingSymlinksInPath()
            guard visitedDirectories.insert(canonical.path).inserted else { return }
            directoryCount += 1

            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: AppServerSkillWatchIdentity.resourceKeys,
                options: [.skipsHiddenFiles]
            ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else { return }

            for child in children {
                guard descendantCount < maximumDescendants else {
                    truncated = true
                    return
                }
                let childPath = logicalPath.isEmpty
                    ? child.lastPathComponent
                    : logicalPath + "/" + child.lastPathComponent
                guard let identity = AppServerSkillWatchIdentity.capture(child) else { continue }
                entries[childPath] = identity
                descendantCount += 1

                guard depth < SkillCatalog.maximumScanDepth,
                      identity.targetIsDirectory,
                      (!identity.isSymbolicLink || root.kind.followsDirectorySymlinks) else { continue }
                let nextDirectory = identity.isSymbolicLink
                    ? child.standardizedFileURL.resolvingSymlinksInPath()
                    : child
                walk(nextDirectory, logicalPath: childPath, depth: depth + 1)
            }
        }

        if rootIdentity.targetIsDirectory {
            walk(rootURL, logicalPath: "", depth: 0)
        }
        return AppServerSkillRootSnapshot(path: rootURL.path, entries: entries, truncated: truncated)
    }
}

private struct AppServerSkillTreeSnapshot: Sendable, Equatable {
    var roots: [AppServerSkillRootSnapshot]

    static func capture(roots: [SkillRoot]) -> AppServerSkillTreeSnapshot {
        var remainingEntries = AppServerSkillWatcher.maximumEntriesAcrossRoots
        let snapshots = roots.map { root in
            let allowance = min(AppServerSkillWatcher.maximumEntriesPerRoot, remainingEntries)
            let snapshot = AppServerSkillWatcher.captureRoot(
                root,
                maximumDescendants: allowance
            )
            remainingEntries -= min(allowance, max(0, snapshot.entries.count - 1))
            return snapshot
        }
        return AppServerSkillTreeSnapshot(roots: snapshots)
    }
}

private struct AppServerSkillRootSnapshot: Sendable, Equatable {
    var path: String
    var entries: [String: AppServerSkillWatchIdentity]
    var truncated: Bool
}

private struct AppServerSkillWatchIdentity: Sendable, Equatable {
    enum Kind: String, Sendable {
        case directory
        case file
        case symbolicLink
        case other
    }

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .contentModificationDateKey,
        .fileSizeKey,
        .fileResourceIdentifierKey
    ]

    var kind: Kind
    var modifiedAt: Date?
    var size: Int
    var resourceIdentifier: String?
    var contentFingerprint: UInt64?
    var targetIsDirectory: Bool

    var isSymbolicLink: Bool { kind == .symbolicLink }

    static func capture(_ url: URL) -> AppServerSkillWatchIdentity? {
        var uncachedURL = url
        uncachedURL.removeAllCachedResourceValues()
        guard let values = try? uncachedURL.resourceValues(forKeys: Set(resourceKeys)) else {
            return nil
        }
        let isSymbolicLink = values.isSymbolicLink == true
        let targetIsDirectory: Bool
        if isSymbolicLink {
            var target = url.standardizedFileURL.resolvingSymlinksInPath()
            target.removeAllCachedResourceValues()
            targetIsDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        } else {
            targetIsDirectory = values.isDirectory == true
        }
        let kind: Kind
        if isSymbolicLink {
            kind = .symbolicLink
        } else if values.isDirectory == true {
            kind = .directory
        } else if values.isRegularFile == true {
            kind = .file
        } else {
            kind = .other
        }
        return AppServerSkillWatchIdentity(
            kind: kind,
            modifiedAt: values.contentModificationDate,
            size: values.fileSize ?? 0,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
            contentFingerprint: fingerprintIfRelevant(url, isRegularFile: kind == .file),
            targetIsDirectory: targetIsDirectory
        )
    }

    private static func fingerprintIfRelevant(_ url: URL, isRegularFile: Bool) -> UInt64? {
        guard isRegularFile,
              url.lastPathComponent == SkillResolver.manifestFileName || url.lastPathComponent == "openai.yaml",
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let limit = max(SkillCatalog.maximumManifestBytes, SkillCatalog.maximumMetadataBytes)
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data.reduce(14_695_981_039_346_656_037) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
