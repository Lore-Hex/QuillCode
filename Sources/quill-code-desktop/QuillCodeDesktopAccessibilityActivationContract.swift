import AppKit
import Foundation

struct QuillCodeDesktopWorkspaceThreadActivationState: Equatable {
    var selectedThreadID: UUID?
    var threadIDs: Set<UUID>
}

enum QuillCodeDesktopAccessibilityActivationState: Equatable, CustomStringConvertible {
    case flag(Bool)
    case workspaceThreads(QuillCodeDesktopWorkspaceThreadActivationState)

    var description: String {
        switch self {
        case .flag(let value):
            return value.description
        case .workspaceThreads(let state):
            return "selected=\(state.selectedThreadID?.uuidString ?? "none");count=\(state.threadIDs.count)"
        }
    }
}

struct QuillCodeDesktopAccessibilityActivationVerification {
    var evidence: String
    var validationIssue: String?

    static let stateChange = QuillCodeDesktopAccessibilityActivationVerification(
        evidence: "AXPress changed observable controller state",
        validationIssue: nil
    )
}

enum QuillCodeDesktopAccessibilityActivationPhase: Int, Comparable {
    case transientSurface
    case workspaceReplacement

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct QuillCodeDesktopAccessibilityActivationContract {
    typealias Observe = @MainActor (QuillCodeDesktopController) -> QuillCodeDesktopAccessibilityActivationState
    typealias Reset = @MainActor (
        QuillCodeDesktopAccessibilityActivationState,
        QuillCodeDesktopAccessibilityActivationState,
        QuillCodeDesktopController
    ) -> Void
    typealias ValidateTransition = @MainActor (
        QuillCodeDesktopAccessibilityActivationState,
        QuillCodeDesktopAccessibilityActivationState
    ) -> String?
    typealias Verify = @MainActor (NSView) async -> QuillCodeDesktopAccessibilityActivationVerification

    var contractID: String
    var phase: QuillCodeDesktopAccessibilityActivationPhase
    var expectedOutcome: String
    var observe: Observe
    var reset: Reset
    var validateTransition: ValidateTransition?
    var verify: Verify?

    static func presentation(
        _ contractID: String,
        expectedOutcome: String,
        observe: @escaping @MainActor (QuillCodeDesktopController) -> Bool,
        resetToBaseline: @escaping @MainActor (Bool, QuillCodeDesktopController) -> Void,
        verify: Verify? = nil
    ) -> Self {
        Self(
            contractID: contractID,
            phase: .transientSurface,
            expectedOutcome: expectedOutcome,
            observe: { .flag(observe($0)) },
            reset: { before, after, controller in
                guard case .flag(let baseline) = before,
                      case .flag(let current) = after,
                      baseline != current
                else { return }
                resetToBaseline(baseline, controller)
            },
            validateTransition: nil,
            verify: verify
        )
    }

    static func toggle(
        _ contractID: String,
        expectedOutcome: String,
        observe: @escaping @MainActor (QuillCodeDesktopController) -> Bool,
        resetWith toggle: @escaping @MainActor (QuillCodeDesktopController) -> Void
    ) -> Self {
        Self(
            contractID: contractID,
            phase: .transientSurface,
            expectedOutcome: expectedOutcome,
            observe: { .flag(observe($0)) },
            reset: { before, after, controller in
                guard before != after else { return }
                toggle(controller)
            },
            validateTransition: nil,
            verify: nil
        )
    }
}
