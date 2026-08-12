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
    var baselineResidentMemoryBytes: Int64
    var presentedResidentMemoryBytes: Int64
    var presentedResidentMemoryGrowthBytes: Int64
    var baselineThreadCount: Int
    var presentedThreadCount: Int
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
            "baselineResidentMemoryBytes": baselineResidentMemoryBytes,
            "presentedResidentMemoryBytes": presentedResidentMemoryBytes,
            "presentedResidentMemoryGrowthBytes": presentedResidentMemoryGrowthBytes,
            "baselineThreadCount": baselineThreadCount,
            "presentedThreadCount": presentedThreadCount,
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

    private var peakPresentedMemoryCheck: QuillCodeDesktopAccessibilityActivationCheck? {
        checks.max { lhs, rhs in
            lhs.presentedResidentMemoryBytes < rhs.presentedResidentMemoryBytes
        }
    }

    private var maximumPresentedResidentMemoryGrowthBytes: Int64 {
        checks.map(\.presentedResidentMemoryGrowthBytes).max() ?? 0
    }

    private var peakPresentedThreadCount: Int {
        checks.map(\.presentedThreadCount).max() ?? 0
    }

    var dictionary: [String: Any] {
        [
            "ok": ok,
            "liveAccessibilityActivation": liveAccessibilityActivation,
            "requiredContractIDs": requiredContractIDs,
            "activatedContractIDs": activatedContractIDs,
            "skippedContractIDs": skippedContractIDs,
            "checkCount": checks.count,
            "resourceMeasurement": QuillCodeDesktopPerformanceSnapshot.memoryMeasurement,
            "peakPresentedContractID": peakPresentedMemoryCheck?.contractID ?? "",
            "peakPresentedResidentMemoryBytes": peakPresentedMemoryCheck?.presentedResidentMemoryBytes ?? 0,
            "maximumPresentedResidentMemoryGrowthBytes": maximumPresentedResidentMemoryGrowthBytes,
            "peakPresentedThreadCount": peakPresentedThreadCount,
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
            "onboarding.developer-key",
            phase: .initialSurface,
            expectedOutcome: "developer-key onboarding opens Developer override settings and dismisses through Close",
            isApplicable: { !$0.model.root.trustedRouterAPIKeyConfigured },
            observe: { $0.isSettingsPresented },
            resetToBaseline: { $1.isSettingsPresented = $0 },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyDeveloperKeySettingsDismissal
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
        ),
        .presentation(
            "command.toggle-activity",
            expectedOutcome: "Activity renders its task summary, dismisses through Close, and restores workspace width",
            observe: { $0.surface.activity.isVisible },
            resetToBaseline: { baseline, controller in
                if controller.surface.activity.isVisible != baseline {
                    controller.toggleActivity()
                }
            },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyActivityDismissal
        ),
        .presentation(
            "command.toggle-review-panel",
            expectedOutcome: "Review renders its scope control and dismisses through Close",
            observe: { $0.surface.review.isVisible },
            resetToBaseline: { baseline, controller in
                if controller.surface.review.isVisible != baseline {
                    controller.runCommand(commandID: "toggle-review-panel")
                }
            },
            verify: QuillCodeDesktopAccessibilityInteractionVerifier.verifyReviewDismissal
        )
    ]

    static let requiredActivationContractIDs = Set(activationContracts.map(\.contractID))
    static let repeatableActivationContractIDs = Set(
        activationContracts
            .filter { $0.phase != .initialSurface }
            .map(\.contractID)
    )

    static func validatedReport(
        contentView: NSView,
        controller: QuillCodeDesktopController,
        nativeHitTargets: QuillCodeNativeHitTargetAuditReport,
        includesInitialSurface: Bool = true
    ) async throws -> QuillCodeDesktopAccessibilityActivationReport {
        let report = try await sample(
            contentView: contentView,
            controller: controller,
            nativeHitTargets: nativeHitTargets,
            includesInitialSurface: includesInitialSurface
        )
        guard report.ok else {
            throw QuillCodeDesktopSmokeFailure.nativeAccessibilityActivationFailed(report.validationIssues)
        }
        return report
    }

    private static func sample(
        contentView: NSView,
        controller: QuillCodeDesktopController,
        nativeHitTargets: QuillCodeNativeHitTargetAuditReport,
        includesInitialSurface: Bool
    ) async throws -> QuillCodeDesktopAccessibilityActivationReport {
        let probesByID = Dictionary(uniqueKeysWithValues: nativeHitTargets.clickProbes.map { ($0.contractID, $0) })
        var checks: [QuillCodeDesktopAccessibilityActivationCheck] = []
        var validationIssues: [String] = []
        let sampledContracts = applicableActivationContracts(
            includesInitialSurface: includesInitialSurface,
            controller: controller
        )

        for contract in sampledContracts {
            markStage("start", contractID: contract.contractID)
            contract.prepare?(controller)
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let probe = probesByID[contract.contractID] else {
                validationIssues.append("\(contract.contractID) has no native click probe to activate")
                continue
            }
            guard let element = await resolveCurrentElement(probe, contentView: contentView) else {
                validationIssues.append(
                    "\(contract.contractID) did not resolve to an AXPress target; "
                        + unresolvedElementDiagnostic(probe, contentView: contentView)
                )
                markStage("unresolved", contractID: contract.contractID)
                continue
            }

            let result = try await activate(
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
            markStage("complete", contractID: contract.contractID)
        }

        let activatedIDs = checks.filter(\.ok).map(\.contractID).sorted()
        let skippedIDs = Set(nativeHitTargets.clickProbes.map(\.contractID))
            .subtracting(Set(checks.map(\.contractID)))
            .sorted()

        return QuillCodeDesktopAccessibilityActivationReport(
            liveAccessibilityActivation: "ax-press-sampled",
            requiredContractIDs: sampledContracts.map(\.contractID).sorted(),
            activatedContractIDs: activatedIDs,
            skippedContractIDs: skippedIDs,
            checks: checks.sorted { $0.contractID < $1.contractID },
            validationIssues: validationIssues.sorted()
        )
    }

    static func orderedActivationContractIDs(includesInitialSurface: Bool) -> [String] {
        orderedActivationContracts(includesInitialSurface: includesInitialSurface).map(\.contractID)
    }

    static func applicableActivationContractIDs(
        includesInitialSurface: Bool,
        controller: QuillCodeDesktopController
    ) -> [String] {
        applicableActivationContracts(
            includesInitialSurface: includesInitialSurface,
            controller: controller
        ).map(\.contractID)
    }

    private static func applicableActivationContracts(
        includesInitialSurface: Bool,
        controller: QuillCodeDesktopController
    ) -> [QuillCodeDesktopAccessibilityActivationContract] {
        orderedActivationContracts(includesInitialSurface: includesInitialSurface)
            .filter { $0.isApplicable(controller) }
    }

    private static func orderedActivationContracts(
        includesInitialSurface: Bool
    ) -> [QuillCodeDesktopAccessibilityActivationContract] {
        activationContracts.enumerated()
            .filter { _, contract in
                includesInitialSurface || repeatableActivationContractIDs.contains(contract.contractID)
            }
            .sorted { lhs, rhs in
                if lhs.element.phase != rhs.element.phase {
                    return lhs.element.phase < rhs.element.phase
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func activate(
        contract: QuillCodeDesktopAccessibilityActivationContract,
        probe: QuillCodeNativeHitTargetProbe,
        element: QuillCodeDesktopAccessibilityElementSnapshot,
        contentView: NSView,
        controller: QuillCodeDesktopController
    ) async throws -> QuillCodeDesktopAccessibilityActivationCheck {
        let baseline = contract.observe(controller)
        let baselineResources = try QuillCodeDesktopProcessResourceSnapshot.capture()
        let axError = QuillCodeDesktopAccessibilityTree.performPress(on: element)
        _ = await waitForStateChange(contract: contract, baseline: baseline, controller: controller)
        let after = contract.observe(controller)
        await QuillCodeDesktopAccessibilityHierarchySettler.waitUntilStable(in: contentView)
        let presentedResources = try QuillCodeDesktopProcessResourceSnapshot.capture()
        let activationIssue = validationIssue(
            contractID: contract.contractID,
            axError: axError,
            before: baseline,
            after: after
        ).map { issue in
            "\(issue) via \(element.role) id=\(element.identifier) label=\(element.bestLabel)"
        }
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
        await QuillCodeDesktopAccessibilityHierarchySettler.waitUntilStable(in: contentView)
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
            baselineResidentMemoryBytes: baselineResources.residentMemoryBytes,
            presentedResidentMemoryBytes: presentedResources.residentMemoryBytes,
            presentedResidentMemoryGrowthBytes: presentedResources.residentMemoryBytes
                - baselineResources.residentMemoryBytes,
            baselineThreadCount: baselineResources.threadCount,
            presentedThreadCount: presentedResources.threadCount,
            validationIssue: contractIssue ?? verification.validationIssue ?? resetIssue
        )
    }

    private static func resolveCurrentElement(
        _ probe: QuillCodeNativeHitTargetProbe,
        contentView: NSView
    ) async -> QuillCodeDesktopAccessibilityElementSnapshot? {
        let directCandidates = QuillCodeDesktopAccessibilityFrameSampler.candidateIdentifiers(for: probe)
        let directElements = QuillCodeDesktopAccessibilityTree(
            root: contentView,
            matchingAnyIdentifier: directCandidates
        ).elements
        if let directElement = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
            probe,
            in: directElements
        ) {
            return directElement
        }
        return await waitForResolvableElement(probe) {
            QuillCodeDesktopAccessibilityTree(root: contentView).elements
        }
    }

    static func waitForResolvableElement(
        _ probe: QuillCodeNativeHitTargetProbe,
        maximumAttempts: Int = 100,
        retryIntervalNanoseconds: UInt64 = 50_000_000,
        elements: () -> [QuillCodeDesktopAccessibilityElementSnapshot]
    ) async -> QuillCodeDesktopAccessibilityElementSnapshot? {
        let attemptCount = max(1, maximumAttempts)
        for attempt in 0..<attemptCount {
            if let element = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
                probe,
                in: elements()
            ) {
                return element
            }
            guard attempt + 1 < attemptCount, !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: retryIntervalNanoseconds)
        }
        return nil
    }

    private static func unresolvedElementDiagnostic(
        _ probe: QuillCodeNativeHitTargetProbe,
        contentView: NSView
    ) -> String {
        let elements = QuillCodeDesktopAccessibilityTree(root: contentView).elements
        let candidates = elements.filter { element in
            element.identifier.localizedCaseInsensitiveContains(probe.selector)
                || element.bestLabel.localizedCaseInsensitiveContains(probe.label)
        }
        let descriptions = candidates.prefix(6).map { element in
            "\(element.role) id=\(element.identifier) label=\(element.bestLabel)"
        }
        return descriptions.isEmpty
            ? "no identifier or label candidates were present in the live AX tree"
            : "live AX candidates: \(descriptions.joined(separator: "; "))"
    }

    private static func axErrorDescription(_ error: AXError) -> String {
        error == .success ? "success" : String(describing: error)
    }

    private static func markStage(_ stage: String, contractID: String) {
        let residentMemory = (try? QuillCodeDesktopProcessResourceSnapshot.capture())
            .map { " footprint=\($0.residentMemoryBytes) threads=\($0.threadCount)" }
            ?? ""
        FileHandle.standardError.write(
            Data("quill-code-desktop AX activation \(stage): \(contractID)\(residentMemory)\n".utf8)
        )
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
