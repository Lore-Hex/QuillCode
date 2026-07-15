import Foundation

public enum WorkflowRecordingPhase: String, Codable, Sendable, Hashable {
    case idle
    case recording
    case limitReached
}

public struct WorkflowRecordingStatus: Codable, Sendable, Hashable {
    public var phase: WorkflowRecordingPhase
    public var goal: String?
    public var startedAt: Date?
    public var eventCount: Int
    public var snapshotCount: Int

    public init(
        phase: WorkflowRecordingPhase,
        goal: String? = nil,
        startedAt: Date? = nil,
        eventCount: Int = 0,
        snapshotCount: Int = 0
    ) {
        self.phase = phase
        self.goal = Self.bounded(goal, limit: WorkflowRecordingLimits.goalCharacterCount)
        self.startedAt = startedAt
        self.eventCount = max(0, eventCount)
        self.snapshotCount = max(0, snapshotCount)
    }

    public static let idle = WorkflowRecordingStatus(phase: .idle)

    public var isRecording: Bool {
        phase != .idle
    }

    public var hasReachedDurationLimit: Bool {
        phase == .limitReached
    }

    private static func bounded(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }
}

public struct WorkflowRecordingRequest: Codable, Sendable, Hashable {
    public var goal: String
    public var originThreadID: String?
    public var projectID: String?
    public var workspaceRoot: String?
    public var artifactDirectory: String

    public init(
        goal: String,
        originThreadID: String? = nil,
        projectID: String? = nil,
        workspaceRoot: String? = nil,
        artifactDirectory: String
    ) {
        self.goal = Self.bounded(goal, limit: WorkflowRecordingLimits.goalCharacterCount)
        self.originThreadID = Self.optionalBounded(originThreadID, limit: 160)
        self.projectID = Self.optionalBounded(projectID, limit: 160)
        self.workspaceRoot = Self.optionalBounded(workspaceRoot, limit: 2_048)
        self.artifactDirectory = Self.bounded(artifactDirectory, limit: 4_096)
    }

    private static func bounded(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func optionalBounded(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let bounded = Self.bounded(value, limit: limit)
        return bounded.isEmpty ? nil : bounded
    }
}

public enum WorkflowRecordingEventKind: String, Codable, Sendable, Hashable {
    case applicationChanged
    case click
    case scroll
    case textInput
    case protectedInput
    case key
}

public struct WorkflowRecordingEvent: Codable, Sendable, Hashable {
    public var kind: WorkflowRecordingEventKind
    public var elapsedMilliseconds: Int
    public var summary: String
    public var application: ComputerUseApplication?
    public var x: Int?
    public var y: Int?

    public init(
        kind: WorkflowRecordingEventKind,
        elapsedMilliseconds: Int,
        summary: String,
        application: ComputerUseApplication? = nil,
        x: Int? = nil,
        y: Int? = nil
    ) {
        self.kind = kind
        self.elapsedMilliseconds = max(0, elapsedMilliseconds)
        self.summary = String(
            summary
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(WorkflowRecordingLimits.eventSummaryCharacterCount)
        )
        self.application = application
        self.x = x
        self.y = y
    }
}

public struct WorkflowRecordingSnapshot: Codable, Sendable, Hashable {
    public var path: String
    public var width: Int
    public var height: Int
    public var elapsedMilliseconds: Int
    public var application: ComputerUseApplication?

    public init(
        path: String,
        width: Int,
        height: Int,
        elapsedMilliseconds: Int,
        application: ComputerUseApplication? = nil
    ) {
        self.path = String(path.prefix(4_096))
        self.width = max(0, width)
        self.height = max(0, height)
        self.elapsedMilliseconds = max(0, elapsedMilliseconds)
        self.application = application
    }
}

public struct WorkflowRecordingCapture: Codable, Sendable, Hashable {
    public var goal: String
    public var startedAt: Date
    public var stoppedAt: Date
    public var originThreadID: String?
    public var projectID: String?
    public var workspaceRoot: String?
    public var events: [WorkflowRecordingEvent]
    public var snapshots: [WorkflowRecordingSnapshot]
    public var omittedEventCount: Int
    public var omittedSnapshotCount: Int
    public var reachedDurationLimit: Bool

    public init(
        goal: String,
        startedAt: Date,
        stoppedAt: Date,
        originThreadID: String? = nil,
        projectID: String? = nil,
        workspaceRoot: String? = nil,
        events: [WorkflowRecordingEvent],
        snapshots: [WorkflowRecordingSnapshot],
        omittedEventCount: Int = 0,
        omittedSnapshotCount: Int = 0,
        reachedDurationLimit: Bool = false
    ) {
        self.goal = String(goal.prefix(WorkflowRecordingLimits.goalCharacterCount))
        self.startedAt = startedAt
        self.stoppedAt = max(startedAt, stoppedAt)
        self.originThreadID = originThreadID
        self.projectID = projectID
        self.workspaceRoot = workspaceRoot
        self.events = Array(events.prefix(WorkflowRecordingLimits.eventCount))
        self.snapshots = Array(snapshots.prefix(WorkflowRecordingLimits.snapshotCount))
        self.omittedEventCount = max(
            0,
            omittedEventCount + events.count - self.events.count
        )
        self.omittedSnapshotCount = max(
            0,
            omittedSnapshotCount + snapshots.count - self.snapshots.count
        )
        self.reachedDurationLimit = reachedDurationLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            goal: try container.decode(String.self, forKey: .goal),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            stoppedAt: try container.decode(Date.self, forKey: .stoppedAt),
            originThreadID: try container.decodeIfPresent(String.self, forKey: .originThreadID),
            projectID: try container.decodeIfPresent(String.self, forKey: .projectID),
            workspaceRoot: try container.decodeIfPresent(String.self, forKey: .workspaceRoot),
            events: try container.decode([WorkflowRecordingEvent].self, forKey: .events),
            snapshots: try container.decode([WorkflowRecordingSnapshot].self, forKey: .snapshots),
            omittedEventCount: try container.decodeIfPresent(Int.self, forKey: .omittedEventCount) ?? 0,
            omittedSnapshotCount: try container.decodeIfPresent(Int.self, forKey: .omittedSnapshotCount) ?? 0,
            reachedDurationLimit: try container.decodeIfPresent(Bool.self, forKey: .reachedDurationLimit) ?? false
        )
    }

    public var durationSeconds: Int {
        max(0, Int(stoppedAt.timeIntervalSince(startedAt).rounded()))
    }

    public var artifactPaths: [String] {
        snapshots.map(\.path)
    }

    public func representativeSnapshots(maximumCount: Int) -> [WorkflowRecordingSnapshot] {
        let count = min(max(0, maximumCount), snapshots.count)
        guard count > 0 else { return [] }
        guard count < snapshots.count else { return snapshots }
        guard count > 1 else { return [snapshots[snapshots.count - 1]] }

        let lastIndex = snapshots.count - 1
        return (0..<count).map { position in
            let ratio = Double(position) / Double(count - 1)
            let index = Int((Double(lastIndex) * ratio).rounded())
            return snapshots[index]
        }
    }

    public var skillDraftingPrompt: String {
        var lines = [
            "The user finished demonstrating a workflow and asked QuillCode to turn it into a reusable skill.",
            "Goal: \(goal)",
            "Duration: \(durationSeconds) seconds",
            "",
            "Recorded actions:"
        ]
        if events.isEmpty {
            lines.append("- No input events were captured. Use only the screenshots and the user's stated goal.")
        } else {
            lines.append(contentsOf: events.enumerated().map { index, event in
                let seconds = Double(event.elapsedMilliseconds) / 1_000
                return String(format: "%d. [%.1fs] %@", index + 1, seconds, event.summary)
            })
        }
        if omittedEventCount > 0 {
            lines.append("- \(omittedEventCount) additional events were omitted by the privacy bound.")
        }
        if reachedDurationLimit {
            lines.append(
                "- Recording reached the \(WorkflowRecordingLimits.durationSeconds / 60)-minute limit; "
                    + "later actions were not captured."
            )
        }
        lines.append("")
        lines.append("Visual references (the app attaches a representative first-to-final subset):")
        if snapshots.isEmpty {
            lines.append("- No screenshots were captured.")
        } else {
            lines.append(contentsOf: snapshots.enumerated().map { index, snapshot in
                let app = snapshot.application.map { " in \($0.displayLabel)" } ?? ""
                return "\(index + 1). \(URL(fileURLWithPath: snapshot.path).lastPathComponent)\(app)"
            })
        }
        if omittedSnapshotCount > 0 {
            lines.append("- \(omittedSnapshotCount) additional screenshots were omitted by the privacy bound.")
        }
        lines.append("")
        lines.append(
            "Inspect the attached screenshots. Create or update one project skill at "
                + "`.quillcode/skills/<safe-slug>/SKILL.md` using the normal audited file tools. "
                + "Start it with YAML frontmatter containing a matching safe name and concise description. "
                + "Include when to use it, variable inputs, numbered replay steps, and verification. "
                + "Generalize user-specific values into inputs. Never include credentials, protected text, "
                + "or details not supported by the demonstration. Complete the skill in this turn."
        )
        return lines.joined(separator: "\n")
    }
}

public enum WorkflowRecordingLimits {
    public static let goalCharacterCount = 1_000
    public static let eventSummaryCharacterCount = 320
    public static let eventCount = 240
    public static let snapshotCount = 12
    public static let durationSeconds = 30 * 60
}

public protocol WorkflowRecordingStatusProviding: Sendable {
    var workflowRecordingStatusSnapshot: WorkflowRecordingStatus { get }
}

public protocol WorkflowRecordingBackend: WorkflowRecordingStatusProviding, Sendable {
    func workflowRecordingStatus() async -> WorkflowRecordingStatus
    func startWorkflowRecording(_ request: WorkflowRecordingRequest) async throws -> WorkflowRecordingStatus
    func stopWorkflowRecording() async throws -> WorkflowRecordingCapture
    func cancelWorkflowRecording() async
}
