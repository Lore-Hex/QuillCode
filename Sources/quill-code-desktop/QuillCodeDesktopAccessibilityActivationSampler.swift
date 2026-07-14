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

private struct QuillCodeDesktopAccessibilityActivationVerification {
    var evidence: String
    var validationIssue: String?

    static let stateChange = QuillCodeDesktopAccessibilityActivationVerification(
        evidence: "AXPress changed observable controller state",
        validationIssue: nil
    )
}

private struct QuillCodeDesktopAccessibilityActivationContract {
    typealias Observe = @MainActor (QuillCodeDesktopController) -> Bool
    typealias Reset = @MainActor (Bool, Bool, QuillCodeDesktopController) -> Void
    typealias Verify = @MainActor (NSView) async -> QuillCodeDesktopAccessibilityActivationVerification

    var contractID: String
    var expectedOutcome: String
    var observe: Observe
    var reset: Reset
    var verify: Verify?

    static func presentation(
        _ contractID: String,
        expectedOutcome: String,
        observe: @escaping Observe,
        resetToBaseline: @escaping @MainActor (Bool, QuillCodeDesktopController) -> Void,
        verify: Verify? = nil
    ) -> Self {
        Self(
            contractID: contractID,
            expectedOutcome: expectedOutcome,
            observe: observe,
            reset: { before, after, controller in
                guard before != after else { return }
                resetToBaseline(before, controller)
            },
            verify: verify
        )
    }

    static func toggle(
        _ contractID: String,
        expectedOutcome: String,
        observe: @escaping Observe,
        resetWith toggle: @escaping @MainActor (QuillCodeDesktopController) -> Void
    ) -> Self {
        Self(
            contractID: contractID,
            expectedOutcome: expectedOutcome,
            observe: observe,
            reset: { before, after, controller in
                guard before != after else { return }
                toggle(controller)
            },
            verify: nil
        )
    }
}

@MainActor
enum QuillCodeDesktopAccessibilityActivationSampler {
    private static let searchInputIdentifier = "quillcode-search-input"
    private static let searchSmokeText = "QuillCode search smoke"

    private static let activationContracts: [QuillCodeDesktopAccessibilityActivationContract] = [
        .presentation(
            "command.search",
            expectedOutcome: "search dialog opens, focuses its field, and accepts text",
            observe: { $0.isSearchPresented },
            resetToBaseline: { $1.isSearchPresented = $0 },
            verify: verifySearchTextEntry
        ),
        .presentation(
            "command.settings",
            expectedOutcome: "settings sheet becomes presented",
            observe: { $0.isSettingsPresented },
            resetToBaseline: { $1.isSettingsPresented = $0 }
        ),
        .toggle(
            "command.toggle-automations",
            expectedOutcome: "automations pane visibility toggles",
            observe: { $0.surface.automations.isVisible },
            resetWith: { $0.toggleAutomations() }
        ),
        .toggle(
            "command.toggle-extensions",
            expectedOutcome: "extensions pane visibility toggles",
            observe: { $0.surface.extensions.isVisible },
            resetWith: { $0.toggleExtensions() }
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
        let elements = QuillCodeDesktopAccessibilityTree(root: contentView).elements
        let probesByID = Dictionary(uniqueKeysWithValues: nativeHitTargets.clickProbes.map { ($0.contractID, $0) })
        var checks: [QuillCodeDesktopAccessibilityActivationCheck] = []
        var validationIssues: [String] = []

        for contract in activationContracts.sorted(by: { $0.contractID < $1.contractID }) {
            guard let probe = probesByID[contract.contractID] else {
                validationIssues.append("\(contract.contractID) has no native click probe to activate")
                continue
            }
            guard let element = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
                probe,
                in: elements
            ) else {
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
        let verification: QuillCodeDesktopAccessibilityActivationVerification
        if let activationIssue {
            verification = QuillCodeDesktopAccessibilityActivationVerification(
                evidence: "deeper interaction verification skipped after failed AXPress: \(activationIssue)",
                validationIssue: nil
            )
        } else if let verify = contract.verify {
            verification = await verify(contentView)
        } else {
            verification = .stateChange
        }
        contract.reset(baseline, after, controller)
        await Task.yield()

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
            validationIssue: activationIssue ?? verification.validationIssue
        )
    }

    private static func axErrorDescription(_ error: AXError) -> String {
        error == .success ? "success" : String(describing: error)
    }

    private static func waitForStateChange(
        contract: QuillCodeDesktopAccessibilityActivationContract,
        baseline: Bool,
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

    private static func validationIssue(
        contractID: String,
        axError: AXError,
        before: Bool,
        after: Bool
    ) -> String? {
        if axError != .success {
            return "\(contractID) AXPress failed with \(axError)"
        }
        if before == after {
            return "\(contractID) AXPress did not change expected state \(before)"
        }
        return nil
    }

    private static func verifySearchTextEntry(
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityActivationVerification {
        guard let initialSearchInput = await waitForSearchInput(in: contentView) else {
            return QuillCodeDesktopAccessibilityActivationVerification(
                evidence: "search input did not become focused",
                validationIssue: "command.search did not expose a focused \(searchInputIdentifier) field"
            )
        }

        let setError = QuillCodeDesktopAccessibilityTree.performSetValue(searchSmokeText, on: initialSearchInput)
        guard setError == .success else {
            return QuillCodeDesktopAccessibilityActivationVerification(
                evidence: "search input rejected AXValue text entry",
                validationIssue: "command.search \(searchInputIdentifier) rejected AXValue with \(setError)"
            )
        }

        guard await waitForSearchValue(searchSmokeText, in: contentView) else {
            return QuillCodeDesktopAccessibilityActivationVerification(
                evidence: "search input AXValue did not update",
                validationIssue: "command.search \(searchInputIdentifier) did not retain AXValue text entry"
            )
        }

        guard let updatedInput = searchInput(in: contentView),
              QuillCodeDesktopAccessibilityTree.performSetValue("", on: updatedInput) == .success,
              await waitForSearchValue("", in: contentView)
        else {
            return QuillCodeDesktopAccessibilityActivationVerification(
                evidence: "search input accepted text but did not clear",
                validationIssue: "command.search \(searchInputIdentifier) could not restore its empty value"
            )
        }

        return QuillCodeDesktopAccessibilityActivationVerification(
            evidence: "\(searchInputIdentifier) focused and accepted reversible AXValue text entry",
            validationIssue: nil
        )
    }

    private static func waitForSearchInput(
        in contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityElementSnapshot? {
        for _ in 0..<20 {
            if let input = searchInput(in: contentView), input.isFocused {
                return input
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private static func waitForSearchValue(
        _ expectedValue: String,
        in contentView: NSView
    ) async -> Bool {
        for _ in 0..<20 {
            if searchInput(in: contentView)?.value == expectedValue {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static func searchInput(
        in contentView: NSView
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        QuillCodeDesktopAccessibilityTree(root: contentView).elements
            .filter { $0.identifier == searchInputIdentifier }
            .max { $0.frameArea < $1.frameArea }
    }
}
