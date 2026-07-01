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
        let policyCoverage = surfacePolicyCoverage(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let coveredFocusTargets = Set(surfaceContracts.compactMap(\.focusTarget))
        let missingFocusTargets = requiredFocusTargets
            .filter { !coveredFocusTargets.contains($0) }
            .map(\.rawValue)
            .sorted()
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
            missingRequiredSurfaceKinds: policyCoverage.missingRequiredKinds,
            coveredFocusTargets: coveredFocusTargets.map(\.rawValue).sorted(),
            missingRequiredFocusTargets: missingFocusTargets,
            missingRequiredSurfaceActions: policyCoverage.missingRequiredActions,
            missingRequiredSurfaceFocusTargets: policyCoverage.missingRequiredFocusTargets,
            unexpectedSurfaceKinds: policyCoverage.unexpectedKinds,
            unexpectedSurfaceActions: policyCoverage.unexpectedActions,
            unexpectedSurfaceFocusTargets: policyCoverage.unexpectedFocusTargets,
            missingRequiredCommandIDs: missingCommandIDs,
            missingClickProbeContractIDs: missingClickProbeContractIDs,
            clickProbeValidationIssues: clickProbeValidationIssues,
            duplicateContractIDs: duplicateContractIDs,
            validationIssues: validationIssues
        )
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
}
