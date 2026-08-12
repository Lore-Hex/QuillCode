import AppKit
import Foundation
import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopComposerDraftCheckpointCoordinatorTests: XCTestCase {
    func testControllerDebouncesTypingAndRelaunchRestoresLatestDraft() async throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root)
        let coordinator = QuillCodeDesktopComposerDraftCheckpointCoordinator(
            delayNanoseconds: 1_000_000
        )
        let controller = QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(
                paths: paths,
                runtimeFactory: QuillCodeRuntimeFactory(
                    paths: paths,
                    environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
                )
            ),
            browserLiveDOMCapturer: nil,
            composerDraftCheckpointCoordinator: coordinator,
            updateController: QuillCodeDesktopUpdateController(
                configuration: nil,
                installResultURL: nil
            ),
            workspaceRoot: root
        )
        let threadID = controller.model.newChat()
        controller.refresh()

        for index in 0..<1_000 {
            controller.draft = "draft \(index)"
        }
        await waitUntil { !coordinator.hasPendingCheckpoint }

        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        XCTAssertTrue(threadStore.contains(threadID), "the first checkpoint must make a new chat durable")
        let baselineThreadDraft = try threadStore.load(threadID).composerDraft
        XCTAssertEqual(
            try ComposerDraftCheckpointStore(directory: paths.composerDraftsDirectory)
                .load(for: threadID)?.draft,
            "draft 999"
        )

        controller.draft = "latest after another burst"
        await waitUntil { !coordinator.hasPendingCheckpoint }

        XCTAssertEqual(
            try threadStore.load(threadID).composerDraft,
            baselineThreadDraft,
            "later typing should not rewrite the full transcript snapshot"
        )
        let reloaded = try QuillCodeWorkspaceBootstrap(
            paths: paths,
            runtimeFactory: QuillCodeRuntimeFactory(
                paths: paths,
                environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
            )
        ).makeModel()
        XCTAssertEqual(reloaded.selectedThread?.id, threadID)
        XCTAssertEqual(reloaded.composer.draft, "latest after another burst")
    }

    func testDelayedCheckpointCannotBleedAcrossThreadSelection() throws {
        let root = try makeTempDirectory()
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [first, second],
                selectedThreadID: first.id
            ),
            composerDraftStore: checkpointStore
        )
        let coordinator = QuillCodeDesktopComposerDraftCheckpointCoordinator(
            delayNanoseconds: 5_000_000_000
        )

        coordinator.schedule(draft: "belongs to first", model: model)
        model.selectThread(second.id)
        coordinator.flush(on: model)

        XCTAssertEqual(model.selectedThread?.id, second.id)
        XCTAssertEqual(model.composer.draft, "")
        XCTAssertNotEqual(try checkpointStore.load(for: first.id)?.draft, "belongs to first")
        XCTAssertNil(try checkpointStore.load(for: second.id))
    }

    func testConfidentialTypingNeverWritesCheckpoint() throws {
        let root = try makeTempDirectory()
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let model = QuillCodeWorkspaceModel(composerDraftStore: checkpointStore)
        let threadID = model.newConfidentialChat()
        let coordinator = QuillCodeDesktopComposerDraftCheckpointCoordinator(
            delayNanoseconds: 5_000_000_000
        )

        coordinator.schedule(draft: "private live draft", model: model)
        coordinator.flush(on: model)

        XCTAssertEqual(model.composer.draft, "private live draft")
        XCTAssertNil(try checkpointStore.load(for: threadID))
        XCTAssertNil(try checkpointStore.load(for: nil))
    }

    func testApplicationLifecycleNotificationsFlushPendingCheckpointImmediately() async throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root.appendingPathComponent("threads"))
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let thread = ChatThread(title: "Lifecycle flush")
        try threadStore.save(thread)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: threadStore,
            composerDraftStore: checkpointStore
        )
        let notificationCenter = NotificationCenter()
        let coordinator = QuillCodeDesktopComposerDraftCheckpointCoordinator(
            delayNanoseconds: 5_000_000_000,
            notificationCenter: notificationCenter
        )
        coordinator.startLifecycleFlushes(model: model)
        coordinator.schedule(draft: "flush before leaving", model: model)

        notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
        await waitUntil { !coordinator.hasPendingCheckpoint }

        XCTAssertEqual(try checkpointStore.load(for: thread.id)?.draft, "flush before leaving")

        coordinator.schedule(draft: "flush before relaunch", model: model)
        notificationCenter.post(
            name: .quillCodeDesktopWillTerminateForRelaunch,
            object: nil
        )
        await waitUntil { !coordinator.hasPendingCheckpoint }

        XCTAssertEqual(try checkpointStore.load(for: thread.id)?.draft, "flush before relaunch")
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 where !condition() {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition(), "condition did not become true", file: file, line: line)
    }

    private func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeComposerCheckpointTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
