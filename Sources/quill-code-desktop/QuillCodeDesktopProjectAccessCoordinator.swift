import Foundation
import QuillCodeCore

struct QuillCodeDesktopResolvedProjectBookmark {
    let url: URL
    let isStale: Bool
}

@MainActor
struct QuillCodeDesktopProjectBookmarkService {
    var makeBookmark: (URL) throws -> Data
    var resolveBookmark: (Data) throws -> QuillCodeDesktopResolvedProjectBookmark
    var startAccessing: (URL) -> Bool
    var stopAccessing: (URL) -> Void

    static let live = QuillCodeDesktopProjectBookmarkService(
        makeBookmark: { url in
            try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        },
        resolveBookmark: { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return QuillCodeDesktopResolvedProjectBookmark(url: url, isStale: isStale)
        },
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() }
    )
}

@MainActor
final class QuillCodeDesktopProjectAccessCoordinator {
    static let defaultStorageKey = "projectSecurityScopedBookmarks.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private let service: QuillCodeDesktopProjectBookmarkService
    private var activeURLs: [String: URL] = [:]

    var activeProjectURLs: [URL] {
        Array(activeURLs.values)
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = defaultStorageKey,
        service: QuillCodeDesktopProjectBookmarkService = .live
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.service = service
    }

    @discardableResult
    func retainAccess(to url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let path = standardized.path
        activate(standardized, forPath: path)

        do {
            var bookmarks = storedBookmarks()
            bookmarks[path] = try service.makeBookmark(standardized)
            saveBookmarks(bookmarks)
        } catch {
            // The current picker grant remains active. Reopening can replace a
            // bookmark that the OS declined to create.
        }
        return standardized
    }

    func restoreAccess(for projects: [ProjectRef]) {
        let localPaths = Set(projects.lazy.filter { !$0.isRemote }.map { project in
            URL(fileURLWithPath: project.path).standardizedFileURL.path
        })
        var bookmarks = storedBookmarks()

        for path in activeURLs.keys where !localPaths.contains(path) {
            deactivate(path)
        }
        bookmarks = bookmarks.filter { localPaths.contains($0.key) }

        for path in localPaths where activeURLs[path] == nil {
            guard let data = bookmarks[path] else { continue }
            do {
                let resolved = try service.resolveBookmark(data)
                let url = resolved.url.standardizedFileURL
                guard url.path == path else {
                    bookmarks.removeValue(forKey: path)
                    continue
                }
                activate(url, forPath: path)
                if resolved.isStale {
                    bookmarks[path] = try service.makeBookmark(url)
                }
            } catch {
                bookmarks.removeValue(forKey: path)
            }
        }
        saveBookmarks(bookmarks)
    }

    func reconcileProjects(_ projects: [ProjectRef]) {
        restoreAccess(for: projects)
    }

    private func activate(_ url: URL, forPath path: String) {
        guard activeURLs[path] == nil, service.startAccessing(url) else { return }
        activeURLs[path] = url
    }

    private func deactivate(_ path: String) {
        guard let url = activeURLs.removeValue(forKey: path) else { return }
        service.stopAccessing(url)
    }

    private func storedBookmarks() -> [String: Data] {
        defaults.dictionary(forKey: storageKey) as? [String: Data] ?? [:]
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) {
        defaults.set(bookmarks, forKey: storageKey)
    }
}
