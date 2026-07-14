import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeThreadSidebarSurfaceTests: XCTestCase {
    func testSidebarSurfaceFiltersGroupsAndLabelsSelection() {
        let selectedThread = ChatThread(title: "Run whoami", model: TrustedRouterDefaults.prometheusModel)
        var pinnedThread = ChatThread(title: "Review git diff", model: "z-ai/glm-5.2", isPinned: true)
        pinnedThread.messages = [
            .init(role: .user, content: "Can you inspect the browser preview?")
        ]
        var archivedThread = ChatThread(title: "Old release plan", model: TrustedRouterDefaults.prometheusModel)
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
        XCTAssertTrue(surface.filteredItems(matching: "workspace manager").isEmpty)
        XCTAssertEqual(surface.pinnedItems.map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.recentItems.map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.recentSections().map(\.title), ["Today"])
        XCTAssertEqual(surface.recentSections().flatMap(\.items).map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.archivedItems.map(\.title), ["Old release plan"])
        XCTAssertEqual(surface.bulkActions.map(\.commandID), ["thread-selection-clear", "thread-bulk-delete"])
        XCTAssertEqual(surface.bulkActions.last?.isDestructive, true)
    }

    func testSavedFiltersCountActiveAndRestrictVisibleGroups() {
        let recent = ChatThread(title: "Recent")
        var pinned = ChatThread(title: "Pinned")
        pinned.isPinned = true
        var archived = ChatThread(title: "Archived")
        archived.isArchived = true

        let surface = SidebarSurface(
            items: [recent, pinned, archived].map {
                SidebarItemSurface(item: SidebarItem(thread: $0), selectedThreadID: nil)
            },
            selectedThreadID: nil,
            activeFilter: .archived
        )

        XCTAssertEqual(surface.savedFilters.map(\.kind), [.all, .pinned, .recent, .archived])
        XCTAssertEqual(surface.savedFilters.map(\.count), [3, 1, 1, 1])
        XCTAssertEqual(surface.savedFilters.map(\.isActive), [false, false, false, true])
        XCTAssertEqual(surface.visibleItems.map(\.title), ["Archived"])
        XCTAssertEqual(surface.pinnedItems, [])
        XCTAssertEqual(surface.recentItems, [])
        XCTAssertEqual(surface.archivedItems.map(\.title), ["Archived"])
        XCTAssertEqual(surface.emptyTitle, "No archived chats")
    }

    func testCustomSavedSearchesCountActivateAndRestrictVisibleGroups() throws {
        let savedSearchID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let disk = ChatThread(title: "Disk usage", messages: [
            .init(role: .user, content: "Run df -h")
        ])
        var pinnedOpenClaw = ChatThread(title: "OpenClaw setup", messages: [
            .init(role: .assistant, content: "OpenClaw is installed under /Quill/Apps.")
        ])
        pinnedOpenClaw.isPinned = true
        var archivedOpenClaw = ChatThread(title: "Old OpenClaw plan")
        archivedOpenClaw.isArchived = true

        let surface = SidebarSurface(
            items: [disk, pinnedOpenClaw, archivedOpenClaw].map {
                SidebarItemSurface(item: SidebarItem(thread: $0), selectedThreadID: nil)
            },
            selectedThreadID: nil,
            activeSavedSearchID: savedSearchID,
            customSavedSearches: [
                SidebarSavedSearch(id: savedSearchID, title: "OpenClaw", query: "openclaw")
            ]
        )

        XCTAssertEqual(surface.savedFilters.map(\.isActive), [false, false, false, false])
        XCTAssertEqual(surface.customSavedSearches.map(\.title), ["OpenClaw"])
        XCTAssertEqual(surface.customSavedSearches.map(\.count), [2])
        XCTAssertEqual(surface.customSavedSearches.first?.isActive, true)
        XCTAssertEqual(surface.customSavedSearches.first?.commandID, "sidebar-saved-search:\(savedSearchID.uuidString)")
        XCTAssertEqual(surface.visibleItems.map(\.title), ["OpenClaw setup", "Old OpenClaw plan"])
        XCTAssertEqual(surface.pinnedItems.map(\.title), ["OpenClaw setup"])
        XCTAssertEqual(surface.recentItems, [])
        XCTAssertEqual(surface.archivedItems.map(\.title), ["Old OpenClaw plan"])
        XCTAssertEqual(surface.emptyTitle, "No chats matching OpenClaw")
    }

    func testInvalidSavedSearchesAreHidden() {
        let surface = SidebarSurface(
            items: [SidebarItemSurface(item: SidebarItem(thread: ChatThread(title: "Thread")), selectedThreadID: nil)],
            selectedThreadID: nil,
            customSavedSearches: [
                SidebarSavedSearch(title: "", query: "thread"),
                SidebarSavedSearch(title: "Blank query", query: "   ")
            ]
        )

        XCTAssertEqual(surface.customSavedSearches, [])
    }

    func testSavedFilterEmptyTitleKeepsOriginalWhenNoChatsExist() {
        let surface = SidebarSurface(
            items: [],
            selectedThreadID: nil,
            emptyTitle: "No workspace chats",
            activeFilter: .pinned
        )

        XCTAssertEqual(surface.emptyTitle, "No workspace chats")
        XCTAssertEqual(surface.visibleItems, [])
        XCTAssertEqual(surface.savedFilters.map(\.count), [0, 0, 0, 0])
        XCTAssertEqual(surface.customSavedSearches, [])
    }

    func testSidebarSearchExcludesHiddenInternalContext() {
        let thread = ChatThread(title: "Visible thread", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .tool, content: #"{"result":"secret internal feedback"}"#),
            .init(role: .system, content: "private hook guidance"),
            .init(role: .assistant, content: "Output:\nquill")
        ])
        let sidebar = SidebarSurface(
            items: [SidebarItemSurface(item: SidebarItem(thread: thread), selectedThreadID: thread.id)],
            selectedThreadID: thread.id
        )

        XCTAssertEqual(sidebar.filteredItems(matching: "secret internal feedback"), [])
        XCTAssertEqual(sidebar.filteredItems(matching: "private hook guidance"), [])
        XCTAssertEqual(sidebar.filteredItems(matching: "whoami").map(\.id), [thread.id])
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
        XCTAssertEqual(surface.activeFilter, .all)
        XCTAssertEqual(surface.savedFilters.map(\.kind), [.all, .pinned, .recent, .archived])
        XCTAssertEqual(surface.visibleItems, [])
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

        let filterCommand = QuillCodeSidebarCommandAdapter.workspaceCommand(
            for: SidebarSavedFilterSurface(kind: .recent, count: 2, isActive: false)
        )
        XCTAssertEqual(filterCommand.id, "sidebar-filter:recent")
        XCTAssertEqual(filterCommand.title, "Show recent chats")
        XCTAssertEqual(filterCommand.category, WorkspaceCommandPalette.threadCategory)

        let savedSearchID = UUID()
        let searchCommand = QuillCodeSidebarCommandAdapter.workspaceCommand(
            for: SidebarSavedSearchSurface(
                savedSearch: SidebarSavedSearch(id: savedSearchID, title: "Errors", query: "error failed"),
                count: 4,
                isActive: false
            )
        )
        XCTAssertEqual(searchCommand.id, "sidebar-saved-search:\(savedSearchID.uuidString)")
        XCTAssertEqual(searchCommand.title, "Show Errors")
        XCTAssertEqual(searchCommand.category, WorkspaceCommandPalette.threadCategory)
    }
}
