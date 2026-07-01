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
    static let requiredActivationContractIDs: Set<String> = [
        "command.settings",
        "command.toggle-automations",
        "command.toggle-extensions"
    ]

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

        for contractID in requiredActivationContractIDs.sorted() {
            guard let probe = probesByID[contractID] else {
                validationIssues.append("\(contractID) has no native click probe to activate")
                continue
            }
            guard let element = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
                probe,
                in: elements
            ) else {
                validationIssues.append("\(contractID) did not resolve to an AXPress target")
                continue
            }

            let result = await activate(probe: probe, element: element, controller: controller)
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
        probe: QuillCodeNativeHitTargetProbe,
        element: QuillCodeDesktopAccessibilityElementSnapshot,
        controller: QuillCodeDesktopController
    ) async -> QuillCodeDesktopAccessibilityActivationCheck {
        let baseline = observedValue(for: probe.contractID, controller: controller)
        let expectedOutcome = expectedOutcomeDescription(for: probe.contractID)
        let axError = QuillCodeDesktopAccessibilityTree.performPress(on: element)
        _ = await waitForStateChange(
            contractID: probe.contractID,
            baseline: baseline,
            controller: controller
        )
        let after = observedValue(for: probe.contractID, controller: controller)
        let issue = validationIssue(
            contractID: probe.contractID,
            axError: axError,
            before: baseline,
            after: after
        )
        resetStateChangedByActivation(
            contractID: probe.contractID,
            before: baseline,
            after: after,
            controller: controller
        )

        return QuillCodeDesktopAccessibilityActivationCheck(
            contractID: probe.contractID,
            selectorKind: probe.selectorKind.rawValue,
            selector: probe.selector,
            resolvedIdentifier: element.identifier,
            role: element.role,
            label: element.bestLabel,
            activation: "AXPress",
            expectedOutcome: expectedOutcome,
            beforeValue: baseline,
            afterValue: after,
            axError: axErrorDescription(axError),
            validationIssue: issue
        )
    }

    private static func axErrorDescription(_ error: AXError) -> String {
        error == .success ? "success" : String(describing: error)
    }

    private static func observedValue(
        for contractID: String,
        controller: QuillCodeDesktopController
    ) -> String {
        switch contractID {
        case "command.settings":
            return controller.isSettingsPresented.description
        case "command.toggle-automations":
            return controller.surface.automations.isVisible.description
        case "command.toggle-extensions":
            return controller.surface.extensions.isVisible.description
        default:
            return ""
        }
    }

    private static func expectedOutcomeDescription(for contractID: String) -> String {
        switch contractID {
        case "command.settings":
            return "settings sheet becomes presented"
        case "command.toggle-automations":
            return "automations pane visibility toggles"
        case "command.toggle-extensions":
            return "extensions pane visibility toggles"
        default:
            return "observable controller state changes"
        }
    }

    private static func waitForStateChange(
        contractID: String,
        baseline: String,
        controller: QuillCodeDesktopController
    ) async -> Bool {
        for _ in 0..<10 {
            if observedValue(for: contractID, controller: controller) != baseline {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static func validationIssue(
        contractID: String,
        axError: AXError,
        before: String,
        after: String
    ) -> String? {
        if axError != .success {
            return "\(contractID) AXPress failed with \(axError)"
        }
        if before == after {
            return "\(contractID) AXPress did not change expected state \(before)"
        }
        return nil
    }

    private static func resetStateChangedByActivation(
        contractID: String,
        before: String,
        after: String,
        controller: QuillCodeDesktopController
    ) {
        guard before != after else { return }
        switch contractID {
        case "command.settings":
            controller.isSettingsPresented = boolState(from: before)
        case "command.toggle-automations":
            controller.toggleAutomations()
        case "command.toggle-extensions":
            controller.toggleExtensions()
        default:
            break
        }
    }

    private static func boolState(from value: String) -> Bool {
        value == true.description
    }
}
