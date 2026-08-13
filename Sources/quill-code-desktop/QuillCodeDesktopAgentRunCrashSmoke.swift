import Darwin
import Foundation
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence

@MainActor
enum QuillCodeDesktopAgentRunCrashSmoke {
    static func runAndExit(
        _ request: QuillCodeDesktopAgentRunCrashSmokeRequest,
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopAgentRunCrashSmokeWorkspaceRoot
    ) async {
        do {
            switch request.phase {
            case "write":
                try await startToolAndCrash(controller: controller, workspaceRoot: workspaceRoot)
            case "verify":
                try await verifyRecoveredRun(controller: controller, workspaceRoot: workspaceRoot)
                exit(0)
            default:
                throw Failure.invalidPhase(request.phase)
            }
        } catch {
            FileHandle.standardError.write(
                Data("quill-code-desktop agent run crash smoke failed: \(error)\n".utf8)
            )
            exit(1)
        }
    }

    private static func startToolAndCrash(
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopAgentRunCrashSmokeWorkspaceRoot
    ) async throws {
        try FileManager.default.createDirectory(
            at: workspaceRoot.workspace,
            withIntermediateDirectories: true
        )
        let childPIDURL = workspaceRoot.workspace.appendingPathComponent("crash-child.pid")
        let quotedPIDPath = childPIDURL.path.replacingOccurrences(of: "'", with: "'\\''")
        controller.draft = "Run `printf '%s' \"$$\" > '\(quotedPIDPath)'; sleep 30`"
        controller.send()
        let store = JSONThreadStore(
            directory: QuillCodePaths(home: workspaceRoot.appState).threadsDirectory
        )

        for _ in 0..<400 {
            if let threadID = controller.model.selectedThread?.id,
               let persisted = try? store.load(threadID),
               persisted.activeRunCheckpoint != nil,
               persisted.events.contains(where: {
                   $0.kind == .toolQueued || $0.kind == .toolRunning || $0.kind == .toolProgress
               }),
               let childPID = liveChildPID(at: childPIDURL) {
                FileHandle.standardOutput.write(
                    Data("agent tool checkpointed before SIGKILL (child \(childPID))\n".utf8)
                )
                FileHandle.standardOutput.synchronizeFile()
                guard Darwin.kill(getpid(), SIGKILL) == 0 else {
                    throw Failure.couldNotTerminate
                }
                throw Failure.couldNotTerminate
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw Failure.checkpointTimedOut
    }

    private static func verifyRecoveredRun(
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopAgentRunCrashSmokeWorkspaceRoot
    ) async throws {
        let childPIDURL = workspaceRoot.workspace.appendingPathComponent("crash-child.pid")
        guard let childPID = recordedChildPID(at: childPIDURL) else {
            throw Failure.missingChildPID
        }
        for _ in 0..<80 where processIsAlive(childPID) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard !processIsAlive(childPID) else {
            throw Failure.childProcessSurvived(childPID)
        }

        controller.refresh()
        guard let thread = controller.model.selectedThread else {
            throw Failure.missingRecoveredThread
        }
        guard thread.activeRunCheckpoint == nil else { throw Failure.checkpointSurvived }
        guard !controller.model.isAgentRunActive(for: thread.id),
              !controller.model.composer.isSending
        else {
            throw Failure.runStillActive
        }
        guard controller.surface.transcript.toolCards.last?.status == .failed else {
            throw Failure.toolCardDidNotFail
        }
        guard controller.surface.runtimeIssue?.title == "Run interrupted" else {
            throw Failure.missingRecoveryIssue
        }
        guard controller.model.canRetryFailedRun(threadID: thread.id) else {
            throw Failure.retryUnavailable
        }
        guard controller.model.prepareRetryLastUserTurn(),
              controller.model.composer.draft == QuillCodeWorkspaceModel.failedRunRetryPrompt
        else {
            throw Failure.unsafeRetryDraft
        }

        let persisted = try JSONThreadStore(
            directory: QuillCodePaths(home: workspaceRoot.appState).threadsDirectory
        ).load(thread.id)
        guard persisted.activeRunCheckpoint == nil,
              persisted.events.suffix(2).map(\.kind) == [.toolFailed, .notice]
        else {
            throw Failure.recoveryWasNotPersisted
        }
        FileHandle.standardOutput.write(Data("agent run recovered after SIGKILL\n".utf8))
    }

    private static func liveChildPID(at url: URL) -> pid_t? {
        guard let pid = recordedChildPID(at: url), processIsAlive(pid) else { return nil }
        return pid
    }

    private static func recordedChildPID(at url: URL) -> pid_t? {
        guard let value = try? String(contentsOf: url, encoding: .utf8),
              let pid = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 1
        else {
            return nil
        }
        return pid
    }

    private static func processIsAlive(_ pid: pid_t) -> Bool {
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }

    private enum Failure: LocalizedError {
        case checkpointSurvived
        case checkpointTimedOut
        case childProcessSurvived(pid_t)
        case couldNotTerminate
        case invalidPhase(String)
        case missingRecoveredThread
        case missingRecoveryIssue
        case missingChildPID
        case recoveryWasNotPersisted
        case retryUnavailable
        case runStillActive
        case toolCardDidNotFail
        case unsafeRetryDraft

        var errorDescription: String? {
            switch self {
            case .checkpointSurvived: "The relaunched thread still owns the dead run checkpoint."
            case .checkpointTimedOut: "The live tool boundary was not persisted before the deadline."
            case .childProcessSurvived(let pid):
                "The shell child survived the desktop hard crash (PID \(pid))."
            case .couldNotTerminate: "The writer process could not terminate itself with SIGKILL."
            case .invalidPhase(let phase): "The agent run crash smoke phase is invalid: \(phase)"
            case .missingRecoveredThread: "The relaunched app did not restore the run owner."
            case .missingRecoveryIssue: "The relaunched app did not present Run interrupted."
            case .missingChildPID: "The crash writer did not record its live shell child."
            case .recoveryWasNotPersisted: "The repaired terminal events were not saved."
            case .retryUnavailable: "The interrupted run was not retryable."
            case .runStillActive: "The dead run was still projected as active after relaunch."
            case .toolCardDidNotFail: "The interrupted tool card did not become Failed."
            case .unsafeRetryDraft: "Retry did not prepare the cautious continuation prompt."
            }
        }
    }
}
