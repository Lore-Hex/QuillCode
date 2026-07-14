import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillComputerUseKit

@MainActor
extension QuillCodeWorkspaceModel {
    public var workflowRecordingStatus: WorkflowRecordingStatus? {
        (computerUseBackend as? any WorkflowRecordingStatusProviding)?
            .workflowRecordingStatusSnapshot
    }

    public func stopWorkflowRecordingCapture() async throws -> WorkflowRecordingCapture {
        guard let recorder = computerUseBackend as? any WorkflowRecordingBackend else {
            throw ComputerUseError.unavailable(
                "Workflow recording is not supported by this Computer Use backend."
            )
        }
        do {
            let capture = try await recorder.stopWorkflowRecording()
            setLastError(nil)
            return capture
        } catch {
            setLastError(String(describing: error))
            throw error
        }
    }

    public func cancelWorkflowRecording() async {
        guard let recorder = computerUseBackend as? any WorkflowRecordingBackend else { return }
        await recorder.cancelWorkflowRecording()
    }

    /// Completes a consented Record & Replay session through the ordinary TrustedRouter agent
    /// runtime. The bounded capture is persisted as hidden tool feedback so raw action telemetry
    /// does not become a giant user bubble, while the visible user turn stays concise. Skill files
    /// are still created only through normal audited file tools.
    public func submitWorkflowRecordingCapture(
        _ capture: WorkflowRecordingCapture,
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)? = nil,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async {
        guard let threadID = ensureWorkflowRecordingThread(for: capture) else { return }
        let attachments = workflowRecordingAttachments(for: capture)
        guard appendWorkflowRecordingFeedback(
            capture.skillDraftingPrompt,
            attachments: attachments,
            threadID: threadID
        ) else { return }

        guard let first = await runAgentTurn(
            prompt: "Create the reusable skill from the workflow I just demonstrated.",
            threadID: threadID,
            clearingDraftFor: nil,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        ) else { return }

        await drainFollowUpQueue(
            after: first,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        )
    }

    @discardableResult
    func prepareStoppedWorkflowRecordingForComposer() async -> Bool {
        do {
            let capture = try await stopWorkflowRecordingCapture()
            let threadID = ensureWorkflowRecordingThread(for: capture)
            let attachments = workflowRecordingAttachments(for: capture)
            setDraft(capture.skillDraftingPrompt)
            composer.attachments = attachments
            persistComposerAttachments(attachments, for: threadID)
            setLastError(nil)
            return true
        } catch {
            setLastError(String(describing: error))
            return false
        }
    }

    func ensureWorkflowRecordingThread(for capture: WorkflowRecordingCapture) -> UUID? {
        if let rawID = capture.originThreadID,
           let threadID = UUID(uuidString: rawID),
           root.threads.contains(where: { $0.id == threadID }) {
            selectThread(threadID)
            return threadID
        }
        let projectID = capture.projectID
            .flatMap(UUID.init(uuidString:))
            .flatMap { candidate in root.projects.contains(where: { $0.id == candidate }) ? candidate : nil }
        return newChat(projectID: projectID)
    }

    func workflowRecordingAttachments(
        for capture: WorkflowRecordingCapture
    ) -> [ChatAttachment] {
        guard let imageAttachmentStore else { return [] }
        let snapshots = capture.representativeSnapshots(
            maximumCount: ChatAttachment.maximumCountPerTurn
        )
        return snapshots.enumerated().compactMap { index, snapshot in
            try? imageAttachmentStore.attachmentForManagedImage(
                at: URL(fileURLWithPath: snapshot.path),
                displayName: "Workflow recording \(index + 1) of \(snapshots.count).png"
            )
        }
    }

    private func appendWorkflowRecordingFeedback(
        _ content: String,
        attachments: [ChatAttachment],
        threadID: UUID
    ) -> Bool {
        guard let index = root.threads.firstIndex(where: { $0.id == threadID }) else {
            return false
        }
        root.threads[index].messages.append(ChatMessage(
            role: .tool,
            content: content,
            attachments: attachments
        ))
        root.threads[index].updatedAt = Date()
        threadPersistence.save(root.threads[index])
        return true
    }
}
