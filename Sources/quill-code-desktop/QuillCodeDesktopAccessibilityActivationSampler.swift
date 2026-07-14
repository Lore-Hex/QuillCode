import AppKit
import ApplicationServices
import Foundation
import QuillCodeApp

struct QuillCodeDesktopAccessibilityActivationCheck {
    var contractID: String
    var selectorKind: String
    var selector: String
    var resolvedIdentifier: String
    var role: String
    var label: String
    var activation: String
    var expectedOutcome: String
    var beforeValue: String
    var afterValue: String
    var axError: String
    var interactionEvidence: String
    var validationIssue: String?

    var ok: Bool {
        validationIssue == nil
    }

    var dictionary: [String: Any] {
        [
            "contractID": contractID,
            "selectorKind": selectorKind,
            "selector": selector,
            "resolvedIdentifier": resolvedIdentifier,
            "role": role,
            "label": label,
            "activation": activation,
            "expectedOutcome": expectedOutcome,
            "beforeValue": beforeValue,
            "afterValue": afterValue,
            "axError": axError,
            "interactionEvidence": interactionEvidence,
            "ok": ok,
            "validationIssue": validationIssue ?? ""
        ]
    }
}

struct QuillCodeDesktopAccessibilityActivationReport {
    var liveAccessibilityActivation: String
    var requiredContractIDs: [String]
    var activatedContractIDs: [String]
    var skippedContractIDs: [String]
    var checks: [QuillCodeDesktopAccessibilityActivationCheck]
    var validationIssues: [String]

    var ok: Bool {
        validationIssues.isEmpty
    }

    var dictionary: [String: Any] {
        [
            "ok": ok,
            "liveAccessibilityActivation": liveAccessibilityActivation,
            "requiredContractIDs": requiredContractIDs,
            "activatedContractIDs": activatedContractIDs,
            "skippedContractIDs": skippedContractIDs,
            "checkCount": checks.count,
            "checks": checks.map(\.dictionary),
            "validationIssues": validationIssues
        ]
    }
}

@MainActor
enum QuillCodeDesktopAccessibilityActivationSampler {
    private static let activationContracts: [QuillCodeDesktopAccessibilityActivationContract] = [
        .presentation(
            "composer.model-picker",
            expectedOutcome: "model picker opens, focuses search, and surfaces a catalog result",
            observe: { $0.isModelPickerPresented },
            resetToBaseline: { $1.isModelPickerPresented = $0 },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyModelPickerSearch
        ),
        QuillCodeDesktopAccessibilityActivationContract(
            contractID: "command.new-chat",
            phase: .workspaceReplacement,
            expectedOutcome: "creates and selects exactly one chat, then focuses its composer",
            observe: QuillCodeDesktopAccessibilityInteractionVerifier.observeWorkspaceThreads,
            reset: QuillCodeDesktopAccessibilityInteractionVerifier.resetWorkspaceThreads,
            validateTransition: QuillCodeDesktopAccessibilityInteractionVerifier.newChatTransitionIssue,
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyNewChatComposerTextEntry
        ),
        .presentation(
            "command.search",
            expectedOutcome: "search dialog opens, focuses its field, and accepts text",
            observe: { $0.isSearchPresented },
            resetToBaseline: { $1.isSearchPresented = $0 },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifySearchTextEntry
        ),
        .presentation(
            "command.settings",
            expectedOutcome: "settings dialog renders its primary controls and dismisses through Close",
            observe: { $0.isSettingsPresented },
            resetToBaseline: { $1.isSettingsPresented = $0 },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifySettingsDismissal
        ),
        .presentation(
            "command.toggle-automations",
            expectedOutcome: "Automations renders its Create control and dismisses through Close",
            observe: { $0.surface.automations.isVisible },
            resetToBaseline: { baseline, controller in
                if controller.surface.automations.isVisible != baseline {
                    controller.toggleAutomations()
                }
            },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyAutomationsDismissal
        ),
        .presentation(
            "command.toggle-extensions",
            expectedOutcome: "Extensions renders its Add control and dismisses through Close",
            observe: { $0.surface.extensions.isVisible },
            resetToBaseline: { baseline, controller in
                if controller.surface.extensions.isVisible != baseline {
                    controller.toggleExtensions()
                }
            },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyExtensionsDismissal
        ),
        .presentation(
            "command.toggle-memories",
            expectedOutcome: "Memories renders its Add control and dismisses through Close",
            observe: { $0.surface.memories.isVisible },
            resetToBaseline: { baseline, controller in
                if controller.surface.memories.isVisible != baseline {
                    controller.toggleMemories()
                }
            },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyMemoriesDismissal
        )
    ]

    static let requiredActivationContractIDs = Set(activationContracts.map(\.contractID))

    static func validatedReport(
        contentView: NSView,
        controller: QuillCodeDesktopController,
        nativeHitTargets: QuillCodeNativeHitTargetAuditReport
    ) async throws -> QuillCodeDesktopAccessibilityActivationReport {
        let report = await sample(
            contentView: contentView,
            controller: controller,
            nativeHitTargets: nativeHitTargets
        )
        guard report.ok else {
            throw QuillCodeDesktopSmokeFailure.nativeAccessibilityActivationFailed(report.validationIssues)
        }
        return report
    }

    private static func sample(
        contentView: NSView,
        controller: QuillCodeDesktopController,
        nativeHitTargets: QuillCodeNativeHitTargetAuditReport
    ) async -> QuillCodeDesktopAccessibilityActivationReport {
        let probesByID = Dictionary(uniqueKeysWithValues: nativeHitTargets.clickProbes.map { ($0.contractID, $0) })
        var checks: [QuillCodeDesktopAccessibilityActivationCheck] = []
        var validationIssues: [String] = []

        for contract in activationContracts.sorted(by: activationOrder) {
            guard let probe = probesByID[contract.contractID] else {
                validationIssues.append("\(contract.contractID) has no native click probe to activate")
                continue
            }
            guard let element = await resolveCurrentElement(probe, contentView: contentView) else {
                validationIssues.append("\(contract.contractID) did not resolve to an AXPress target")
                continue
            }

            let result = await activate(
                contract: contract,
                probe: probe,
                element: element,
                contentView: contentView,
                controller: controller
            )
            checks.append(result)
            if let issue = result.validationIssue {
                validationIssues.append(issue)
            }
        }

        let activatedIDs = checks.filter(\.ok).map(\.contractID).sorted()
        let skippedIDs = Set(nativeHitTargets.clickProbes.map(\.contractID))
            .subtracting(Set(checks.map(\.contractID)))
            .sorted()

        return QuillCodeDesktopAccessibilityActivationReport(
            liveAccessibilityActivation: "ax-press-sampled",
            requiredContractIDs: requiredActivationContractIDs.sorted(),
            activatedContractIDs: activatedIDs,
            skippedContractIDs: skippedIDs,
            checks: checks.sorted { $0.contractID < $1.contractID },
            validationIssues: validationIssues.sorted()
        )
    }

    private static func activationOrder(
        _ lhs: QuillCodeDesktopAccessibilityActivationContract,
        _ rhs: QuillCodeDesktopAccessibilityActivationContract
    ) -> Bool {
        if lhs.phase != rhs.phase {
            return lhs.phase < rhs.phase
        }
        return lhs.contractID < rhs.contractID
    }

    private static func activate(
        contract: QuillCodeDesktopAccessibilityActivationContract,
        probe: QuillCodeNativeHitTargetProbe,
        element: QuillCodeDesktopAccessibilityElementSnapshot,
        contentView: NSView,
        controller: QuillCodeDesktopController
    ) async -> QuillCodeDesktopAccessibilityActivationCheck {
        let baseline = contract.observe(controller)
        let axError = QuillCodeDesktopAccessibilityTree.performPress(on: element)
        _ = await waitForStateChange(contract: contract, baseline: baseline, controller: controller)
        let after = contract.observe(controller)
        let activationIssue = validationIssue(
            contractID: contract.contractID,
            axError: axError,
            before: baseline,
            after: after
        )
        let transitionIssue = activationIssue == nil
            ? contract.validateTransition?(baseline, after)
            : nil
        let contractIssue = activationIssue ?? transitionIssue
        let verification: QuillCodeDesktopAccessibilityActivationVerification
        if let contractIssue {
            verification = QuillCodeDesktopAccessibilityActivationVerification(
                evidence: "deeper interaction verification skipped: \(contractIssue)",
                validationIssue: nil
            )
        } else if let verify = contract.verify {
            verification = await verify(contentView)
        } else {
            verification = .stateChange
        }
        contract.reset(baseline, after, controller)
        let didRestoreBaseline = await waitForObservedState(
            contract: contract,
            expected: baseline,
            controller: controller
        )
        // State changes can replace SwiftUI's backing AX elements. Let the accessibility
        // hierarchy settle before the next contract resolves a fresh element snapshot.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let resetIssue = didRestoreBaseline
            ? nil
            : "\(contract.contractID) could not restore its baseline state after AXPress"

        return QuillCodeDesktopAccessibilityActivationCheck(
            contractID: probe.contractID,
            selectorKind: probe.selectorKind.rawValue,
            selector: probe.selector,
            resolvedIdentifier: element.identifier,
            role: element.role,
            label: element.bestLabel,
            activation: "AXPress",
            expectedOutcome: contract.expectedOutcome,
            beforeValue: baseline.description,
            afterValue: after.description,
            axError: axErrorDescription(axError),
            interactionEvidence: verification.evidence,
            validationIssue: contractIssue ?? verification.validationIssue ?? resetIssue
        )
    }

    private static func resolveCurrentElement(
        _ probe: QuillCodeNativeHitTargetProbe,
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityElementSnapshot? {
        for _ in 0..<20 {
            let elements = QuillCodeDesktopAccessibilityTree(root: contentView).elements
            if let element = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
                probe,
                in: elements
            ) {
                return element
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private static func axErrorDescription(_ error: AXError) -> String {
        error == .success ? "success" : String(describing: error)
    }

    private static func waitForStateChange(
        contract: QuillCodeDesktopAccessibilityActivationContract,
        baseline: QuillCodeDesktopAccessibilityActivationState,
        controller: QuillCodeDesktopController
    ) async -> Bool {
        for _ in 0..<10 {
            if contract.observe(controller) != baseline {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static func waitForObservedState(
        contract: QuillCodeDesktopAccessibilityActivationContract,
        expected: QuillCodeDesktopAccessibilityActivationState,
        controller: QuillCodeDesktopController
    ) async -> Bool {
        for _ in 0..<20 {
            if contract.observe(controller) == expected {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static func validationIssue(
        contractID: String,
        axError: AXError,
        before: QuillCodeDesktopAccessibilityActivationState,
        after: QuillCodeDesktopAccessibilityActivationState
    ) -> String? {
        if axError != .success {
            return "\(contractID) AXPress failed with \(axError)"
        }
        if before == after {
            return "\(contractID) AXPress did not change expected state \(before)"
        }
        return nil
    }
}
