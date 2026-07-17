import Foundation

public struct WorkspaceNavigationLocation: Codable, Sendable, Hashable {
    public var threadID: UUID?
    public var projectID: UUID?

    public init(threadID: UUID? = nil, projectID: UUID? = nil) {
        self.threadID = threadID
        self.projectID = projectID
    }

    public var isEmpty: Bool {
        threadID == nil && projectID == nil
    }
}

public struct WorkspaceNavigationHistoryState: Codable, Sendable, Hashable {
    public static let maximumEntryCount = 100

    public private(set) var entries: [WorkspaceNavigationLocation]
    public private(set) var currentIndex: Int

    public init(entries: [WorkspaceNavigationLocation] = [], currentIndex: Int = -1) {
        self.entries = entries.filter { !$0.isEmpty }
        let droppedEntryCount = max(0, self.entries.count - Self.maximumEntryCount)
        if droppedEntryCount > 0 {
            self.entries.removeFirst(droppedEntryCount)
        }

        if self.entries.isEmpty {
            self.currentIndex = -1
        } else {
            self.currentIndex = min(max(currentIndex - droppedEntryCount, 0), self.entries.count - 1)
        }
    }

    public var canGoBack: Bool {
        currentIndex > 0 && entries.indices.contains(currentIndex)
    }

    public var canGoForward: Bool {
        entries.indices.contains(currentIndex) && currentIndex < entries.count - 1
    }

    public mutating func recordTransition(
        from oldLocation: WorkspaceNavigationLocation,
        to newLocation: WorkspaceNavigationLocation
    ) {
        guard oldLocation != newLocation, !newLocation.isEmpty else { return }

        if entries.isEmpty {
            if !oldLocation.isEmpty {
                entries.append(oldLocation)
            }
            entries.append(newLocation)
            currentIndex = entries.count - 1
            return
        }

        if !entries.indices.contains(currentIndex) || entries[currentIndex] != oldLocation {
            entries = oldLocation.isEmpty ? [] : [oldLocation]
            currentIndex = entries.isEmpty ? -1 : 0
        } else if currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)..<entries.count)
        }

        entries.append(newLocation)
        trimToMaximumEntries()
        currentIndex = entries.count - 1
    }

    /// Removes every entry referencing `threadID` and collapses the adjacent duplicates that removal
    /// creates. Used when a session-only (incognito) thread is destroyed: Back/Forward must never be
    /// able to resurrect a conversation the UI promised was gone.
    public mutating func pruneEntries(withThreadID threadID: UUID) {
        guard entries.contains(where: { $0.threadID == threadID }) else { return }
        let currentLocation = entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
        var pruned: [WorkspaceNavigationLocation] = []
        for entry in entries where entry.threadID != threadID {
            if pruned.last != entry {
                pruned.append(entry)
            }
        }
        entries = pruned
        if let currentLocation,
           currentLocation.threadID != threadID,
           let index = pruned.lastIndex(of: currentLocation) {
            currentIndex = index
        } else {
            currentIndex = pruned.count - 1
        }
    }

    public mutating func goBack() -> WorkspaceNavigationLocation? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return entries[currentIndex]
    }

    public mutating func goForward() -> WorkspaceNavigationLocation? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return entries[currentIndex]
    }

    public mutating func prune(validThreadIDs: Set<UUID>, validProjectIDs: Set<UUID>) {
        guard !entries.isEmpty else { return }
        let currentLocation = entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
        entries = entries.filter { location in
            if let threadID = location.threadID {
                return validThreadIDs.contains(threadID)
            }
            if let projectID = location.projectID {
                return validProjectIDs.contains(projectID)
            }
            return false
        }

        if entries.isEmpty {
            currentIndex = -1
            return
        }

        if let currentLocation,
           let preservedIndex = entries.firstIndex(of: currentLocation) {
            currentIndex = preservedIndex
        } else {
            currentIndex = min(max(currentIndex, 0), entries.count - 1)
        }
    }

    private mutating func trimToMaximumEntries() {
        let droppedEntryCount = entries.count - Self.maximumEntryCount
        guard droppedEntryCount > 0 else { return }
        entries.removeFirst(droppedEntryCount)
        currentIndex = max(-1, currentIndex - droppedEntryCount)
    }
}
