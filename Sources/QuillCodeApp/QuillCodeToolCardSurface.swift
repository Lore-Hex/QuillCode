import Foundation
import QuillCodeCore

public enum ToolCardStatus: String, Codable, Sendable, Hashable {
    case queued
    case running
    case done
    case failed
    case review
}

public enum ToolCardReviewState: String, Codable, Sendable, Hashable {
    case none
    case ready
    case needsReview
}

public enum ToolCardActionKind: String, Codable, Sendable, Hashable {
    case approve
    case edit
    case deny
    /// Approve AND save a persisted always-allow permission rule for this exact action + resource.
    case approveAlways
    /// Skip AND save a persisted always-deny permission rule for this exact action + resource.
    case denyAlways

    /// Kinds that run the held tool when acted on (and afterwards resume a Plan-mode run) — the
    /// approve family. Routing (desktop send-slot gating, resume-after-approval) keys off this so
    /// "Always allow" behaves exactly like "Run" plus the saved rule.
    public var approvesHeldTool: Bool {
        self == .approve || self == .approveAlways
    }

    /// Kinds that RESOLVE the approval gate — the approve family and the deny family. `.edit` does
    /// not decide the gate (it seeds a composer draft and leaves the request undecided for a
    /// re-submit). The desktop routes every gate-deciding action through the async approval choke
    /// point so a queued follow-up drains once the gate is settled — for a deny/skip as well as an
    /// approve, in every mode.
    public var decidesGate: Bool {
        self == .approve || self == .approveAlways || self == .deny || self == .denyAlways
    }
}

public enum ToolCardActionStyle: String, Codable, Sendable, Hashable {
    case primary
    case secondary
    case destructive
}

public struct WorkspaceSubagentApprovalTarget: Codable, Sendable, Hashable {
    public var parentThreadID: UUID
    public var runID: UUID
    public var workerID: String
    public var generation: Int

    public init(parentThreadID: UUID, runID: UUID, workerID: String, generation: Int) {
        self.parentThreadID = parentThreadID
        self.runID = runID
        self.workerID = workerID
        self.generation = generation
    }
}

public struct ToolCardActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var kind: ToolCardActionKind
    public var requestID: String
    public var style: ToolCardActionStyle
    public var systemImage: String?
    /// Fully pins a private delegated approval to its parent/run/worker generation. Nil preserves
    /// the ordinary selected-thread approval path.
    public var subagentTarget: WorkspaceSubagentApprovalTarget?

    public init(
        id: String? = nil,
        title: String,
        kind: ToolCardActionKind,
        requestID: String,
        style: ToolCardActionStyle,
        systemImage: String? = nil,
        subagentTarget: WorkspaceSubagentApprovalTarget? = nil
    ) {
        self.id = id ?? ["tool-card-action", kind.rawValue, requestID, subagentTarget?.workerID]
            .compactMap { $0 }
            .joined(separator: "-")
        self.title = title
        self.kind = kind
        self.requestID = requestID
        self.style = style
        self.systemImage = systemImage
        self.subagentTarget = subagentTarget
    }
}

public enum ToolCardDensity: String, Codable, Sendable, Hashable {
    case collapsed
    case peek
    case expanded
}

public struct ToolProgressSurface: Codable, Sendable, Hashable {
    public var completed: Double
    public var total: Double?
    public var message: String?

    public init(progress: ToolExecutionProgress) {
        self.completed = progress.completed
        self.total = progress.total
        self.message = progress.message
    }

    public var fractionCompleted: Double? {
        ToolExecutionProgress(
            completed: completed,
            total: total,
            message: message
        ).fractionCompleted
    }

    public var percentLabel: String? {
        fractionCompleted.map { "\(Int(($0 * 100).rounded()))%" }
    }
}

public struct ToolCardState: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var status: ToolCardStatus
    public var executionContext: ExecutionContextSurface?
    public var inputJSON: String?
    public var outputJSON: String?
    public var progress: ToolProgressSurface?
    public var artifacts: [ToolArtifactState]
    public var actions: [ToolCardActionSurface]
    public var isExpanded: Bool
    public var density: ToolCardDensity
    public var reviewState: ToolCardReviewState

    public init(
        id: String,
        title: String,
        subtitle: String,
        status: ToolCardStatus,
        executionContext: ExecutionContextSurface? = nil,
        inputJSON: String? = nil,
        outputJSON: String? = nil,
        progress: ToolProgressSurface? = nil,
        artifacts: [ToolArtifactState] = [],
        actions: [ToolCardActionSurface] = [],
        isExpanded: Bool = false,
        density: ToolCardDensity? = nil,
        reviewState: ToolCardReviewState? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.executionContext = executionContext
        self.inputJSON = inputJSON
        self.outputJSON = outputJSON
        self.progress = progress
        self.artifacts = artifacts
        self.actions = actions
        self.isExpanded = isExpanded
        self.density = density ?? Self.defaultDensity(status: status, isExpanded: isExpanded)
        self.reviewState = reviewState ?? Self.defaultReviewState(
            status: status,
            actions: actions,
            subtitle: subtitle
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case status
        case executionContext
        case inputJSON
        case outputJSON
        case progress
        case artifacts
        case actions
        case isExpanded
        case density
        case reviewState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.status = try container.decode(ToolCardStatus.self, forKey: .status)
        self.executionContext = try container.decodeIfPresent(ExecutionContextSurface.self, forKey: .executionContext)
        self.inputJSON = try container.decodeIfPresent(String.self, forKey: .inputJSON)
        self.outputJSON = try container.decodeIfPresent(String.self, forKey: .outputJSON)
        self.progress = try container.decodeIfPresent(ToolProgressSurface.self, forKey: .progress)
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.actions = try container.decodeIfPresent([ToolCardActionSurface].self, forKey: .actions) ?? []
        self.isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        self.density = try container.decodeIfPresent(ToolCardDensity.self, forKey: .density)
            ?? Self.defaultDensity(status: status, isExpanded: isExpanded)
        self.reviewState = try container.decodeIfPresent(ToolCardReviewState.self, forKey: .reviewState)
            ?? Self.defaultReviewState(status: status, actions: actions, subtitle: subtitle)
    }

    public static func defaultDensity(status: ToolCardStatus, isExpanded: Bool = false) -> ToolCardDensity {
        if isExpanded {
            return .expanded
        }
        switch status {
        case .queued, .running:
            return .peek
        case .done:
            return .collapsed
        case .failed, .review:
            return .expanded
        }
    }

    public var opensDetailsByDefault: Bool {
        density == .expanded
    }

    public static func defaultReviewState(
        status: ToolCardStatus,
        actions: [ToolCardActionSurface] = [],
        subtitle: String = ""
    ) -> ToolCardReviewState {
        guard status == .review else {
            return .none
        }
        // Compatibility fallback for older encoded surfaces and simple harness fixtures.
        if actions.isEmpty,
           subtitle.localizedCaseInsensitiveContains("Blocked") {
            return .needsReview
        }
        return .ready
    }

    public var statusDisplayLabel: String {
        switch status {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .review:
            return needsReview ? "Needs review" : "Ready"
        }
    }

    public var statusAccessibilityLabel: String {
        switch status {
        case .review:
            return needsReview ? "needs review" : "ready to run"
        default:
            return status.rawValue
        }
    }

    public var needsReview: Bool {
        status == .review && reviewState == .needsReview
    }

    public var densityAccessibilityLabel: String {
        switch density {
        case .collapsed:
            return "collapsed"
        case .peek:
            return "preview"
        case .expanded:
            return "expanded"
        }
    }

    public var imagePreviewArtifacts: [ToolArtifactState] {
        artifacts.filter(\.isImagePreview)
    }

    public var textPreviewArtifacts: [ToolArtifactState] {
        artifacts.filter(\.hasTextPreview)
    }

    public var documentPreviewArtifacts: [ToolArtifactState] {
        artifacts.filter(\.isDocumentPreview)
    }
}
