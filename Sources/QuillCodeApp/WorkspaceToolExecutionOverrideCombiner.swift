import Foundation
import QuillCodeAgent

struct WorkspaceToolExecutionOverrideCombiner: Sendable, Hashable {
    static func combine(
        plan: AgentToolExecutionOverride?,
        browser: AgentToolExecutionOverride?,
        computerUse: AgentToolExecutionOverride?,
        memory: AgentToolExecutionOverride?,
        mcp: AgentToolExecutionOverride?,
        remoteProject: AgentToolExecutionOverride?
    ) -> AgentToolExecutionOverride? {
        guard plan != nil
                || browser != nil
                || computerUse != nil
                || memory != nil
                || mcp != nil
                || remoteProject != nil else {
            return nil
        }

        return { call, workspaceRoot in
            if let result = await plan?(call, workspaceRoot) {
                return result
            }
            if let result = await remoteProject?(call, workspaceRoot) {
                return result
            }
            if let result = await browser?(call, workspaceRoot) {
                return result
            }
            if let result = await computerUse?(call, workspaceRoot) {
                return result
            }
            if let result = await memory?(call, workspaceRoot) {
                return result
            }
            if let result = await mcp?(call, workspaceRoot) {
                return result
            }
            return nil
        }
    }
}
