import Foundation
import QuillCodeCore

/// Tracks the one SessionStart event due for each thread in this app process. The state is
/// intentionally in-memory: reopening QuillCode is a `resume`, while clearing a live thread can
/// re-arm the same durable thread id as `clear` without writing hook bookkeeping into its transcript.
final class WorkspaceSessionStartHookCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingSources: [UUID: ProjectPluginSessionStartSource]
    private var startedThreadIDs: Set<UUID> = []

    init(resumedThreadIDs: Set<UUID> = []) {
        pendingSources = Dictionary(uniqueKeysWithValues: resumedThreadIDs.map { ($0, .resume) })
    }

    func consumeSource(for threadID: UUID) -> ProjectPluginSessionStartSource? {
        lock.lock()
        defer { lock.unlock() }
        guard startedThreadIDs.insert(threadID).inserted else { return nil }
        return pendingSources.removeValue(forKey: threadID) ?? .startup
    }

    func registerCreatedThread(
        _ threadID: UUID,
        source: ProjectPluginSessionStartSource = .startup
    ) {
        reset(threadID: threadID, source: source)
    }

    func reset(threadID: UUID, source: ProjectPluginSessionStartSource) {
        lock.lock()
        pendingSources[threadID] = source
        startedThreadIDs.remove(threadID)
        lock.unlock()
    }

    func remove(threadID: UUID) {
        lock.lock()
        pendingSources[threadID] = nil
        startedThreadIDs.remove(threadID)
        lock.unlock()
    }
}
