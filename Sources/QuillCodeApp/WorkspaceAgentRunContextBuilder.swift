import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

struct WorkspaceAgentRunContextBuilder: Sendable {
    var selectedProject: ProjectRef?
    var browser: BrowserState
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
        [ToolDefinition.planUpdate, ToolDefinition.browserInspect]
            + computerUseToolDefinitions
            + memoryToolDefinitions
            + mcpToolDefinitions
    }

    var toolExecutionOverride: AgentToolExecutionOverride? {
        WorkspaceToolExecutionOverrideCombiner.combine(
            plan: planToolExecutionOverride,
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

    private var planToolExecutionOverride: AgentToolExecutionOverride {
        { call, _ in
            guard call.name == ToolDefinition.planUpdate.name else { return nil }
            return PlanUpdateToolExecutor.execute(call)
        }
    }

    private var browserToolExecutionOverride: AgentToolExecutionOverride {
        let snapshot = browser
        return { call, _ in
            guard call.name == ToolDefinition.browserInspect.name else { return nil }
            return BrowserInspector.toolResult(from: snapshot)
        }
    }

    private var computerUseToolExecutionOverride: AgentToolExecutionOverride? {
        guard let computerUseBackend else { return nil }
        let executor = ComputerUseToolExecutor(backend: computerUseBackend)
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
