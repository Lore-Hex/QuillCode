import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety

public enum WorkspaceCodeReviewRunner {
    public static let readableToolNames: Set<String> = [
        ToolDefinition.fileRead.name,
        ToolDefinition.fileList.name,
        ToolDefinition.fileSearch.name,
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitBranchList.name
    ]

    /// Restricts an already-configured runner to the dedicated review capability boundary.
    /// The source runner may carry project routing, model selection, or transport configuration;
    /// mutation tools and optional extension surfaces never cross this boundary.
    public static func configure(
        _ source: AgentRunner,
        reportCollector: WorkspaceCodeReviewReportCollector
    ) -> AgentRunner {
        var reviewer = source
        reviewer.baseToolDefinitions = reviewer.baseToolDefinitions.filter {
            readableToolNames.contains($0.name) && $0.risk == .read
        }
        reviewer.additionalToolDefinitions = [WorkspaceCodeReviewSubmitTool.definition]
        reviewer.hostToolAccessScope = .workspaceOnly

        let underlyingOverride = reviewer.toolExecutionOverride
        reviewer.toolExecutionOverride = { call, workspaceRoot in
            if call.name == WorkspaceCodeReviewSubmitTool.name {
                return await reportCollector.capture(call)
            }
            guard readableToolNames.contains(call.name) else {
                return ToolResult(
                    ok: false,
                    error: "The dedicated code reviewer cannot execute \(call.name)."
                )
            }
            return await underlyingOverride?(call, workspaceRoot)
        }
        reviewer.safety = StaticSafetyReviewer()
        reviewer.preToolUseHook = nil
        reviewer.postToolUseHook = nil
        reviewer.permissionRequestHook = nil
        reviewer.preCompactHook = nil
        reviewer.postCompactHook = nil
        reviewer.threadToolExecutionOverride = nil
        reviewer.toolFeedbackAttachmentProvider = nil
        reviewer.skillResolver = nil
        reviewer.webSearch = nil
        reviewer.lsp = nil
        reviewer.enablesImmediateActionPreflight = false
        return reviewer
    }
}
