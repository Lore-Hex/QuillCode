import AppKit
import ApplicationServices
import Foundation
import QuillCodeApp

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
        requiredControlIdentifier: "quillcode-settings-api-base-url",
        requiredControlDescription: "Account API field",
        closeIdentifier: "quillcode-settings-close"
    )
    private static let developerKeySettingsSurfaceContract = DismissibleSurfaceContract(
        contractID: "onboarding.developer-key",
        name: "Developer override settings",
        titleIdentifier: "quillcode-settings-title",
        requiredControlIdentifier: "quillcode-settings-api-key",
        requiredControlDescription: "developer key field",
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
            selectedProjectID: controller.model.root.selectedProjectID,
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
        _ = controller.model.selectWorkspaceLocation(
            WorkspaceNavigationLocation(
                threadID: baseline.selectedThreadID,
                projectID: baseline.selectedProjectID
            ),
            recordsNavigation: false
        )
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
        let verification = await verifyDismissibleSurface(
            settingsSurfaceContract,
            contentView: contentView,
            validateBeforeDismiss: {
                guard let generalButton = await waitForElement(
                    "quillcode-settings-section-general",
                    in: contentView
                ) else {
                    return .init(
                        evidence: "Settings rendered without its General section",
                        validationIssue: "command.settings did not expose General section navigation"
                    )
                }
                guard QuillCodeDesktopAccessibilityTree.performPress(on: generalButton) == .success,
                      await waitForElement("quillcode-notifications-agent-runs", in: contentView) != nil
                else {
                    return .init(
                        evidence: "General section did not render its notifications control",
                        validationIssue: "command.settings could not open its General section"
                    )
                }
                guard let accountButton = await waitForElement(
                    "quillcode-settings-section-account",
                    in: contentView
                ),
                    QuillCodeDesktopAccessibilityTree.performPress(on: accountButton) == .success,
                    await waitForElement("quillcode-settings-api-base-url", in: contentView) != nil
                else {
                    return .init(
                        evidence: "Settings could not return from General to Account",
                        validationIssue: "command.settings section navigation did not restore Account"
                    )
                }
                return nil
            }
        )
        guard verification.validationIssue == nil else { return verification }
        return .init(
            evidence: verification.evidence
                + "; switched to General, rendered its notifications control, and returned to Account",
            validationIssue: nil
        )
    }

    static func verifyDeveloperKeySettingsDismissal(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        await verifyDismissibleSurface(developerKeySettingsSurfaceContract, contentView: contentView)
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
        var constrainedFrame: CGRect?
        let dismissal = await verifyDismissibleSurface(
            activitySurfaceContract,
            contentView: contentView,
            validateBeforeDismiss: {
                guard let frame = await waitForStableInputFrame(composerInputIdentifier, in: contentView) else {
                    return .init(
                        evidence: "Activity rendered without a stable, measurable composer",
                        validationIssue: "command.toggle-activity could not measure the composer while Activity was visible"
                    )
                }
                constrainedFrame = frame
                return nil
            }
        )
        guard dismissal.validationIssue == nil else { return dismissal }
        guard let constrainedFrame else {
            return .init(
                evidence: "Activity dismissed before the composer measurement completed",
                validationIssue: "command.toggle-activity did not complete its composer measurement"
            )
        }

        let minimumRestoredWidth = constrainedFrame.width + 240
        guard let restoredFrame = await waitForStableInputFrame(
            composerInputIdentifier,
            minimumWidth: minimumRestoredWidth,
            in: contentView
        ) else {
            return .init(
                evidence: "Activity dismissed but the composer did not stabilize at least \(Int(minimumRestoredWidth)) points wide",
                validationIssue: "command.toggle-activity did not restore the horizontal workspace after dismissal"
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
        contentView: NSView,
        validateBeforeDismiss: (() async -> QuillCodeDesktopAccessibilityActivationVerification?)? = nil
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        let presentation = await waitForDismissibleSurface(contract, in: contentView)
        var readinessSampleCount = presentation.sampleCount
        guard presentation.isComplete,
              var closeButton = presentation.elementsByIdentifier[contract.closeIdentifier]
        else {
            return dismissibleSurfaceReadinessFailure(contract, sample: presentation)
        }

        if let validateBeforeDismiss,
           let validation = await validateBeforeDismiss()
        {
            return validation
        }
        if validateBeforeDismiss != nil {
            let refreshedPresentation = await waitForDismissibleSurface(contract, in: contentView)
            readinessSampleCount += refreshedPresentation.sampleCount
            guard refreshedPresentation.isComplete,
                  let refreshedCloseButton = refreshedPresentation.elementsByIdentifier[contract.closeIdentifier]
            else {
                return .init(
                    evidence: "\(contract.name) changed while waiting for layout; missing "
                        + refreshedPresentation.missingIdentifiers.sorted().joined(separator: ", "),
                    validationIssue: "\(contract.contractID) did not remain fully accessible before dismissal"
                )
            }
            closeButton = refreshedCloseButton
        }

        let pressError = QuillCodeDesktopAccessibilityTree.performPress(on: closeButton)
        guard pressError == .success else {
            return .init(
                evidence: "\(contract.closeIdentifier) rejected AXPress",
                validationIssue: "\(contract.contractID) could not dismiss through \(contract.closeIdentifier): \(pressError)"
            )
        }
        guard await waitForElementToDisappear(
            contract.titleIdentifier,
            maximumAttempts: 100,
            in: contentView
        ) else {
            return .init(
                evidence: "\(contract.closeIdentifier) accepted AXPress but \(contract.name) remained visible",
                validationIssue: "\(contract.contractID) close button did not dismiss \(contract.name)"
            )
        }

        return .init(
            evidence: "rendered \(contract.name) with its \(contract.requiredControlDescription) "
                + "after \(targetedSampleDescription(readinessSampleCount)) and dismissed through "
                + "\(contract.closeIdentifier) with AXPress",
            validationIssue: nil
        )
    }

    private static func waitForDismissibleSurface(
        _ contract: DismissibleSurfaceContract,
        in contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityRequiredElementSample {
        await QuillCodeDesktopAccessibilityElementSetSampler.waitForRequiredElements(
            [
                contract.titleIdentifier,
                contract.requiredControlIdentifier,
                contract.closeIdentifier
            ],
            elements: {
                QuillCodeDesktopAccessibilityTree(
                    root: contentView,
                    matchingIdentifiers: [
                        contract.titleIdentifier,
                        contract.requiredControlIdentifier,
                        contract.closeIdentifier
                    ]
                ).elements
            }
        )
    }

    private static func dismissibleSurfaceReadinessFailure(
        _ contract: DismissibleSurfaceContract,
        sample: QuillCodeDesktopAccessibilityRequiredElementSample
    ) -> QuillCodeDesktopAccessibilityActivationVerification {
        let missing = sample.missingIdentifiers.sorted().joined(separator: ", ")
        let sampleEvidence = "after \(targetedSampleDescription(sample.sampleCount)); missing \(missing)"
        if sample.missingIdentifiers.contains(contract.titleIdentifier) {
            return .init(
                evidence: "\(contract.name) title did not render \(sampleEvidence)",
                validationIssue: "\(contract.contractID) did not render \(contract.name); \(sampleEvidence)"
            )
        }
        if sample.missingIdentifiers.contains(contract.requiredControlIdentifier) {
            return .init(
                evidence: "\(contract.name) rendered without its "
                    + "\(contract.requiredControlDescription) \(sampleEvidence)",
                validationIssue: "\(contract.contractID) did not expose its "
                    + "\(contract.requiredControlDescription); \(sampleEvidence)"
            )
        }
        return .init(
            evidence: "\(contract.name) rendered without an accessible close button \(sampleEvidence)",
            validationIssue: "\(contract.contractID) did not expose \(contract.closeIdentifier); \(sampleEvidence)"
        )
    }

    private static func targetedSampleDescription(_ count: Int) -> String {
        "\(count) targeted AX \(count == 1 ? "sample" : "samples")"
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
        maximumAttempts: Int = 20,
        in contentView: NSView
    ) async -> Bool {
        for _ in 0..<max(1, maximumAttempts) {
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
        QuillCodeDesktopAccessibilityTree(
            root: contentView,
            matchingIdentifiers: [identifier]
        ).elements
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

    private static func waitForStableInputFrame(
        _ identifier: String,
        minimumWidth: CGFloat? = nil,
        in contentView: NSView
    ) async -> CGRect? {
        await QuillCodeDesktopAccessibilityLayoutSampler.waitForStableFrame(
            accepts: { frame in
                minimumWidth.map { frame.width >= $0 } ?? true
            },
            sample: {
                input(identifier, in: contentView)?.frame
            }
        )
    }

    private static func input(
        _ identifier: String,
        in contentView: NSView
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        QuillCodeDesktopAccessibilityTree(
            root: contentView,
            matchingIdentifiers: [identifier]
        ).elements
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
