import Foundation
import QuillCodeCore

struct WorkspaceAutomationStateMutation<Value: Sendable & Hashable>: Sendable, Hashable {
    let state: AutomationsState
    let value: Value
}

enum WorkspaceAutomationStateReducer {
    static func setItems(
        _ items: [QuillAutomation],
        isVisible: Bool
    ) -> AutomationsState {
        AutomationsState(
            isVisible: isVisible,
            items: QuillAutomation.sortedForDisplay(items)
        )
    }

    static func createThreadFollowUp(
        in state: AutomationsState,
        thread: ChatThread,
        selectedProjectID: UUID?,
        scheduleDescription: String,
        nextRunAt: Date?,
        recurrence: QuillAutomationRecurrence?,
        now: Date
    ) -> WorkspaceAutomationStateMutation<QuillAutomation> {
        let automation = WorkspaceAutomationFactory.threadFollowUp(
            for: thread,
            selectedProjectID: selectedProjectID,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        return mutation(state: appending(automation, to: state), value: automation)
    }

    static func createWorkspaceSchedule(
        in state: AutomationsState,
        project: ProjectRef,
        scheduleDescription: String,
        nextRunAt: Date?,
        recurrence: QuillAutomationRecurrence?,
        now: Date
    ) -> WorkspaceAutomationStateMutation<QuillAutomation> {
        let automation = WorkspaceAutomationFactory.workspaceSchedule(
            for: project,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        return mutation(state: appending(automation, to: state), value: automation)
    }

    static func updateStatus(
        in state: AutomationsState,
        id: UUID,
        status: QuillAutomationStatus,
        now: Date
    ) -> WorkspaceAutomationStateMutation<Bool> {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else {
            return mutation(state: state, value: false)
        }
        var items = state.items
        items[index].status = status
        items[index].updatedAt = now
        return mutation(state: setItems(items, isVisible: state.isVisible), value: true)
    }

    static func delete(
        from state: AutomationsState,
        id: UUID
    ) -> WorkspaceAutomationStateMutation<Bool> {
        let items = state.items.filter { $0.id != id }
        guard items.count != state.items.count else {
            return mutation(state: state, value: false)
        }
        return mutation(state: setItems(items, isVisible: state.isVisible), value: true)
    }

    static func replace(
        in state: AutomationsState,
        automation: QuillAutomation
    ) -> WorkspaceAutomationStateMutation<Bool> {
        guard let index = state.items.firstIndex(where: { $0.id == automation.id }) else {
            return mutation(state: state, value: false)
        }
        var items = state.items
        items[index] = automation
        return mutation(state: setItems(items, isVisible: state.isVisible), value: true)
    }

    private static func appending(
        _ automation: QuillAutomation,
        to state: AutomationsState
    ) -> AutomationsState {
        setItems(state.items + [automation], isVisible: true)
    }

    private static func mutation<Value: Sendable & Hashable>(
        state: AutomationsState,
        value: Value
    ) -> WorkspaceAutomationStateMutation<Value> {
        WorkspaceAutomationStateMutation(state: state, value: value)
    }
}
