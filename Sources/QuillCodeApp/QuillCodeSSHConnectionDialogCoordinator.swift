import SwiftUI
import QuillCodeCore
import QuillCodeTools

@MainActor
final class QuillCodeSSHConnectionDialogCoordinator: ObservableObject {
    @Published var isPresented = false
    @Published var draft = QuillCodeSSHConnectionDraft()

    private var discoveryTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var presentationID = UUID()

    func present(loadHosts: @escaping () async -> SSHHostDiscoveryResult) {
        cancelTasks()
        presentationID = UUID()
        draft = QuillCodeSSHConnectionDraft()
        isPresented = true
        load(using: loadHosts, presentationID: presentationID)
    }

    func retry(loadHosts: @escaping () async -> SSHHostDiscoveryResult) {
        guard isPresented else { return }
        discoveryTask?.cancel()
        draft.hostLoad = .loading
        draft.errorMessage = nil
        load(using: loadHosts, presentationID: presentationID)
    }

    func selectHost(_ host: SSHHostConfiguration) {
        draft.selectedHostID = host.id
        draft.errorMessage = nil
    }

    func connect(
        register: @escaping (WorkspaceSSHProjectRequest) async -> WorkspaceSSHProjectRegistrationResult
    ) {
        guard isPresented, let request = draft.request, !draft.isConnecting else { return }
        connectionTask?.cancel()
        draft.isConnecting = true
        draft.errorMessage = nil
        let expectedPresentationID = presentationID
        connectionTask = Task { [weak self] in
            let result = await register(request)
            guard !Task.isCancelled,
                  let self,
                  self.isPresented,
                  self.presentationID == expectedPresentationID
            else { return }
            self.draft.isConnecting = false
            switch result {
            case .success:
                self.finishPresentation()
            case .failure(let message):
                self.draft.errorMessage = message
            }
        }
    }

    func dismiss() {
        guard isPresented else { return }
        finishPresentation()
    }

    private func load(
        using loadHosts: @escaping () async -> SSHHostDiscoveryResult,
        presentationID expectedPresentationID: UUID
    ) {
        discoveryTask = Task { [weak self] in
            let result = await loadHosts()
            guard !Task.isCancelled,
                  let self,
                  self.isPresented,
                  self.presentationID == expectedPresentationID
            else { return }
            self.draft.apply(result)
        }
    }

    private func finishPresentation() {
        cancelTasks()
        presentationID = UUID()
        draft.isConnecting = false
        isPresented = false
    }

    private func cancelTasks() {
        discoveryTask?.cancel()
        connectionTask?.cancel()
        discoveryTask = nil
        connectionTask = nil
    }
}
