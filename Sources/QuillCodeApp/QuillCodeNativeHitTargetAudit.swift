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

}
