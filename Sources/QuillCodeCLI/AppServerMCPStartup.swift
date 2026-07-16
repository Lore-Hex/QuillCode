import Foundation
import QuillCodeTools

private enum AppServerMCPStartupOutcome: Sendable {
    case ready
    case failed(String)
    case cancelled
}

private enum AppServerMCPStartupStatus: String, Sendable {
    case starting
    case ready
    case failed
    case cancelled
}

private enum AppServerMCPStartupFailureReason: String, Sendable {
    case reauthenticationRequired
}

extension AppServerSession {
    func validateRequiredMCPServers(for record: AppServerThreadRecord) async throws {
        let context = try mcpContext(for: record)
        var failures: [String] = []
        for configuration in context.configurations.values
            .filter(\.required)
            .sorted(by: { $0.name < $1.name }) {
            switch await prepareMCPServer(
                context: context,
                configuration: configuration,
                threadID: record.thread.id
            ) {
            case .ready:
                break
            case .failed(let error):
                failures.append("\(configuration.name): \(error)")
            case .cancelled:
                throw CancellationError()
            }
        }
        guard failures.isEmpty else {
            throw AppServerMCPRequiredServersError(failures: failures)
        }
    }

    func launchOptionalMCPServerStartups(for threadID: UUID) {
        guard mcpStartupTasks[threadID] == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performOptionalMCPServerStartups(for: threadID)
        }
        mcpStartupTasks[threadID] = task
    }

    func cancelAllMCPServerStartups() {
        let tasks = mcpStartupTasks.values
        mcpStartupTasks.removeAll(keepingCapacity: false)
        for task in tasks { task.cancel() }
    }

    private func performOptionalMCPServerStartups(for threadID: UUID) async {
        defer { mcpStartupTasks.removeValue(forKey: threadID) }
        guard !Task.isCancelled,
              let record = try? await repository.load(threadID),
              let context = try? mcpContext(for: record)
        else {
            return
        }
        for configuration in context.configurations.values
            .filter({ !$0.required })
            .sorted(by: { $0.name < $1.name }) {
            guard !Task.isCancelled else { return }
            _ = await prepareMCPServer(
                context: context,
                configuration: configuration,
                threadID: threadID
            )
        }
    }

    private func prepareMCPServer(
        context: AppServerMCPContext,
        configuration: AppServerMCPServerConfiguration,
        threadID: UUID
    ) async -> AppServerMCPStartupOutcome {
        if await mcpRegistry.isServerReady(
            scope: context.scope,
            configuration: configuration,
            detail: .toolsAndAuthOnly
        ) {
            return .ready
        }

        await sendMCPStartupUpdate(
            threadID: threadID,
            server: configuration.name,
            status: .starting,
            error: nil
        )
        do {
            try Task.checkCancellation()
            try await mcpRegistry.prepareServer(
                scope: context.scope,
                configuration: configuration,
                detail: .toolsAndAuthOnly
            )
            try Task.checkCancellation()
            await sendMCPStartupUpdate(
                threadID: threadID,
                server: configuration.name,
                status: .ready,
                error: nil
            )
            return .ready
        } catch is CancellationError {
            await sendMCPStartupUpdate(
                threadID: threadID,
                server: configuration.name,
                status: .cancelled,
                error: nil
            )
            return .cancelled
        } catch {
            if Task.isCancelled {
                await sendMCPStartupUpdate(
                    threadID: threadID,
                    server: configuration.name,
                    status: .cancelled,
                    error: nil
                )
                return .cancelled
            }
            let description = String(error.localizedDescription.prefix(2_000))
            await sendMCPStartupUpdate(
                threadID: threadID,
                server: configuration.name,
                status: .failed,
                error: description
            )
            return .failed(description)
        }
    }

    private func sendMCPStartupUpdate(
        threadID: UUID,
        server: String,
        status: AppServerMCPStartupStatus,
        error: String?,
        failureReason: AppServerMCPStartupFailureReason? = nil
    ) async {
        guard !inputFinished else { return }
        await sendNotification("mcpServer/startupStatus/updated", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "name": .string(server),
            "status": .string(status.rawValue),
            "error": error.map(CLIJSONValue.string) ?? .null,
            "failureReason": failureReason.map { .string($0.rawValue) } ?? .null
        ]))
    }
}
