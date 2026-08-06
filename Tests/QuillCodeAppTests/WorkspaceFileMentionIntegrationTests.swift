import XCTest
@testable import QuillCodeApp
import QuillCodeTools

@MainActor
final class WorkspaceFileMentionIntegrationTests: XCTestCase {
    private func makeProject(files: [String]) throws -> URL {
        let root = try makeQuillCodeTestDirectory()
        let executor = FileToolExecutor(workspaceRoot: root)
        for path in files {
            XCTAssertTrue(executor.write(path: path, content: "// \(path)\n").ok)
        }
        return root
    }

    func testAddingLocalProjectPopulatesFileMentionIndex() async throws {
        let root = try makeProject(files: ["Sources/App.swift", "README.md"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        await model.waitForFileMentionIndexRefresh()

        let paths = model.fileMentionIndex.entries.map(\.path)
        XCTAssertTrue(paths.contains("Sources/App.swift"))
        XCTAssertTrue(paths.contains("README.md"))
    }

    func testComposerSurfaceSuggestsWorkspaceFilesForActiveMention() async throws {
        let root = try makeProject(files: ["Sources/App.swift", "Sources/Helper.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        await model.waitForFileMentionIndexRefresh()

        model.setDraft("please read @App")
        let suggestions = model.surface().composer.fileMentionSuggestions

        XCTAssertEqual(suggestions.first?.path, "Sources/App.swift")
        XCTAssertEqual(suggestions.first?.insertText, "please read @Sources/App.swift ")
    }

    func testComposerSurfaceHasNoMentionSuggestionsWithoutActiveMention() throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        model.setDraft("no mention here")
        XCTAssertTrue(model.surface().composer.fileMentionSuggestions.isEmpty)
    }

    func testSlashCommandDraftSuppressesFileMentionSuggestions() throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        model.setDraft("/help")
        let surface = model.surface().composer
        XCTAssertFalse(surface.slashSuggestions.isEmpty)
        XCTAssertTrue(surface.fileMentionSuggestions.isEmpty)
    }

    func testRefreshContextPicksUpNewlyCreatedFiles() async throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Demo")
        await model.waitForFileMentionIndexRefresh()

        XCTAssertTrue(FileToolExecutor(workspaceRoot: root).write(path: "Sources/Added.swift", content: "// new\n").ok)
        XCTAssertFalse(model.fileMentionIndex.entries.map(\.path).contains("Sources/Added.swift"))

        _ = model.refreshProjectContext(projectID)
        await model.waitForFileMentionIndexRefresh()
        XCTAssertTrue(model.fileMentionIndex.entries.map(\.path).contains("Sources/Added.swift"))
    }

    func testFileMentionIndexRefreshesAfterAgentFileWrite() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        XCTAssertFalse(model.fileMentionIndex.entries.map(\.path).contains("hello.txt"))

        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)
        await model.waitForFileMentionIndexRefresh()

        XCTAssertTrue(model.fileMentionIndex.entries.map(\.path).contains("hello.txt"))
    }

    func testSelectingSSHRemoteProjectClearsFileMentionIndex() async throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        await model.waitForFileMentionIndexRefresh()
        XCTAssertFalse(model.fileMentionIndex.isEmpty)

        _ = model.addSSHProject("user@host:/srv/app", name: "Remote")
        XCTAssertTrue(model.fileMentionIndex.isEmpty)
    }

    func testSlowFileMentionIndexingDoesNotBlockTheMainActor() async throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel(fileMentionIndexBuilder: { _ in
            Thread.sleep(forTimeInterval: 0.25)
            return WorkspaceFileIndex(entries: [
                WorkspaceFileIndexEntry(path: "Sources/App.swift", name: "App.swift", directory: "Sources")
            ])
        })
        let startedAt = ContinuousClock.now

        _ = model.addProject(path: root, name: "Demo")

        XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(100))
        await model.waitForFileMentionIndexRefresh()
        XCTAssertEqual(model.fileMentionIndex.entries.map(\.path), ["Sources/App.swift"])
    }

    func testRepeatedFileMentionRefreshCoalescesAnInFlightScan() async throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let probe = BlockingFileMentionIndexBuilder()
        let model = QuillCodeWorkspaceModel(fileMentionIndexBuilder: { root in
            probe.build(root)
        })

        _ = model.addProject(path: root, name: "Demo")
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline, probe.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        model.refreshFileMentionIndex()
        model.refreshFileMentionIndex()

        XCTAssertEqual(probe.callCount, 1)
        probe.release.signal()
        await model.waitForFileMentionIndexRefresh()
        XCTAssertEqual(probe.callCount, 1)
    }
}

private final class BlockingFileMentionIndexBuilder: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func build(_ root: URL) -> WorkspaceFileIndex {
        lock.withLock { calls += 1 }
        release.wait()
        return WorkspaceFileIndex(entries: [
            WorkspaceFileIndexEntry(
                path: "Sources/App.swift",
                name: "App.swift",
                directory: "Sources"
            )
        ])
    }
}
