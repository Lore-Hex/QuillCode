import Foundation

public enum QuillCodeNativeHitTargetAudit {
    public static func report(for surface: WorkspaceSurface) -> QuillCodeNativeHitTargetAuditReport {
        let commandIDs = Set(surface.commands.map(\.id))
        let missingCommandIDs = requiredCommandIDs.filter { !commandIDs.contains($0) }
        let surfaceContracts = self.surfaceContracts(for: surface)
        let designContracts = designSystemContracts
        let clickProbes = clickProbes(for: surfaceContracts)
        let designKinds = Set(designContracts.map(\.kind))
        let missingKinds = QuillCodeNativeHitTargetKind.allCases
            .filter { !designKinds.contains($0) }
            .map(\.rawValue)
        let coveredFamilies = Set((designContracts + surfaceContracts).map(\.family))
        let missingFamilies = requiredSurfaceFamilies
            .filter { !coveredFamilies.contains($0) }
            .map(\.rawValue)
            .sorted()
        let allContracts = designContracts + surfaceContracts
        let missingSurfaceKinds = missingRequiredSurfaceKinds(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let missingSurfaceActions = missingRequiredSurfaceActions(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let coveredFocusTargets = Set(surfaceContracts.compactMap(\.focusTarget))
        let missingFocusTargets = requiredFocusTargets
            .filter { !coveredFocusTargets.contains($0) }
            .map(\.rawValue)
            .sorted()
        let missingSurfaceFocusTargets = missingRequiredSurfaceFocusTargets(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let unexpectedSurfaceKinds = unexpectedSurfaceKinds(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let unexpectedSurfaceActions = unexpectedSurfaceActions(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let unexpectedSurfaceFocusTargets = unexpectedSurfaceFocusTargets(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let duplicateContractIDs = duplicateIDs(in: allContracts.map(\.id))
        let validationIssues = allContracts.flatMap(\.validationIssues)
        let missingClickProbeContractIDs = missingClickProbeContractIDs(
            contracts: surfaceContracts,
            probes: clickProbes
        )
        let clickProbeValidationIssues = validateClickProbes(
            contracts: surfaceContracts,
            probes: clickProbes
        )

        return QuillCodeNativeHitTargetAuditReport(
            minimumHitTarget: Double(QuillCodeMetrics.minimumHitTarget),
            minimumTargetClearance: Double(QuillCodeMetrics.minimumTargetClearance),
            pressScale: Double(QuillCodeMetrics.pressScale),
            surfacePolicies: requiredSurfacePolicies,
            designSystemContracts: designContracts,
            surfaceContracts: surfaceContracts,
            clickProbes: clickProbes,
            missingDesignKinds: missingKinds,
            coveredSurfaceFamilies: coveredFamilies.map(\.rawValue).sorted(),
            missingSurfaceFamilies: missingFamilies,
            missingRequiredSurfaceKinds: missingSurfaceKinds,
            coveredFocusTargets: coveredFocusTargets.map(\.rawValue).sorted(),
            missingRequiredFocusTargets: missingFocusTargets,
            missingRequiredSurfaceActions: missingSurfaceActions,
            missingRequiredSurfaceFocusTargets: missingSurfaceFocusTargets,
            unexpectedSurfaceKinds: unexpectedSurfaceKinds,
            unexpectedSurfaceActions: unexpectedSurfaceActions,
            unexpectedSurfaceFocusTargets: unexpectedSurfaceFocusTargets,
            missingRequiredCommandIDs: missingCommandIDs,
            missingClickProbeContractIDs: missingClickProbeContractIDs,
            clickProbeValidationIssues: clickProbeValidationIssues,
            duplicateContractIDs: duplicateContractIDs,
            validationIssues: validationIssues
        )
    }

    private static func missingRequiredSurfaceKinds(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        missingRequiredPolicyValues(
            policies: policies,
            contracts: contracts,
            requiredValues: \.requiredKinds,
            contractValue: { Optional($0.kind) },
            valueDescription: \.rawValue
        )
    }

    private static func missingRequiredSurfaceActions(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        missingRequiredPolicyValues(
            policies: policies,
            contracts: contracts,
            requiredValues: \.requiredActions,
            contractValue: { Optional($0.action) },
            valueDescription: \.rawValue
        )
    }

    private static func missingRequiredSurfaceFocusTargets(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        missingRequiredPolicyValues(
            policies: policies,
            contracts: contracts,
            requiredValues: \.requiredFocusTargets,
            contractValue: \.focusTarget,
            valueDescription: \.rawValue
        )
    }

    private static func missingRequiredPolicyValues<Value: Hashable>(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract],
        requiredValues: (QuillCodeNativeSurfaceTargetPolicy) -> [Value],
        contractValue: (QuillCodeNativeHitTargetContract) -> Value?,
        valueDescription: (Value) -> String
    ) -> [String] {
        let contractsByFamily = Dictionary(grouping: contracts, by: \.family)
        return policies.flatMap { policy in
            let coveredValues = Set(contractsByFamily[policy.family, default: []].compactMap(contractValue))
            return requiredValues(policy).compactMap { value in
                coveredValues.contains(value) ? nil : "\(policy.family.rawValue):\(valueDescription(value))"
            }
        }
        .sorted()
    }

    private static func unexpectedSurfaceKinds(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        unexpectedPolicyValues(
            policies: policies,
            contracts: contracts,
            allowedValues: \.allowedKinds,
            contractValue: { $0.kind },
            valueDescription: \.rawValue
        )
    }

    private static func unexpectedSurfaceActions(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        unexpectedPolicyValues(
            policies: policies,
            contracts: contracts,
            allowedValues: \.allowedActions,
            contractValue: { $0.action },
            valueDescription: \.rawValue
        )
    }

    private static func unexpectedSurfaceFocusTargets(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        unexpectedPolicyValues(
            policies: policies,
            contracts: contracts,
            allowedValues: \.allowedFocusTargets,
            contractValue: \.focusTarget,
            valueDescription: \.rawValue
        )
    }

    private static func unexpectedPolicyValues<Value: Hashable>(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract],
        allowedValues: (QuillCodeNativeSurfaceTargetPolicy) -> [Value],
        contractValue: (QuillCodeNativeHitTargetContract) -> Value?,
        valueDescription: (Value) -> String
    ) -> [String] {
        let allowedValuesByFamily = Dictionary(
            uniqueKeysWithValues: policies.map { ($0.family, Set(allowedValues($0))) }
        )
        return contracts.compactMap { contract in
            guard let value = contractValue(contract),
                  let allowedValues = allowedValuesByFamily[contract.family],
                  !allowedValues.contains(value)
            else { return nil }
            return "\(contract.family.rawValue):\(contract.id):\(valueDescription(value))"
        }
        .sorted()
    }

    private static func duplicateIDs(in ids: [String]) -> [String] {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for id in ids {
            guard !seen.insert(id).inserted else { continue }
            duplicates.insert(id)
        }
        return duplicates.sorted()
    }

    private static func missingClickProbeContractIDs(
        contracts: [QuillCodeNativeHitTargetContract],
        probes: [QuillCodeNativeHitTargetProbe]
    ) -> [String] {
        let probedContractIDs = Set(probes.map(\.contractID))
        return contracts
            .map(\.id)
            .filter { !probedContractIDs.contains($0) }
            .sorted()
    }

    public static func validateClickProbes(
        contracts: [QuillCodeNativeHitTargetContract],
        probes: [QuillCodeNativeHitTargetProbe]
    ) -> [String] {
        let contractsByID = Dictionary(
            contracts.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seenProbeIDs: Set<String> = []
        var issues: [String] = []

        for probe in probes {
            let contractID = probe.contractID.trimmingCharacters(in: .whitespacesAndNewlines)
            if contractID.isEmpty {
                issues.append("click probe has an empty contract id")
                continue
            }
            guard seenProbeIDs.insert(contractID).inserted else {
                issues.append("\(contractID) has duplicate click probes")
                continue
            }
            guard let contract = contractsByID[contractID] else {
                issues.append("\(contractID) click probe does not match a surface contract")
                continue
            }

            issues.append(contentsOf: selectorValidationIssues(probe: probe, contract: contract))
            issues.append(contentsOf: semanticValidationIssues(probe: probe, contract: contract))
            issues.append(contentsOf: dimensionValidationIssues(probe: probe))
            issues.append(contentsOf: samplePointValidationIssues(probe: probe))
        }

        return issues.sorted()
    }

    private static func selectorValidationIssues(
        probe: QuillCodeNativeHitTargetProbe,
        contract: QuillCodeNativeHitTargetContract
    ) -> [String] {
        let expectedSelector: String?
        switch probe.selectorKind {
        case .testID:
            expectedSelector = contract.testID
        case .commandID:
            expectedSelector = contract.commandID
        case .focusTarget:
            expectedSelector = contract.focusTarget?.rawValue
        }

        let selector = probe.selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if selector.isEmpty {
            return ["\(probe.contractID) click probe has an empty selector"]
        }
        if selector != expectedSelector {
            return ["\(probe.contractID) click probe selector \(selector) does not match \(probe.selectorKind.rawValue) contract selector"]
        }
        return []
    }

    private static func semanticValidationIssues(
        probe: QuillCodeNativeHitTargetProbe,
        contract: QuillCodeNativeHitTargetContract
    ) -> [String] {
        var issues: [String] = []
        if probe.kind != contract.kind {
            issues.append("\(probe.contractID) click probe kind \(probe.kind.rawValue) does not match \(contract.kind.rawValue)")
        }
        if probe.action != contract.action {
            issues.append("\(probe.contractID) click probe action \(probe.action.rawValue) does not match \(contract.action.rawValue)")
        }
        if probe.family != contract.family {
            issues.append("\(probe.contractID) click probe family \(probe.family.rawValue) does not match \(contract.family.rawValue)")
        }
        if probe.collisionScope != contract.collisionScope {
            issues.append("\(probe.contractID) click probe collision scope does not match contract")
        }
        if probe.allowsNestedInteractiveChildren != contract.allowsNestedInteractiveChildren {
            issues.append("\(probe.contractID) click probe nested-child policy does not match contract")
        }
        if probe.requiresUnblockedInterior != contract.requiresUnblockedInterior {
            issues.append("\(probe.contractID) click probe interior-blocking policy does not match contract")
        }
        if probe.requiresTactileFeedback != contract.requiresTactileFeedback {
            issues.append("\(probe.contractID) click probe tactile-feedback policy does not match contract")
        }
        if probe.allowsTextSelection != contract.allowsTextSelection {
            issues.append("\(probe.contractID) click probe text-selection policy does not match contract")
        }
        return issues
    }

    private static func dimensionValidationIssues(
        probe: QuillCodeNativeHitTargetProbe
    ) -> [String] {
        var issues: [String] = []
        let minimum = Double(QuillCodeMetrics.minimumHitTarget)
        let minimumClearance = Double(QuillCodeMetrics.minimumTargetClearance)
        if probe.requiredMinWidth < minimum {
            issues.append("\(probe.contractID) click probe requiredMinWidth \(probe.requiredMinWidth) is below \(minimum)")
        }
        if probe.requiredMinHeight < minimum {
            issues.append("\(probe.contractID) click probe requiredMinHeight \(probe.requiredMinHeight) is below \(minimum)")
        }
        if probe.requiredPeerClearance < minimumClearance {
            issues.append("\(probe.contractID) click probe requiredPeerClearance \(probe.requiredPeerClearance) is below \(minimumClearance)")
        }
        return issues
    }

    private static func samplePointValidationIssues(
        probe: QuillCodeNativeHitTargetProbe
    ) -> [String] {
        var issues: [String] = []
        let pointNames = Set(probe.samplePoints.map(\.name))
        let missingPointNames = requiredClickSamplePointNames
            .filter { !pointNames.contains($0) }
            .sorted()
        if !missingPointNames.isEmpty {
            issues.append("\(probe.contractID) click probe is missing sample points: \(missingPointNames.joined(separator: ", "))")
        }
        for point in probe.samplePoints {
            let pointName = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if pointName.isEmpty {
                issues.append("\(probe.contractID) click probe has an unnamed sample point")
            } else if let expectedPoint = expectedClickSamplePointsByName[pointName] {
                if !point.x.isNearlyEqual(to: expectedPoint.x) || !point.y.isNearlyEqual(to: expectedPoint.y) {
                    issues.append("\(probe.contractID) click probe sample point \(point.name) has unexpected coordinates")
                }
            } else {
                issues.append("\(probe.contractID) click probe has unknown sample point \(point.name)")
            }
            if point.x <= 0 || point.x >= 1 || point.y <= 0 || point.y >= 1 {
                issues.append("\(probe.contractID) click probe sample point \(point.name) is outside the target interior")
            }
        }
        return issues
    }

    private static func clickProbes(
        for contracts: [QuillCodeNativeHitTargetContract]
    ) -> [QuillCodeNativeHitTargetProbe] {
        contracts.compactMap { contract in
            guard let selector = probeSelector(for: contract) else { return nil }
            return QuillCodeNativeHitTargetProbe(
                contractID: contract.id,
                family: contract.family,
                collisionScope: contract.collisionScope,
                label: contract.label,
                kind: contract.kind,
                action: contract.action,
                allowsNestedInteractiveChildren: contract.allowsNestedInteractiveChildren,
                requiresUnblockedInterior: contract.requiresUnblockedInterior,
                requiresTactileFeedback: contract.requiresTactileFeedback,
                allowsTextSelection: contract.allowsTextSelection,
                selectorKind: selector.kind,
                selector: selector.value,
                requiredMinWidth: max(
                    contract.minWidth ?? Double(QuillCodeMetrics.minimumHitTarget),
                    Double(QuillCodeMetrics.minimumHitTarget)
                ),
                requiredMinHeight: max(
                    contract.minHeight,
                    Double(QuillCodeMetrics.minimumHitTarget)
                ),
                requiredPeerClearance: Double(QuillCodeMetrics.minimumTargetClearance),
                samplePoints: normalizedClickSamplePoints
            )
        }
        .sorted { lhs, rhs in
            lhs.contractID < rhs.contractID
        }
    }

    private static func probeSelector(
        for contract: QuillCodeNativeHitTargetContract
    ) -> (kind: QuillCodeNativeHitTargetProbeSelectorKind, value: String)? {
        if let testID = contract.testID?.trimmingCharacters(in: .whitespacesAndNewlines), !testID.isEmpty {
            return (.testID, testID)
        }
        if let commandID = contract.commandID?.trimmingCharacters(in: .whitespacesAndNewlines), !commandID.isEmpty {
            return (.commandID, commandID)
        }
        if let focusTarget = contract.focusTarget {
            return (.focusTarget, focusTarget.rawValue)
        }
        return nil
    }

    private static let requiredClickSamplePointNames: Set<String> = [
        "center",
        "leading-edge",
        "leading-interior",
        "trailing-edge",
        "trailing-interior",
        "top-edge",
        "top-interior",
        "bottom-edge",
        "bottom-interior"
    ]

    private static let normalizedClickSamplePoints: [QuillCodeNativeHitTargetProbePoint] = [
        QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "leading-edge", x: 0.08, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "leading-interior", x: 0.18, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "trailing-edge", x: 0.92, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "trailing-interior", x: 0.82, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "top-edge", x: 0.5, y: 0.08),
        QuillCodeNativeHitTargetProbePoint(name: "top-interior", x: 0.5, y: 0.18),
        QuillCodeNativeHitTargetProbePoint(name: "bottom-edge", x: 0.5, y: 0.92),
        QuillCodeNativeHitTargetProbePoint(name: "bottom-interior", x: 0.5, y: 0.82)
    ]

    private static let expectedClickSamplePointsByName = Dictionary(
        uniqueKeysWithValues: normalizedClickSamplePoints.map { ($0.name, $0) }
    )


}

private extension Double {
    func isNearlyEqual(to other: Double) -> Bool {
        abs(self - other) <= 1e-9
    }
}
