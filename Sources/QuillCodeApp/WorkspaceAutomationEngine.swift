import Foundation
import QuillCodeCore

public struct AutomationsState: Sendable, Hashable {
    public var isVisible: Bool
    public var items: [QuillAutomation]

    public init(isVisible: Bool = false, items: [QuillAutomation] = []) {
        self.isVisible = isVisible
        self.items = items
    }
}

public struct AutomationRunReport: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID { followUpThreadID }
    public var automationID: UUID
    public var followUpThreadID: UUID
    public var title: String
    public var body: String

    public init(
        automationID: UUID,
        followUpThreadID: UUID,
        title: String,
        body: String
    ) {
        self.automationID = automationID
        self.followUpThreadID = followUpThreadID
        self.title = title
        self.body = body
    }
}

struct WorkspaceAutomationRunDraft: Sendable, Hashable {
    let automation: QuillAutomation
    let thread: ChatThread
    let selectedProjectID: UUID?
    let report: AutomationRunReport
}

struct WorkspaceAutomationTrigger: Sendable, Hashable {
    let automationID: UUID
    let eventDescription: String?
}
