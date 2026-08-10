import Darwin
import Foundation
import QuillCodePersistence

@MainActor
enum QuillCodeDesktopComposerDraftCrashSmoke {
    private static let expectedDraft = "Packaged crash recovery keeps this unsent text."

    static func runAndExit(
        _ request: QuillCodeDesktopComposerDraftCrashSmokeRequest,
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopComposerDraftCrashSmokeWorkspaceRoot
    ) async {
        do {
            switch request.phase {
            case "write":
                try await checkpointAndCrash(controller: controller, workspaceRoot: workspaceRoot)
            case "verify":
                try verifyAndClean(controller: controller, workspaceRoot: workspaceRoot)
                exit(0)
            default:
                throw Failure.invalidPhase(request.phase)
            }
        } catch {
            FileHandle.standardError.write(
                Data("quill-code-desktop composer draft crash smoke failed: \(error)\n".utf8)
            )
            exit(1)
        }
    }

    private static func checkpointAndCrash(
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopComposerDraftCrashSmokeWorkspaceRoot
    ) async throws {
        let threadID = controller.model.newChat()
        controller.refresh()
        controller.draft = expectedDraft

        let store = ComposerDraftCheckpointStore(
            directory: QuillCodePaths(home: workspaceRoot.appState).composerDraftsDirectory
        )
        for _ in 0..<200 {
            if try store.load(for: threadID)?.draft == expectedDraft {
                FileHandle.standardOutput.write(Data("composer draft checkpointed before SIGKILL\n".utf8))
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

    private static func verifyAndClean(
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopComposerDraftCrashSmokeWorkspaceRoot
    ) throws {
        guard let threadID = controller.model.selectedThread?.id else {
            throw Failure.missingRecoveredThread
        }
        guard controller.model.composer.draft == expectedDraft else {
            throw Failure.draftMismatch(controller.model.composer.draft)
        }

        let store = ComposerDraftCheckpointStore(
            directory: QuillCodePaths(home: workspaceRoot.appState).composerDraftsDirectory
        )
        guard try store.load(for: threadID)?.draft == expectedDraft else {
            throw Failure.missingCheckpoint
        }
        controller.model.setDraft("")
        guard try store.load(for: threadID)?.draft == nil else {
            throw Failure.tombstoneWasNotWritten
        }
        FileHandle.standardOutput.write(Data("composer draft recovered after SIGKILL\n".utf8))
    }

    private enum Failure: LocalizedError {
        case checkpointTimedOut
        case couldNotTerminate
        case draftMismatch(String)
        case invalidPhase(String)
        case missingCheckpoint
        case missingRecoveredThread
        case tombstoneWasNotWritten

        var errorDescription: String? {
            switch self {
            case .checkpointTimedOut:
                "The live composer draft was not checkpointed before the deadline."
            case .couldNotTerminate:
                "The writer process could not terminate itself with SIGKILL."
            case .draftMismatch(let draft):
                "The relaunched composer restored an unexpected draft: \(draft)"
            case .invalidPhase(let phase):
                "The composer draft crash smoke phase is invalid: \(phase)"
            case .missingCheckpoint:
                "The relaunched app could not read the expected composer checkpoint."
            case .missingRecoveredThread:
                "The relaunched app did not restore the checkpoint owner."
            case .tombstoneWasNotWritten:
                "Clearing the recovered draft did not write a durable tombstone."
            }
        }
    }
}
