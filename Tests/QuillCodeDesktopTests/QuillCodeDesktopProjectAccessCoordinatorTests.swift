import Foundation
import XCTest
import QuillCodeCore
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopProjectAccessCoordinatorTests: XCTestCase {
    func testRetainPersistsBookmarkAndStartsAccess() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let spy = ProjectBookmarkServiceSpy()
        let coordinator = QuillCodeDesktopProjectAccessCoordinator(
            defaults: fixture.defaults,
            storageKey: fixture.storageKey,
            service: spy.service
        )

        let retained = coordinator.retainAccess(to: fixture.projectURL)

        XCTAssertEqual(retained, fixture.projectURL.standardizedFileURL)
        XCTAssertEqual(spy.startedPaths, [fixture.projectURL.path])
        let stored = try XCTUnwrap(
            fixture.defaults.dictionary(forKey: fixture.storageKey) as? [String: Data]
        )
        XCTAssertEqual(stored[fixture.projectURL.path], Data(fixture.projectURL.path.utf8))
    }

    func testRestoreRenewsStaleBookmarkAndRemovalStopsAccess() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let path = fixture.projectURL.path
        fixture.defaults.set([path: Data(path.utf8)], forKey: fixture.storageKey)
        let spy = ProjectBookmarkServiceSpy(isStale: true)
        let coordinator = QuillCodeDesktopProjectAccessCoordinator(
            defaults: fixture.defaults,
            storageKey: fixture.storageKey,
            service: spy.service
        )
        let project = ProjectRef(name: "Project", path: path)

        coordinator.restoreAccess(for: [project])
        coordinator.reconcileProjects([])

        XCTAssertEqual(spy.resolvedPaths, [path])
        XCTAssertEqual(spy.startedPaths, [path])
        XCTAssertEqual(spy.stoppedPaths, [path])
        let stored = fixture.defaults.dictionary(forKey: fixture.storageKey) as? [String: Data]
        XCTAssertEqual(stored, [:])
    }

    func testRestoreDropsBookmarkThatResolvesToAnotherPath() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let path = fixture.projectURL.path
        fixture.defaults.set([path: Data(path.utf8)], forKey: fixture.storageKey)
        let otherURL = fixture.projectURL.deletingLastPathComponent().appendingPathComponent("Other")
        let spy = ProjectBookmarkServiceSpy(resolvedURLOverride: otherURL)
        let coordinator = QuillCodeDesktopProjectAccessCoordinator(
            defaults: fixture.defaults,
            storageKey: fixture.storageKey,
            service: spy.service
        )

        coordinator.restoreAccess(for: [ProjectRef(name: "Project", path: path)])

        XCTAssertTrue(spy.startedPaths.isEmpty)
        let stored = fixture.defaults.dictionary(forKey: fixture.storageKey) as? [String: Data]
        XCTAssertEqual(stored, [:])
    }

    func testRestoreDoesNotRewriteUnchangedBookmarks() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let path = fixture.projectURL.path
        let bookmark = Data(path.utf8)
        let persistence = ProjectBookmarkPersistenceSpy(bookmarks: [path: bookmark])
        let spy = ProjectBookmarkServiceSpy()
        let coordinator = QuillCodeDesktopProjectAccessCoordinator(
            defaults: persistence,
            storageKey: fixture.storageKey,
            service: spy.service
        )

        coordinator.restoreAccess(for: [ProjectRef(name: "Project", path: path)])

        XCTAssertEqual(spy.resolvedPaths, [path])
        XCTAssertEqual(spy.madeBookmarkPaths, [])
        XCTAssertEqual(persistence.bookmarks, [path: bookmark])
        XCTAssertEqual(persistence.writeCount, 0)
    }

    private func makeFixture() throws -> ProjectAccessFixture {
        let suiteName = "QuillCodeDesktopProjectAccessCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-project-access-\(UUID().uuidString)", isDirectory: true)
        let projectURL = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        return ProjectAccessFixture(
            defaults: defaults,
            suiteName: suiteName,
            storageKey: "bookmarks",
            root: root,
            projectURL: projectURL
        )
    }
}

@MainActor
private final class ProjectBookmarkPersistenceSpy: QuillCodeDesktopProjectBookmarkPersisting {
    var bookmarks: [String: Data]
    private(set) var writeCount = 0

    init(bookmarks: [String: Data]) {
        self.bookmarks = bookmarks
    }

    func dictionary(forKey defaultName: String) -> [String: Any]? {
        bookmarks
    }

    func set(_ value: Any?, forKey defaultName: String) {
        writeCount += 1
        bookmarks = value as? [String: Data] ?? [:]
    }
}

@MainActor
private final class ProjectBookmarkServiceSpy {
    var startedPaths: [String] = []
    var stoppedPaths: [String] = []
    var resolvedPaths: [String] = []
    var madeBookmarkPaths: [String] = []
    private let isStale: Bool
    private let resolvedURLOverride: URL?

    init(isStale: Bool = false, resolvedURLOverride: URL? = nil) {
        self.isStale = isStale
        self.resolvedURLOverride = resolvedURLOverride
    }

    var service: QuillCodeDesktopProjectBookmarkService {
        QuillCodeDesktopProjectBookmarkService(
            makeBookmark: { [weak self] url in
                self?.madeBookmarkPaths.append(url.path)
                return Data(url.path.utf8)
            },
            resolveBookmark: { [weak self] data in
                let path = String(decoding: data, as: UTF8.self)
                self?.resolvedPaths.append(path)
                return QuillCodeDesktopResolvedProjectBookmark(
                    url: self?.resolvedURLOverride ?? URL(fileURLWithPath: path),
                    isStale: self?.isStale ?? false
                )
            },
            startAccessing: { [weak self] url in
                self?.startedPaths.append(url.path)
                return true
            },
            stopAccessing: { [weak self] url in
                self?.stoppedPaths.append(url.path)
            }
        )
    }
}

private struct ProjectAccessFixture {
    let defaults: UserDefaults
    let suiteName: String
    let storageKey: String
    let root: URL
    let projectURL: URL

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
