import Foundation
import QuillCodeCore
import QuillCodePersistence

@MainActor
extension QuillCodeWorkspaceModel {
    /// Keeps read-only navigation from turning a bounded launch working set back into every chat's
    /// full transcript. Selected, running, ephemeral, and persistence-failed chats stay resident.
    func enforceThreadPayloadResidency(
        maximumResidentActivePayloads: Int = JSONThreadStore.defaultMaximumResidentActivePayloads,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let retentionStart = ThreadPeriodUsageSnapshot.currentPeriodRetentionStart(
            now: now,
            calendar: calendar
        )
        let selectedID = root.selectedThreadID

        let releasableArchiveIDs = Array(root.threads.lazy
            .filter {
                $0.isArchived
                    && $0.payloadResidency.isLoaded
                    && $0.id != selectedID
                    && !self.agentRuns.isRunning($0.id)
                    && !self.isCancellableToolRunActive(for: $0.id)
            }
            .map(\.id))
        for id in releasableArchiveIDs {
            _ = threadPersistence.deferPayload(
                id,
                threads: &root.threads,
                retainingUsageSince: retentionStart,
                calendar: calendar,
                now: now
            )
        }

        let residentLimit = max(0, maximumResidentActivePayloads)
        var loadedActiveCount = root.threads.lazy.filter {
            !$0.isArchived && $0.payloadResidency.isLoaded && !$0.runtimeContext.isEphemeral
        }.count
        guard loadedActiveCount > residentLimit else { return }

        let releaseCandidates = root.threads.lazy
            .filter {
                !$0.isArchived
                    && $0.payloadResidency.isLoaded
                    && !$0.runtimeContext.isEphemeral
                    && $0.id != selectedID
                    && !self.agentRuns.isRunning($0.id)
                    && !self.isCancellableToolRunActive(for: $0.id)
            }
            .sorted { $0.updatedAt < $1.updatedAt }
            .map(\.id)
        for id in releaseCandidates where loadedActiveCount > residentLimit {
            if threadPersistence.deferPayload(
                id,
                threads: &root.threads,
                retainingUsageSince: retentionStart,
                calendar: calendar,
                now: now
            ) {
                loadedActiveCount -= 1
            }
        }
    }
}
