import Foundation
import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
extension XCTestCase {
    func makeProjectAutomationWorkspace() throws -> AutomationWorkspace {
        let root = try makeQuillCodeTestDirectory()
        let project = ProjectRef(name: "QuillCode", path: root.path)
        return try makeAutomationWorkspace(root: root, rootState: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id
        ))
    }

    func makeAutomationWorkspace(
        root: URL? = nil,
        rootState: QuillCodeRootState? = nil
    ) throws -> AutomationWorkspace {
        let resolvedRoot = try root ?? makeQuillCodeTestDirectory()
        let paths = QuillCodePaths(home: resolvedRoot.appendingPathComponent(".quillcode"))
        try paths.ensure()

        let automationStore = JSONAutomationStore(fileURL: paths.automationsFile)
        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        let model: QuillCodeWorkspaceModel
        if let rootState {
            model = QuillCodeWorkspaceModel(
                root: rootState,
                threadStore: threadStore,
                automationStore: automationStore
            )
        } else {
            model = QuillCodeWorkspaceModel(
                threadStore: threadStore,
                automationStore: automationStore
            )
        }

        return AutomationWorkspace(
            root: resolvedRoot,
            automationStore: automationStore,
            threadStore: threadStore,
            model: model
        )
    }

    func threadFollowUpAutomation(
        title: String,
        detail: String = "Resume this thread.",
        status: QuillAutomationStatus = .active,
        threadID: UUID,
        scheduleDescription: String = "Now",
        nextRunAt: Date
    ) -> QuillAutomation {
        QuillAutomation(
            title: title,
            detail: detail,
            kind: .threadFollowUp,
            status: status,
            scheduleKind: .heartbeat,
            scheduleDescription: scheduleDescription,
            threadID: threadID,
            nextRunAt: nextRunAt
        )
    }

    func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func makeUTCDate(day: Int, hour: Int, minute: Int) -> Date? {
        let calendar = makeUTCCalendar()
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 1970,
            month: 1,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ))
    }
}

struct AutomationWorkspace {
    var root: URL
    var automationStore: JSONAutomationStore
    var threadStore: JSONThreadStore
    var model: QuillCodeWorkspaceModel
}
