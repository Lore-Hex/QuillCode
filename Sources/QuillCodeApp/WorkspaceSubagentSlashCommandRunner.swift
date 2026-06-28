import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func runSubagentSlashCommand(_ request: WorkspaceSubagentRunRequest, originalPrompt: String) async {
        if selectedThread == nil {
            _ = newChat()
        }
        mutateSelectedThread { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = "Subagents"
            }
            thread.messages.append(ChatMessage(role: .user, content: originalPrompt))
        }
        threadPersistence.saveIfPossible(selectedThread)

        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)
        let result = await subagentScheduler.run(request: request) { [weak self] update in
            await self?.recordSubagentProgress(update)
        }
        guard !Task.isCancelled else {
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.stopped)
            return
        }

        mutateSelectedThread { thread in
            thread.messages.append(ChatMessage(role: .assistant, content: result.summary))
        }
        threadPersistence.saveIfPossible(selectedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    private func recordSubagentProgress(_ update: SubagentProgressUpdate) {
        let argumentsJSON = (try? JSONHelpers.encodePretty(update))
            ?? #"{"subagents":[]}"#
        let call = ToolCall(name: ToolDefinition.subagentsUpdate.name, argumentsJSON: argumentsJSON)
        let result = SubagentProgressToolExecutor.execute(call)
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
        }
        threadPersistence.saveIfPossible(selectedThread)
    }
}

private extension WorkspaceThreadPersistence {
    func saveIfPossible(_ thread: ChatThread?) {
        guard let thread else { return }
        save(thread)
    }
}
