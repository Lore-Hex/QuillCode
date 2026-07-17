import Foundation
import QuillCodeCore

public struct WorkspaceSideConversationSlash: Sendable, Hashable {
    public var prompt: String?

    public init(prompt: String?) {
        self.prompt = prompt
    }

    public static func parse(_ input: String) -> Self? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let command = components.first?.lowercased(),
              command == "/side" || command == "/btw"
        else {
            return nil
        }
        let prompt = components.count == 2
            ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return Self(prompt: prompt.isEmpty ? nil : prompt)
    }
}

@MainActor
public extension QuillCodeWorkspaceModel {
    var activeSideConversationParentThreadID: UUID? {
        selectedThread?.runtimeContext.sideConversationParentThreadID
    }

    @discardableResult
    func startSideConversation(prompt: String? = nil) -> UUID? {
        guard let parent = selectedThread else {
            setLastError("Start a chat before opening a side conversation.")
            return nil
        }
        guard !parent.runtimeContext.isEphemeral else {
            setLastError("A side conversation is already open. Return to the parent chat first.")
            return nil
        }
        guard parent.messages.contains(where: { $0.role == .user }) else {
            setLastError("Send a message in the main chat before opening a side conversation.")
            return nil
        }

        let projectID = knownProjectID(parent.projectID)
        let side = WorkspaceThreadCreationEngine.sideConversation(from: parent, projectID: projectID)
        let threadID = insertCreatedThread(
            side,
            selectedProjectID: projectID,
            saveThread: false,
            recordsNavigation: false
        )
        setDraft(prompt ?? "")
        setLastError(nil)
        return threadID
    }

    @discardableResult
    func startQuickChat() -> UUID {
        if let threadID = startSideConversation() {
            return threadID
        }
        setLastError(nil)
        return newChat()
    }

    @discardableResult
    func returnFromSideConversation() -> Bool {
        guard let side = selectedThread,
              let parentThreadID = side.runtimeContext.sideConversationParentThreadID,
              let parent = root.threads.first(where: { $0.id == parentThreadID })
        else {
            return false
        }

        applyThreadDraftSelection(to: parentThreadID, removing: side.id)
        // A side conversation runs on the parent's priced (non-E2E) model and accrues real token
        // usage. It is ephemeral and about to be destroyed, so — exactly like incognito discard,
        // /clear, and /delete — keep a content-free spend receipt or its spend would vanish from the
        // period ledger and cycling side conversations could launder unbounded spend past the limits.
        retainEphemeralSpendReceipt(for: side)
        root.threads.removeAll { $0.id == side.id }
        sessionStartHookCoordinator.remove(threadID: side.id)
        agentRuns.finish(threadID: side.id)
        // agentRuns.finish is registry bookkeeping; the OWNING .send task must be cancelled too, at
        // the model level so EVERY caller is covered — including newIncognitoChat, which replaces an
        // active side conversation from the menu/palette where the desktop's command-keyed cancel
        // helper never fires.
        onEphemeralThreadDiscarded?(side.id)
        root.selectedThreadID = parentThreadID
        root.selectedProjectID = knownProjectID(parent.projectID)
        syncTerminalSessionToSelectedProject()
        refreshFileMentionIndex()
        refreshSelectedAgentRunPresentation()
        setLastError(nil)
        return true
    }
}
