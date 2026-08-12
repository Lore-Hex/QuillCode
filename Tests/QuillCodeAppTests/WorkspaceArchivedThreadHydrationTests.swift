import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceArchivedThreadHydrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_435_200) // 2026-08-11 UTC

    func testBootstrapDefersEveryArchiveAndHydratesHistoricalChatOnSelection() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let project = ProjectRef(name: "Quill Cowork", path: paths.home.path)
        try JSONProjectStore(fileURL: paths.projectsFile).save([project])
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        let oldDate = Date(timeIntervalSince1970: 1_751_328_000)
        let currentMonthDate = now.addingTimeInterval(-24 * 60 * 60)
        var historical = ChatThread(
            title: "Historical crash investigation",
            projectID: project.id,
            messages: [
                ChatMessage(role: .user, content: "why did launch fail"),
                ChatMessage(role: .assistant, content: "the prior build rolled back safely")
            ],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        historical.events = [ThreadEvent(kind: .notice, summary: "Exact archived event")]
        let provenance = AgentImportThreadProvenance(source: .claudeCode, sourceID: "session-42")
        let provenancePayload = try JSONEncoder().encode([
            AgentImportThreadProvenance.payloadKey: provenance
        ])
        historical.events.append(ThreadEvent(
            kind: .notice,
            summary: "Imported from Claude Code",
            payloadJSON: String(decoding: provenancePayload, as: UTF8.self)
        ))
        historical.events.append(try XCTUnwrap(RunIntegrityRecord.event(for: RunIntegrityReport(
            verdict: .red,
            reasons: [RunIntegrityReason(
                rule: .standingTestFailure,
                detail: "release verification failed"
            )]
        ))))
        let recentArchive = ChatThread(
            title: "August usage receipt",
            projectID: project.id,
            messages: [ChatMessage(role: .assistant, content: "keep current month resident")],
            isArchived: true,
            createdAt: currentMonthDate,
            updatedAt: currentMonthDate
        )
        let active = ChatThread(
            title: "Current release",
            projectID: project.id,
            messages: [ChatMessage(role: .user, content: "publish")],
            createdAt: now,
            updatedAt: now
        )
        try store.save(historical)
        try store.save(recentArchive)
        try store.save(active)

        let model = try makeBootstrap(paths: paths).makeModel(
            automaticStartupPolicy: .deferUntilRequested
        )

        XCTAssertEqual(model.root.selectedThreadID, active.id)
        XCTAssertTrue(try XCTUnwrap(model.root.threads.first { $0.id == active.id }).payloadResidency.isLoaded)
        XCTAssertFalse(
            try XCTUnwrap(model.root.threads.first { $0.id == recentArchive.id })
                .payloadResidency.isLoaded
        )
        let deferred = try XCTUnwrap(model.root.threads.first { $0.id == historical.id })
        XCTAssertFalse(deferred.payloadResidency.isLoaded)
        XCTAssertTrue(deferred.messages.isEmpty)
        XCTAssertEqual(
            model.root.allSidebarItems.first { $0.id == historical.id }?.searchText,
            "why did launch fail\nthe prior build rolled back safely"
        )
        XCTAssertEqual(AgentImportThreadProvenance.value(in: deferred), provenance)
        let attentionItem = try XCTUnwrap(model.attentionModel.items.first { $0.threadID == historical.id })
        XCTAssertEqual(attentionItem.verdict, .red)
        XCTAssertEqual(attentionItem.title, historical.title)

        model.selectThread(historical.id)

        XCTAssertEqual(model.root.selectedThreadID, historical.id)
        let selected = try XCTUnwrap(model.selectedThread)
        XCTAssertTrue(selected.payloadResidency.isLoaded)
        XCTAssertEqual(selected.messages.map(\.id), historical.messages.map(\.id))
        XCTAssertEqual(selected.messages.map(\.content), historical.messages.map(\.content))
        XCTAssertEqual(selected.events.map(\.id), historical.events.map(\.id))
        XCTAssertEqual(selected.events.map(\.summary), historical.events.map(\.summary))

        model.selectThread(active.id)

        XCTAssertFalse(
            try XCTUnwrap(model.root.threads.first { $0.id == historical.id })
                .payloadResidency.isLoaded
        )
    }

    func testDuplicateAndUnarchiveHydrateHistoricalPayloadBeforeMutation() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let oldDate = Date(timeIntervalSince1970: 1_751_328_000)
        var historical = ChatThread(
            title: "Archived task",
            messages: [ChatMessage(role: .user, content: "preserve the complete transcript")],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        historical.events = [ThreadEvent(kind: .notice, summary: "Preserved lifecycle")]
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        try store.save(historical)

        let duplicateModel = try makeBootstrap(paths: paths).makeModel(
            automaticStartupPolicy: .deferUntilRequested
        )
        let duplicateID = try XCTUnwrap(duplicateModel.duplicateThread(historical.id))
        let duplicate = try XCTUnwrap(duplicateModel.root.threads.first { $0.id == duplicateID })
        XCTAssertEqual(duplicate.messages.map(\.id), historical.messages.map(\.id))
        XCTAssertEqual(duplicate.messages.map(\.content), historical.messages.map(\.content))
        XCTAssertEqual(
            duplicate.events.prefix(historical.events.count).map(\.summary),
            historical.events.map(\.summary)
        )
        XCTAssertTrue(duplicate.events.last?.summary.hasPrefix("Duplicated from") == true)

        let unarchiveModel = try makeBootstrap(paths: paths).makeModel(
            automaticStartupPolicy: .deferUntilRequested
        )
        XCTAssertTrue(unarchiveModel.unarchiveThread(historical.id))
        let restored = try XCTUnwrap(unarchiveModel.selectedThread)
        XCTAssertEqual(restored.id, historical.id)
        XCTAssertFalse(restored.isArchived)
        XCTAssertEqual(restored.messages.map(\.id), historical.messages.map(\.id))
        XCTAssertEqual(restored.messages.map(\.content), historical.messages.map(\.content))
        XCTAssertEqual(restored.events.map(\.id), historical.events.map(\.id))
        XCTAssertEqual(restored.events.map(\.summary), historical.events.map(\.summary))
        let persisted = try store.load(historical.id)
        XCTAssertEqual(persisted.messages.map(\.id), historical.messages.map(\.id))
        XCTAssertEqual(persisted.messages.map(\.content), historical.messages.map(\.content))
    }

    func testHistoricalFollowUpAutomationHydratesSourceContext() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let oldDate = Date(timeIntervalSince1970: 1_751_328_000)
        let historical = ChatThread(
            title: "Archived follow-up source",
            messages: [
                ChatMessage(role: .user, content: "investigate the crash"),
                ChatMessage(role: .assistant, content: "rollback was healthy")
            ],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try JSONThreadStore(directory: paths.threadsDirectory).save(historical)
        let automation = QuillAutomation(
            title: "Follow up archived task",
            detail: "Resume the original context.",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            scheduleDescription: "Now",
            threadID: historical.id,
            createdAt: oldDate,
            updatedAt: oldDate,
            nextRunAt: now
        )
        try JSONAutomationStore(fileURL: paths.automationsFile).save([automation])
        let model = try makeBootstrap(paths: paths).makeModel(
            automaticStartupPolicy: .deferUntilRequested
        )
        XCTAssertFalse(try XCTUnwrap(model.root.threads.first).payloadResidency.isLoaded)

        let followUpID = try XCTUnwrap(model.runAutomation(id: automation.id))
        let followUp = try XCTUnwrap(model.root.threads.first { $0.id == followUpID })

        XCTAssertEqual(followUp.messages.map(\.content), historical.messages.map(\.content))
        XCTAssertFalse(
            try XCTUnwrap(model.root.threads.first { $0.id == historical.id })
                .payloadResidency.isLoaded
        )
    }

    func testDeletingSharedAttachmentKeepsFileWhileDeferredArchiveReferencesIt() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let imageStore = ImageAttachmentStore(directory: paths.attachmentsDirectory)
        let activeID = UUID()
        let attachment = try imageStore.importImage(
            data: Self.onePixelPNG,
            displayName: "shared.png",
            threadID: activeID
        )
        let oldDate = Date(timeIntervalSince1970: 1_751_328_000)
        let historical = ChatThread(
            title: "Archived duplicate",
            messages: [ChatMessage(role: .user, content: "keep image", attachments: [attachment])],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let active = ChatThread(
            id: activeID,
            title: "Current duplicate",
            messages: [ChatMessage(role: .user, content: "same image", attachments: [attachment])],
            createdAt: now,
            updatedAt: now
        )
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        try store.save(historical)
        try store.save(active)
        let model = try makeBootstrap(paths: paths).makeModel(
            automaticStartupPolicy: .deferUntilRequested
        )
        let deferred = try XCTUnwrap(model.root.threads.first { $0.id == historical.id })
        XCTAssertEqual(
            deferred.payloadResidency.deferredSummary?.attachmentIDs,
            Set([attachment.id])
        )

        XCTAssertTrue(model.deleteThread(active.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.localURL.path))
        XCTAssertTrue(model.deleteThread(historical.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.localURL.path))
    }

    private func makeBootstrap(paths: QuillCodePaths) -> QuillCodeWorkspaceBootstrap {
        QuillCodeWorkspaceBootstrap(paths: paths, now: { [now] in now })
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
