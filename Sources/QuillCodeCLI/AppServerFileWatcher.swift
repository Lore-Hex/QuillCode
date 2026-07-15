import Foundation

enum AppServerFileWatcher {
    private static let pollNanoseconds: UInt64 = 100_000_000
    private static let debounceInterval: TimeInterval = 0.2

    static func monitor(
        path: URL,
        onChange: @escaping @Sendable ([URL]) async -> Void
    ) -> Task<Void, Never> {
        let initialSnapshot = AppServerWatchSnapshot.capture(path)
        return Task {
            var snapshot = initialSnapshot
            var pendingPaths = Set<URL>()
            var debounceDeadline: Date?

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: pollNanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }

                let next = AppServerWatchSnapshot.capture(path)
                let changedPaths = snapshot.changedPaths(comparedWith: next, target: path)
                snapshot = next
                if !changedPaths.isEmpty {
                    pendingPaths.formUnion(changedPaths)
                    debounceDeadline = Date().addingTimeInterval(debounceInterval)
                }
                if let deadline = debounceDeadline,
                   Date() >= deadline,
                   !pendingPaths.isEmpty {
                    let paths = pendingPaths.sorted { $0.path < $1.path }
                    pendingPaths.removeAll(keepingCapacity: true)
                    debounceDeadline = nil
                    await onChange(paths)
                }
            }
        }
    }
}

private struct AppServerWatchSnapshot: Sendable, Equatable {
    var target: AppServerWatchIdentity?
    var children: [String: AppServerWatchIdentity]

    static func capture(_ url: URL) -> AppServerWatchSnapshot {
        guard let identity = AppServerWatchIdentity.capture(url) else {
            return AppServerWatchSnapshot(target: nil, children: [:])
        }
        guard identity.kind == .directory,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: AppServerWatchIdentity.resourceKeys,
                options: []
              ) else {
            return AppServerWatchSnapshot(target: identity, children: [:])
        }
        return AppServerWatchSnapshot(
            target: identity,
            children: Dictionary(uniqueKeysWithValues: entries.compactMap { child in
                AppServerWatchIdentity.capture(child).map { (child.lastPathComponent, $0) }
            })
        )
    }

    func changedPaths(comparedWith next: AppServerWatchSnapshot, target url: URL) -> Set<URL> {
        guard target != next.target || children != next.children else { return [] }
        guard target?.kind == .directory, next.target?.kind == .directory else {
            return [url.standardizedFileURL]
        }

        let names = Set(children.keys).union(next.children.keys)
        let changedChildren = names.filter { children[$0] != next.children[$0] }
        if changedChildren.isEmpty {
            return [url.standardizedFileURL]
        }
        return Set(changedChildren.map {
            url.appendingPathComponent($0).standardizedFileURL
        })
    }
}

private struct AppServerWatchIdentity: Sendable, Equatable {
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

    static func capture(_ url: URL) -> AppServerWatchIdentity? {
        var uncachedURL = url
        uncachedURL.removeAllCachedResourceValues()
        guard let values = try? uncachedURL.resourceValues(forKeys: Set(resourceKeys)) else {
            return nil
        }
        let kind: Kind
        if values.isSymbolicLink == true {
            kind = .symbolicLink
        } else if values.isDirectory == true {
            kind = .directory
        } else if values.isRegularFile == true {
            kind = .file
        } else {
            kind = .other
        }
        return AppServerWatchIdentity(
            kind: kind,
            modifiedAt: values.contentModificationDate,
            size: values.fileSize ?? 0,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }
}
