import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeSidebarSurfaceTests: XCTestCase {
    func testProjectItemSurfaceBuildsRemoteStateAndDefaultActions() {
        let projectID = UUID()
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 22
        )
        let project = ProjectRef(id: projectID, name: "Feather", path: connection.path, connection: connection)
        let item = ProjectItemSurface(project: project, selectedProjectID: projectID)

        XCTAssertEqual(item.id, projectID)
        XCTAssertEqual(item.name, "Feather")
        XCTAssertEqual(item.path, "ssh://quill@feather.local:22/srv/quill")
        XCTAssertEqual(item.connectionKindLabel, "SSH Remote")
        XCTAssertTrue(item.isRemote)
        XCTAssertTrue(item.isSelected)
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .rename, .remove])
        XCTAssertEqual(item.actions.map(\.kind.title), ["New chat", "Refresh context", "Rename", "Remove from list"])
        XCTAssertEqual(item.actions.first?.id, "\(projectID.uuidString)-newChat")
    }

    func testProjectItemSurfaceDecodesOlderPayloadWithoutRemoteMetadataOrActions() throws {
        let projectID = UUID()
        let json = """
        {
          "id": "\(projectID.uuidString)",
          "name": "QuillCode",
          "path": "/Users/quill/QuillCode",
          "isSelected": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let item = try JSONDecoder().decode(ProjectItemSurface.self, from: data)

        XCTAssertEqual(item.connectionKindLabel, "Local")
        XCTAssertFalse(item.isRemote)
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .rename, .remove])
        XCTAssertTrue(item.actions.allSatisfy(\.isEnabled))
    }

    func testSidebarSurfaceFiltersGroupsAndLabelsSelection() {
        let selectedThread = ChatThread(title: "Run whoami", model: TrustedRouterDefaults.synthModel)
        var pinnedThread = ChatThread(title: "Review git diff", model: "z-ai/glm-5.2", isPinned: true)
        pinnedThread.messages = [
            .init(role: .user, content: "Can you inspect the browser preview?")
        ]
        var archivedThread = ChatThread(title: "Old release plan", model: TrustedRouterDefaults.synthModel)
        archivedThread.isArchived = true

        let surface = SidebarSurface(
            items: [
                SidebarItemSurface(item: SidebarItem(thread: selectedThread), selectedThreadID: selectedThread.id),
                SidebarItemSurface(item: SidebarItem(thread: pinnedThread), selectedThreadID: selectedThread.id),
                SidebarItemSurface(item: SidebarItem(thread: archivedThread), selectedThreadID: selectedThread.id)
            ],
            selectedThreadID: selectedThread.id,
            isSelectionMode: true,
            selectedThreadIDs: [selectedThread.id, archivedThread.id],
            bulkActions: [
                SidebarBulkActionSurface(kind: .clearSelection),
                SidebarBulkActionSurface(kind: .delete, isDestructive: true)
            ]
        )

        XCTAssertEqual(surface.selectionLabel, "2 chats selected")
        XCTAssertEqual(surface.filteredItems(matching: "").map(\.title), ["Run whoami", "Review git diff", "Old release plan"])
        XCTAssertEqual(surface.filteredItems(matching: "who").map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.filteredItems(matching: "GLM").map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "browser preview").map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "archived").map(\.title), ["Old release plan"])
        XCTAssertEqual(surface.pinnedItems.map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.recentItems.map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.recentSections().map(\.title), ["Today"])
        XCTAssertEqual(surface.recentSections().flatMap(\.items).map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.archivedItems.map(\.title), ["Old release plan"])
        XCTAssertEqual(surface.bulkActions.map(\.commandID), ["thread-selection-clear", "thread-bulk-delete"])
        XCTAssertEqual(surface.bulkActions.last?.isDestructive, true)
    }

    func testSidebarRecentSectionsGroupByTimeBucket() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 24,
            hour: 12
        )))
        func date(day: Int, hour: Int = 9) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 6,
                day: day,
                hour: hour
            )))
        }

        let today = ChatThread(title: "Today task", updatedAt: try date(day: 24, hour: 9))
        let laterToday = ChatThread(title: "Later today task", updatedAt: try date(day: 24, hour: 11))
        let yesterday = ChatThread(title: "Yesterday task", updatedAt: try date(day: 23))
        let lastWeek = ChatThread(title: "Earlier this week", updatedAt: try date(day: 19))
        let sevenDaysAgo = ChatThread(title: "Seven days ago", updatedAt: try date(day: 16))
        let older = ChatThread(title: "Old notes", updatedAt: try date(day: 1))
        var pinned = ChatThread(title: "Pinned never grouped", isPinned: true, updatedAt: try date(day: 24))
        pinned.isPinned = true
        var archived = ChatThread(title: "Archived never grouped", updatedAt: try date(day: 24))
        archived.isArchived = true

        let surface = SidebarSurface(
            items: [today, laterToday, yesterday, lastWeek, sevenDaysAgo, older, pinned, archived].map {
                SidebarItemSurface(item: SidebarItem(thread: $0), selectedThreadID: nil)
            },
            selectedThreadID: nil
        )

        let sections = surface.recentSections(now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Previous 7 days", "Older"])
        XCTAssertEqual(sections.map { $0.items.map(\.title) }, [
            ["Later today task", "Today task"],
            ["Yesterday task"],
            ["Earlier this week", "Seven days ago"],
            ["Old notes"]
        ])
    }

    func testSidebarSurfaceDecodesOlderPayloadWithoutSelectionMetadata() throws {
        let json = """
        {
          "items": [],
          "selectedThreadID": null
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let surface = try JSONDecoder().decode(SidebarSurface.self, from: data)

        XCTAssertEqual(surface.title, "Chats")
        XCTAssertEqual(surface.emptyTitle, "No chats yet")
        XCTAssertFalse(surface.isSelectionMode)
        XCTAssertEqual(surface.selectedThreadIDs, [])
        XCTAssertEqual(surface.selectionLabel, "No chats selected")
        XCTAssertEqual(surface.bulkActions, [])
    }

    func testSidebarItemSurfaceBuildsActivePinnedAndArchivedActions() {
        var activeThread = ChatThread(title: "Active")
        let active = SidebarItemSurface(item: SidebarItem(thread: activeThread), selectedThreadID: nil)
        XCTAssertEqual(active.actions.map(\.kind), [.rename, .duplicate, .pin, .archive, .delete])

        activeThread.isPinned = true
        let pinned = SidebarItemSurface(item: SidebarItem(thread: activeThread), selectedThreadID: nil)
        XCTAssertEqual(pinned.actions.map(\.kind), [.rename, .duplicate, .unpin, .archive, .delete])

        activeThread.isArchived = true
        let archived = SidebarItemSurface(item: SidebarItem(thread: activeThread), selectedThreadID: nil)
        XCTAssertEqual(archived.actions.map(\.kind), [.unarchive, .delete])
        XCTAssertEqual(archived.actions.map(\.kind.title), ["Unarchive", "Delete"])
    }

    func testSidebarItemSurfaceDecodesOlderPayloadWithoutBulkSelectionOrArchiveState() throws {
        let threadID = UUID()
        let json = """
        {
          "id": "\(threadID.uuidString)",
          "title": "Old thread",
          "subtitle": "Nike 1.0",
          "searchText": "old thread nike",
          "isSelected": true,
          "isPinned": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let item = try JSONDecoder().decode(SidebarItemSurface.self, from: data)

        XCTAssertEqual(item.id, threadID)
        XCTAssertTrue(item.isSelected)
        XCTAssertFalse(item.isBulkSelected)
        XCTAssertFalse(item.isArchived)
        XCTAssertEqual(item.updatedAt, .distantPast)
        XCTAssertEqual(item.actions, [])
    }

    func testSidebarBulkActionCommandIDsAndTitlesAreStable() {
        let expectations: [(SidebarBulkActionKind, String, String)] = [
            (.select, "Select", "thread-selection-start"),
            (.selectAll, "Select all", "thread-selection-select-all"),
            (.clearSelection, "Done", "thread-selection-clear"),
            (.pin, "Pin", "thread-bulk-pin"),
            (.unpin, "Unpin", "thread-bulk-unpin"),
            (.archive, "Archive", "thread-bulk-archive"),
            (.unarchive, "Unarchive", "thread-bulk-unarchive"),
            (.delete, "Delete", "thread-bulk-delete")
        ]

        for (kind, title, commandID) in expectations {
            let action = SidebarBulkActionSurface(kind: kind)
            XCTAssertEqual(action.title, title)
            XCTAssertEqual(action.commandID, commandID)
            XCTAssertEqual(action.id, commandID)
            XCTAssertEqual(SidebarBulkActionSurface.commandID(for: kind), commandID)
        }
    }

    func testSidebarCommandAdapterBuildsBulkAndToggleCommands() {
        let delete = SidebarBulkActionSurface(kind: .delete, isEnabled: false, isDestructive: true)
        let bulkCommand = QuillCodeSidebarCommandAdapter.workspaceCommand(for: delete)

        XCTAssertEqual(bulkCommand.id, "thread-bulk-delete")
        XCTAssertEqual(bulkCommand.title, "Delete")
        XCTAssertEqual(bulkCommand.category, WorkspaceCommandPalette.threadCategory)
        XCTAssertFalse(bulkCommand.isEnabled)

        let thread = ChatThread(title: "Selected")
        let item = SidebarItemSurface(
            item: SidebarItem(thread: thread),
            selectedThreadID: nil,
            selectedThreadIDs: [thread.id]
        )
        let toggleCommand = QuillCodeSidebarCommandAdapter.toggleSelectionCommand(for: item)

        XCTAssertEqual(toggleCommand.id, "thread-selection-toggle:\(thread.id.uuidString)")
        XCTAssertEqual(toggleCommand.title, "Deselect chat")
        XCTAssertEqual(toggleCommand.category, WorkspaceCommandPalette.threadCategory)
    }
}
