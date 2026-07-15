import AppKit
import ApplicationServices
import Foundation

@MainActor
enum QuillCodeDesktopAccessibilityInteractionVerifier {
    private static let composerInputIdentifier = "quillcode-composer-input"
    private static let composerSmokeText = "QuillCode new chat smoke"
    private static let modelPickerSearchIdentifier = "quillcode-model-picker-search"
    private static let modelPickerSearchSmokeText = "Prometheus"
    private static let prometheusOptionIdentifier = "quillcode-model-option-trustedrouter/fusion"
    private static let searchInputIdentifier = "quillcode-search-input"
    private static let searchSmokeText = "QuillCode search smoke"
    private static let settingsSurfaceContract = DismissibleSurfaceContract(
        contractID: "command.settings",
        name: "Settings",
        titleIdentifier: "quillcode-settings-title",
        requiredControlIdentifier: "quillcode-notifications-agent-runs",
        requiredControlDescription: "notifications control",
        closeIdentifier: "quillcode-settings-close"
    )
    private static let automationsSurfaceContract = DismissibleSurfaceContract(
        contractID: "command.toggle-automations",
        name: "Automations",
        titleIdentifier: "quillcode-automations-title",
        requiredControlIdentifier: "quillcode-automation-create",
        requiredControlDescription: "Create control",
        closeIdentifier: "quillcode-automations-close"
    )
    private static let extensionsSurfaceContract = DismissibleSurfaceContract(
        contractID: "command.toggle-extensions",
        name: "Extensions",
        titleIdentifier: "quillcode-extensions-title",
        requiredControlIdentifier: "quillcode-extensions-add",
        requiredControlDescription: "Add control",
        closeIdentifier: "quillcode-extensions-close"
    )
    private static let memoriesSurfaceContract = DismissibleSurfaceContract(
        contractID: "command.toggle-memories",
        name: "Memories",
        titleIdentifier: "quillcode-memories-title",
        requiredControlIdentifier: "quillcode-memory-add",
        requiredControlDescription: "Add control",
        closeIdentifier: "quillcode-memories-close"
    )
    private static let activitySurfaceContract = DismissibleSurfaceContract(
        contractID: "command.toggle-activity",
        name: "Activity",
        titleIdentifier: "quillcode-activity-title",
        requiredControlIdentifier: "quillcode-activity-task-summary",
        requiredControlDescription: "task summary",
        closeIdentifier: "quillcode-activity-close"
    )
    private static let reviewSurfaceContract = DismissibleSurfaceContract(
        contractID: "command.toggle-review-panel",
        name: "Review",
        titleIdentifier: "quillcode-review-title",
        requiredControlIdentifier: "quillcode-review-scope",
        requiredControlDescription: "scope control",
        closeIdentifier: "quillcode-review-close"
    )

    static func observeWorkspaceThreads(
        _ controller: QuillCodeDesktopController
    ) -> QuillCodeDesktopAccessibilityActivationState {
        .workspaceThreads(QuillCodeDesktopWorkspaceThreadActivationState(
            selectedThreadID: controller.model.root.selectedThreadID,
            threadIDs: Set(controller.model.root.threads.map(\.id))
        ))
    }

    static func newChatTransitionIssue(
        before: QuillCodeDesktopAccessibilityActivationState,
        after: QuillCodeDesktopAccessibilityActivationState
    ) -> String? {
        guard case .workspaceThreads(let baseline) = before,
              case .workspaceThreads(let current) = after
        else {
            return "command.new-chat did not report workspace thread state"
        }

        let addedThreadIDs = current.threadIDs.subtracting(baseline.threadIDs)
        let removedThreadIDs = baseline.threadIDs.subtracting(current.threadIDs)
        guard removedThreadIDs.isEmpty, addedThreadIDs.count == 1 else {
            return "command.new-chat must create exactly one chat without removing another"
        }
        guard current.selectedThreadID == addedThreadIDs.first else {
            return "command.new-chat did not select the one chat it created"
        }
        return nil
    }

    static func resetWorkspaceThreads(
        before: QuillCodeDesktopAccessibilityActivationState,
        after: QuillCodeDesktopAccessibilityActivationState,
        controller: QuillCodeDesktopController
    ) {
        guard case .workspaceThreads(let baseline) = before,
              case .workspaceThreads(let current) = after
        else { return }

        for threadID in current.threadIDs.subtracting(baseline.threadIDs) {
            _ = controller.model.deleteThread(threadID)
        }
        if let selectedThreadID = baseline.selectedThreadID,
           controller.model.root.threads.contains(where: { $0.id == selectedThreadID })
        {
            controller.model.selectThread(selectedThreadID, recordsNavigation: false)
        }
        controller.modelStateCoordinator.syncComposerDraft(from: controller.model, draft: &controller.draft)
        controller.refresh()
    }

    static func verifyNewChatComposerTextEntry(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyReversibleTextEntry(
            inputIdentifier: composerInputIdentifier,
            smokeText: composerSmokeText,
            successEvidence: "created exactly one selected chat and \(composerInputIdentifier) focused with reversible AXValue text entry",
            missingFocusIssue: "command.new-chat did not expose a focused \(composerInputIdentifier) field",
            rejectedValueIssue: "command.new-chat \(composerInputIdentifier) rejected AXValue",
            retainedValueIssue: "command.new-chat \(composerInputIdentifier) did not retain AXValue text entry",
            clearValueIssue: "command.new-chat \(composerInputIdentifier) could not restore its empty value",
            contentView: contentView
        )
    }

    static func verifySearchTextEntry(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyReversibleTextEntry(
            inputIdentifier: searchInputIdentifier,
            smokeText: searchSmokeText,
            successEvidence: "\(searchInputIdentifier) focused and accepted reversible AXValue text entry",
            missingFocusIssue: "command.search did not expose a focused \(searchInputIdentifier) field",
            rejectedValueIssue: "command.search \(searchInputIdentifier) rejected AXValue",
            retainedValueIssue: "command.search \(searchInputIdentifier) did not retain AXValue text entry",
            clearValueIssue: "command.search \(searchInputIdentifier) could not restore its empty value",
            contentView: contentView
        )
    }

    static func verifyModelPickerSearch(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyReversibleTextEntry(
            inputIdentifier: modelPickerSearchIdentifier,
            smokeText: modelPickerSearchSmokeText,
            successEvidence: "\(modelPickerSearchIdentifier) focused, accepted reversible AXValue text entry, and surfaced the Prometheus 1.0 model option",
            missingFocusIssue: "composer.model-picker did not expose a focused \(modelPickerSearchIdentifier) field",
            rejectedValueIssue: "composer.model-picker \(modelPickerSearchIdentifier) rejected AXValue",
            retainedValueIssue: "composer.model-picker \(modelPickerSearchIdentifier) did not retain AXValue text entry",
            clearValueIssue: "composer.model-picker \(modelPickerSearchIdentifier) could not restore its empty value",
            requiredElementIdentifier: prometheusOptionIdentifier,
            requiredElementLabelFragment: "Prometheus 1.0",
            missingRequiredElementIssue: "composer.model-picker search did not surface the Prometheus 1.0 model option",
            contentView: contentView
        )
    }

    static func verifySettingsDismissal(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyDismissibleSurface(settingsSurfaceContract, contentView: contentView)
    }

    static func verifyAutomationsDismissal(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyDismissibleSurface(automationsSurfaceContract, contentView: contentView)
    }

    static func verifyExtensionsDismissal(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyDismissibleSurface(extensionsSurfaceContract, contentView: contentView)
    }

    static func verifyMemoriesDismissal(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyDismissibleSurface(memoriesSurfaceContract, contentView: contentView)
    }

    static func verifyActivityDismissal(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        guard let constrainedComposer = await waitForInput(composerInputIdentifier, expectedValue: nil, in: contentView),
              let constrainedFrame = constrainedComposer.frame
        else {
            return .init(
                evidence: "Activity rendered without a measurable composer",
                validationIssue: "command.toggle-activity could not measure the composer while Activity was visible"
            )
        }

        let dismissal = await verifyDismissibleSurface(activitySurfaceContract, contentView: contentView)
        guard dismissal.validationIssue == nil else { return dismissal }
        guard let restoredComposer = await waitForInput(composerInputIdentifier, expectedValue: nil, in: contentView),
              let restoredFrame = restoredComposer.frame
        else {
            return .init(
                evidence: "Activity dismissed but the composer did not reappear",
                validationIssue: "command.toggle-activity did not restore the composer after dismissal"
            )
        }

        let restoredWidth = restoredFrame.width
        let constrainedWidth = constrainedFrame.width
        guard restoredWidth - constrainedWidth >= 240 else {
            return .init(
                evidence: "Activity dismissed but composer width changed from \(Int(constrainedWidth)) to only \(Int(restoredWidth)) points",
                validationIssue: "command.toggle-activity did not restore the horizontal workspace after dismissal"
            )
        }

        return .init(
            evidence: "\(dismissal.evidence) and restored composer width from \(Int(constrainedWidth)) to \(Int(restoredWidth)) points",
            validationIssue: nil
        )
    }

    static func verifyReviewDismissal(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyDismissibleSurface(reviewSurfaceContract, contentView: contentView)
    }

    private static func verifyReversibleTextEntry(
        inputIdentifier: String,
        smokeText: String,
        successEvidence: String,
        missingFocusIssue: String,
        rejectedValueIssue: String,
        retainedValueIssue: String,
        clearValueIssue: String,
        requiredElementIdentifier: String? = nil,
        requiredElementLabelFragment: String? = nil,
        missingRequiredElementIssue: String? = nil,
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        guard let initialInput = await waitForInput(
            inputIdentifier,
            expectedValue: nil,
            requiresFocus: true,
            in: contentView
        ) else {
            return .init(evidence: "\(inputIdentifier) did not become focused", validationIssue: missingFocusIssue)
        }

        let setError = QuillCodeDesktopAccessibilityTree.performSetValue(smokeText, on: initialInput)
        guard setError == .success else {
            return .init(
                evidence: "\(inputIdentifier) rejected AXValue text entry",
                validationIssue: "\(rejectedValueIssue) with \(setError)"
            )
        }
        guard await waitForInput(inputIdentifier, expectedValue: smokeText, in: contentView) != nil else {
            return .init(evidence: "\(inputIdentifier) AXValue did not update", validationIssue: retainedValueIssue)
        }
        let requiredElementIssue = await validateRequiredElement(
            identifier: requiredElementIdentifier,
            labelFragment: requiredElementLabelFragment,
            validationIssue: missingRequiredElementIssue,
            contentView: contentView
        )
        guard let updatedInput = input(inputIdentifier, in: contentView),
              QuillCodeDesktopAccessibilityTree.performSetValue("", on: updatedInput) == .success,
              await waitForInput(inputIdentifier, expectedValue: "", in: contentView) != nil
        else {
            return .init(evidence: "\(inputIdentifier) accepted text but did not clear", validationIssue: clearValueIssue)
        }
        if let requiredElementIssue {
            return .init(
                evidence: "\(inputIdentifier) accepted text but the required result did not appear",
                validationIssue: requiredElementIssue
            )
        }

        return .init(evidence: successEvidence, validationIssue: nil)
    }

    private static func validateRequiredElement(
        identifier: String?,
        labelFragment: String?,
        validationIssue: String?,
        contentView: NSView
    ) async -> String? {
        guard let identifier, let labelFragment, let validationIssue else { return nil }
        return await waitForElement(identifier, labelFragment: labelFragment, in: contentView) == nil
            ? validationIssue
            : nil
    }

    private static func verifyDismissibleSurface(
        _ contract: DismissibleSurfaceContract,
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        guard await waitForElement(contract.titleIdentifier, in: contentView) != nil else {
            return .init(
                evidence: "\(contract.name) title did not render",
                validationIssue: "\(contract.contractID) did not render \(contract.name)"
            )
        }
        guard await waitForElement(contract.requiredControlIdentifier, in: contentView) != nil else {
            return .init(
                evidence: "\(contract.name) rendered without its \(contract.requiredControlDescription)",
                validationIssue: "\(contract.contractID) did not expose its \(contract.requiredControlDescription)"
            )
        }
        guard let closeButton = await waitForElement(contract.closeIdentifier, in: contentView) else {
            return .init(
                evidence: "\(contract.name) rendered without an accessible close button",
                validationIssue: "\(contract.contractID) did not expose \(contract.closeIdentifier)"
            )
        }

        let pressError = QuillCodeDesktopAccessibilityTree.performPress(on: closeButton)
        guard pressError == .success else {
            return .init(
                evidence: "\(contract.closeIdentifier) rejected AXPress",
                validationIssue: "\(contract.contractID) could not dismiss through \(contract.closeIdentifier): \(pressError)"
            )
        }
        guard await waitForElementToDisappear(contract.titleIdentifier, in: contentView) else {
            return .init(
                evidence: "\(contract.closeIdentifier) accepted AXPress but \(contract.name) remained visible",
                validationIssue: "\(contract.contractID) close button did not dismiss \(contract.name)"
            )
        }

        return .init(
            evidence: "rendered \(contract.name) with its \(contract.requiredControlDescription) and dismissed through \(contract.closeIdentifier) with AXPress",
            validationIssue: nil
        )
    }

    private static func waitForElement(
        _ identifier: String,
        labelFragment: String? = nil,
        in contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityElementSnapshot? {
        for _ in 0..<20 {
            if let candidate = element(identifier, in: contentView) {
                let labelMatches = labelFragment.map { candidate.bestLabel.contains($0) } ?? true
                if labelMatches {
                    return candidate
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private static func waitForElementToDisappear(
        _ identifier: String,
        in contentView: NSView
    ) async -> Bool {
        for _ in 0..<20 {
            if element(identifier, in: contentView) == nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static func element(
        _ identifier: String,
        in contentView: NSView
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        QuillCodeDesktopAccessibilityTree(root: contentView).elements
            .first { $0.identifier == identifier }
    }

    private static func waitForInput(
        _ identifier: String,
        expectedValue: String?,
        requiresFocus: Bool = false,
        in contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityElementSnapshot? {
        for _ in 0..<20 {
            if let candidate = input(identifier, in: contentView),
               (!requiresFocus || candidate.isFocused),
               expectedValue == nil || candidate.value == expectedValue
            {
                return candidate
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private static func input(
        _ identifier: String,
        in contentView: NSView
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        QuillCodeDesktopAccessibilityTree(root: contentView).elements
            .filter { $0.identifier == identifier }
            .max { $0.frameArea < $1.frameArea }
    }

    private struct DismissibleSurfaceContract {
        let contractID: String
        let name: String
        let titleIdentifier: String
        let requiredControlIdentifier: String
        let requiredControlDescription: String
        let closeIdentifier: String
    }
}
