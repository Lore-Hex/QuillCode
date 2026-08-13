import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceThreadPayloadResidencyTests: XCTestCase {
    func testRepeatedNavigationKeepsActiveTranscriptWorkingSetBounded() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<30 {
            try store.save(ChatThread(
                title: "Chat \(index)",
                messages: [ChatMessage(
                    role: .user,
                    content: "payload \(index) " + String(repeating: "x", count: 8_192)
                )],
                createdAt: baseDate,
                updatedAt: baseDate.addingTimeInterval(TimeInterval(index))
            ))
        }
        let threads = store.bootstrapListing(
            deferArchivedBefore: .distantFuture,
            maximumResidentActivePayloads: QuillCodeWorkspaceBootstrap.maximumLaunchResidentActivePayloads,
            retainingUsageSince: .distantPast
        ).threads
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: threads,
                selectedThreadID: threads.first?.id
            ),
            threadStore: store
        )
        XCTAssertEqual(
            model.root.threads.filter { !$0.isArchived && $0.payloadResidency.isLoaded }.count,
            QuillCodeWorkspaceBootstrap.maximumLaunchResidentActivePayloads
        )
        XCTAssertEqual(model.selectedThread?.messages.count, 1)

        for id in threads.reversed().map(\.id) {
            model.selectThread(id)

            let selected = try XCTUnwrap(model.selectedThread)
            XCTAssertEqual(selected.id, id)
            XCTAssertTrue(selected.payloadResidency.isLoaded)
            XCTAssertEqual(selected.messages.count, 1)
            XCTAssertLessThanOrEqual(
                model.root.threads.filter {
                    !$0.isArchived && $0.payloadResidency.isLoaded
                }.count,
                JSONThreadStore.defaultMaximumResidentActivePayloads
            )
        }
        XCTAssertTrue(model.root.threads.contains {
            !$0.payloadResidency.isLoaded && $0.messages.isEmpty
        })
    }

    func testRunningAndPersistenceFailedChatsAreNeverReleased() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        var threads: [ChatThread] = []
        for index in 0..<14 {
            let thread = ChatThread(
                title: "Chat \(index)",
                messages: [ChatMessage(role: .user, content: "payload \(index)")],
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            try store.save(thread)
            threads.append(thread)
        }
        let runningID = threads[0].id
        let failedID = threads[1].id
        let selectedID = threads[13].id
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: threads, selectedThreadID: selectedID),
            agentRuns: WorkspaceAgentRunRegistry(statusesByThreadID: [runningID: "Running"]),
            threadStore: store
        )
        model.threadPersistenceIssueTracker.recordFailure(for: failedID)

        model.enforceThreadPayloadResidency()

        XCTAssertTrue(try XCTUnwrap(model.root.threads.first { $0.id == runningID })
            .payloadResidency.isLoaded)
        XCTAssertTrue(try XCTUnwrap(model.root.threads.first { $0.id == failedID })
            .payloadResidency.isLoaded)
        XCTAssertTrue(try XCTUnwrap(model.root.threads.first { $0.id == selectedID })
            .payloadResidency.isLoaded)
        XCTAssertEqual(
            model.root.threads.filter { $0.payloadResidency.isLoaded }.count,
            JSONThreadStore.defaultMaximumResidentActivePayloads
        )
    }

    func testProjectAndArchiveFallbackSelectionsHydrateColdChats() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        let firstProject = ProjectRef(name: "First", path: "/tmp/first")
        let secondProject = ProjectRef(name: "Second", path: "/tmp/second")
        let old = ChatThread(
            title: "Old fallback",
            projectID: firstProject.id,
            messages: [ChatMessage(role: .user, content: "old payload")],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newest = ChatThread(
            title: "Newest",
            projectID: firstProject.id,
            messages: [ChatMessage(role: .user, content: "new payload")],
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let other = ChatThread(
            title: "Other project",
            projectID: secondProject.id,
            messages: [ChatMessage(role: .user, content: "other payload")],
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        try [old, newest, other].forEach(store.save)
        let threads = store.bootstrapListing(
            deferArchivedBefore: .distantFuture,
            maximumResidentActivePayloads: 1
        ).threads
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [firstProject, secondProject],
                threads: threads,
                selectedThreadID: other.id
            ),
            threadStore: store
        )

        model.selectProject(firstProject.id)

        XCTAssertEqual(model.selectedThread?.id, newest.id)
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), ["new payload"])
        XCTAssertTrue(model.archiveThread(newest.id))
        XCTAssertEqual(model.selectedThread?.id, old.id)
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), ["old payload"])
    }
}
