import AppKit
import Foundation
import QuillCodeApp

/// Debounces live typing into the lightweight composer checkpoint store. The pending request owns
/// the selected thread identity from the keystroke boundary, so delayed work cannot cross chats.
@MainActor
final class QuillCodeDesktopComposerDraftCheckpointCoordinator: NSObject {
    static let defaultDelayNanoseconds: UInt64 = 350_000_000

    private struct Request: Equatable {
        var draft: String
        var ownerThreadID: UUID?
    }

    private let delayNanoseconds: UInt64
    private let notificationCenter: NotificationCenter
    private var pendingRequest: Request?
    private var pendingTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private weak var lifecycleModel: QuillCodeWorkspaceModel?

    init(
        delayNanoseconds: UInt64 = defaultDelayNanoseconds,
        notificationCenter: NotificationCenter = .default
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.notificationCenter = notificationCenter
        super.init()
    }

    deinit {
        pendingTask?.cancel()
        notificationCenter.removeObserver(self)
    }

    var hasPendingCheckpoint: Bool {
        pendingRequest != nil
    }

    func schedule(draft: String, model: QuillCodeWorkspaceModel) {
        guard model.composer.draft != draft else {
            cancelPending()
            return
        }
        pendingRequest = Request(
            draft: draft,
            ownerThreadID: model.selectedThread?.id
        )
        generation &+= 1
        let scheduledGeneration = generation
        pendingTask?.cancel()
        let delayNanoseconds = delayNanoseconds
        pendingTask = Task { @MainActor [weak self, weak model] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard let self, let model, generation == scheduledGeneration else { return }
            flush(on: model)
        }
    }

    func flush(on model: QuillCodeWorkspaceModel) {
        generation &+= 1
        pendingTask?.cancel()
        pendingTask = nil
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        model.checkpointComposerDraft(
            request.draft,
            ownerThreadID: request.ownerThreadID
        )
    }

    func startLifecycleFlushes(model: QuillCodeWorkspaceModel) {
        guard lifecycleModel == nil else { return }
        lifecycleModel = model
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            notificationCenter.addObserver(
                self,
                selector: #selector(flushForApplicationLifecycle),
                name: name,
                object: nil
            )
        }
    }

    @objc private func flushForApplicationLifecycle(_ notification: Notification) {
        guard let lifecycleModel else { return }
        flush(on: lifecycleModel)
    }

    private func cancelPending() {
        generation &+= 1
        pendingRequest = nil
        pendingTask?.cancel()
        pendingTask = nil
    }
}
