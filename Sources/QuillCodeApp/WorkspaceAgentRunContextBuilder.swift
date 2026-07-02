import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

struct WorkspaceAgentRunContextBuilder: Sendable {
    var selectedProject: ProjectRef?
    var config: AppConfig = AppConfig()
    var browser: BrowserState
    var browserToolOverride: AgentToolExecutionOverride? = nil
    var computerUseBackend: (any ComputerUseBackend)?
    var globalMemoryDirectory: URL?
    var mcpToolDefinitions: [ToolDefinition]
    var mcpToolExecutionOverride: AgentToolExecutionOverride?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor

    func configuredRunner(from runner: AgentRunner) -> AgentRunner {
        var activeRunner = runner
        activeRunner.baseToolDefinitions = baseToolDefinitions
        activeRunner.additionalToolDefinitions = additionalToolDefinitions
        activeRunner.toolExecutionOverride = toolExecutionOverride
        return activeRunner
    }

    var baseToolDefinitions: [ToolDefinition] {
        selectedProject?.isRemote == true
            ? WorkspaceRemoteProjectToolExecutor.toolDefinitions
            : ToolRouter.definitions
    }

    var additionalToolDefinitions: [ToolDefinition] {
        [
            ToolDefinition.planUpdate,
            ToolDefinition.handoffUpdate,
            ToolDefinition.subagentsUpdate,
            ToolDefinition.browserInspect,
            ToolDefinition.browserOpen
        ]
            + computerUseToolDefinitions
            + memoryToolDefinitions
            + mcpToolDefinitions
    }

    var toolExecutionOverride: AgentToolExecutionOverride? {
        WorkspaceToolExecutionOverrideCombiner.combine(
            activity: activityToolExecutionOverride,
            browser: browserToolExecutionOverride,
            computerUse: computerUseToolExecutionOverride,
            memory: WorkspaceMemoryRememberToolExecutor.executionOverride(directory: globalMemoryDirectory),
            mcp: mcpToolExecutionOverride,
            remoteProject: remoteProjectToolExecutionOverride
        )
    }

    private var computerUseToolDefinitions: [ToolDefinition] {
        computerUseBackend == nil ? [] : ToolDefinition.computerUseDefinitions
    }

    private var memoryToolDefinitions: [ToolDefinition] {
        globalMemoryDirectory == nil ? [] : [ToolDefinition.memoryRemember]
    }

    private var activityToolExecutionOverride: AgentToolExecutionOverride {
        { call, _ in
            switch call.name {
            case ToolDefinition.planUpdate.name:
                return PlanUpdateToolExecutor.execute(call)
            case ToolDefinition.handoffUpdate.name:
                return HandoffUpdateToolExecutor.execute(call)
            case ToolDefinition.subagentsUpdate.name:
                return SubagentProgressToolExecutor.execute(call)
            default:
                return nil
            }
        }
    }

    private var browserToolExecutionOverride: AgentToolExecutionOverride {
        if let browserToolOverride {
            return browserToolOverride
        }
        let snapshot = browser
        return { call, _ in
            var browser = snapshot
            var lastError: String?
            return WorkspaceBrowserToolExecutor.execute(
                call,
                workspaceRoot: nil,
                browser: &browser,
                lastError: &lastError,
                domainPolicy: config.browserDomainPolicy
            )
        }
    }

    private var computerUseToolExecutionOverride: AgentToolExecutionOverride? {
        guard let computerUseBackend else { return nil }
        let executor = ComputerUseToolExecutor(
            backend: computerUseBackend,
            appApprovalPolicy: ComputerUseAppApprovalPolicy(
                approvedBundleIdentifiers: config.computerUseApprovedBundleIdentifiers,
                approvedAppNames: config.computerUseApprovedAppNames
            )
        )
        return { call, _ in
            await executor.execute(call)
        }
    }

    private var remoteProjectToolExecutionOverride: AgentToolExecutionOverride? {
        WorkspaceRemoteProjectToolExecutor.executionOverride(
            project: selectedProject,
            executor: sshRemoteShellExecutor
        )
    }
}
