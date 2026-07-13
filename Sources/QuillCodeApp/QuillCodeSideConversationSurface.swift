import Foundation
import QuillCodeCore

public struct SideConversationSurface: Codable, Sendable, Hashable {
    public var parentThreadID: UUID
    public var parentTitle: String
    public var parentStatus: String
    public var returnCommand: WorkspaceCommandSurface

    public init(
        parentThreadID: UUID,
        parentTitle: String,
        parentStatus: String,
        returnCommand: WorkspaceCommandSurface
    ) {
        self.parentThreadID = parentThreadID
        self.parentTitle = parentTitle
        self.parentStatus = parentStatus
        self.returnCommand = returnCommand
    }
}

@MainActor
extension QuillCodeWorkspaceModel {
    func sideConversationSurface() -> SideConversationSurface? {
        guard let parentThreadID = activeSideConversationParentThreadID,
              let parent = root.threads.first(where: { $0.id == parentThreadID })
        else {
            return nil
        }
        return SideConversationSurface(
            parentThreadID: parentThreadID,
            parentTitle: parent.title,
            parentStatus: sideConversationParentStatus(parent),
            returnCommand: WorkspaceCommandSurface(
                id: WorkspaceCommandAction.sideConversationReturn.rawValue,
                title: "Return to main chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["side", "return", "parent", "main", "btw"]
            )
        )
    }

    private func sideConversationParentStatus(_ parent: ChatThread) -> String {
        if !WorkspaceApprovalActionPlanner.undecidedRequests(in: parent).isEmpty {
            return "Main chat needs approval"
        }
        if let status = agentRuns.status(for: parent.id) {
            return "Main chat: \(status)"
        }
        return "Main chat is ready"
    }
}
