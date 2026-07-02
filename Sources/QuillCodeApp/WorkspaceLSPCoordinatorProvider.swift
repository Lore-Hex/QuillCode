import Foundation
import QuillCodeTools

/// Process-wide, workspace-keyed cache of `LSPCoordinator`s. The coordinator holds a live
/// language-server subprocess, so it MUST persist across the many per-send `AgentRunner`s a workspace
/// produces — recreating it each send would relaunch sourcekit-lsp on every write. Keyed by the
/// standardized workspace path; one coordinator (and thus one server) per workspace.
///
/// The whole LSP surface is opt-in: `coordinator(forWorkspace:)` returns `nil` unless the
/// `QUILLCODE_LSP` environment flag is set, so the shipped default behavior is exactly as before
/// until a user turns it on. `QUILLCODE_LSP_FORMAT` additionally enables auto-format-on-save.
public final class WorkspaceLSPCoordinatorProvider: @unchecked Sendable {
    public static let shared = WorkspaceLSPCoordinatorProvider()

    private let lock = NSLock()
    private var coordinators: [String: LSPCoordinator] = [:]
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// The coordinator for a workspace, or `nil` when the feature is disabled. Local (non-remote)
    /// workspaces only — a remote project's files are not on this machine's filesystem, so a local
    /// language server cannot see them.
    public func coordinator(forWorkspace root: URL, isRemote: Bool) -> LSPCoordinator? {
        guard isEnabled, !isRemote else { return nil }
        let key = root.standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        if let existing = coordinators[key] { return existing }
        let coordinator = LSPCoordinator(workspaceRoot: root, formatOnSave: formatOnSave)
        coordinators[key] = coordinator
        return coordinator
    }

    /// Tears down every cached coordinator (and its server process). Call on app shutdown.
    public func shutdownAll() {
        lock.lock()
        defer { lock.unlock() }
        for coordinator in coordinators.values {
            coordinator.shutdown()
        }
        coordinators.removeAll()
    }

    private var isEnabled: Bool {
        flag("QUILLCODE_LSP")
    }

    private var formatOnSave: Bool {
        flag("QUILLCODE_LSP_FORMAT")
    }

    private func flag(_ name: String) -> Bool {
        switch environment[name]?.lowercased() {
        case "1", "true", "yes": return true
        default: return false
        }
    }
}
