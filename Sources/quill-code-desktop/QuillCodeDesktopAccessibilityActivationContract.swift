import AppKit
import Foundation

struct QuillCodeDesktopWorkspaceThreadActivationState: Equatable {
    var selectedThreadID: UUID?
    var selectedProjectID: UUID? = nil
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
            return "selected=\(state.selectedThreadID?.uuidString ?? "none");"
                + "project=\(state.selectedProjectID?.uuidString ?? "none");"
                + "count=\(state.threadIDs.count)"
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
    case initialSurface
    case transientSurface
    case workspaceReplacement

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct QuillCodeDesktopAccessibilityActivationContract {
    typealias Prepare = @MainActor (QuillCodeDesktopController) -> Void
    typealias IsApplicable = @MainActor (QuillCodeDesktopController) -> Bool
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
    var isApplicable: IsApplicable = { _ in true }
    var prepare: Prepare? = nil
    var observe: Observe
    var reset: Reset
    var validateTransition: ValidateTransition?
    var verify: Verify?

    static func presentation(
        _ contractID: String,
        phase: QuillCodeDesktopAccessibilityActivationPhase = .transientSurface,
        expectedOutcome: String,
        isApplicable: @escaping IsApplicable = { _ in true },
        observe: @escaping @MainActor (QuillCodeDesktopController) -> Bool,
        resetToBaseline: @escaping @MainActor (Bool, QuillCodeDesktopController) -> Void,
        verify: Verify? = nil
    ) -> Self {
        Self(
            contractID: contractID,
            phase: phase,
            expectedOutcome: expectedOutcome,
            isApplicable: isApplicable,
            prepare: { controller in
                if observe(controller) {
                    resetToBaseline(false, controller)
                }
            },
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
            prepare: nil,
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
