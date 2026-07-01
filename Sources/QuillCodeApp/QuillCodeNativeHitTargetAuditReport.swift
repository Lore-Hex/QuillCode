import Foundation

public struct QuillCodeNativeHitTargetAuditReport: Codable, Sendable, Hashable {
    public var minimumHitTarget: Double
    public var minimumTargetClearance: Double
    public var pressScale: Double
    public var surfacePolicies: [QuillCodeNativeSurfaceTargetPolicy]
    public var designSystemContracts: [QuillCodeNativeHitTargetContract]
    public var surfaceContracts: [QuillCodeNativeHitTargetContract]
    public var clickProbes: [QuillCodeNativeHitTargetProbe]
    public var missingDesignKinds: [String]
    public var coveredSurfaceFamilies: [String]
    public var missingSurfaceFamilies: [String]
    public var missingRequiredSurfaceKinds: [String]
    public var coveredFocusTargets: [String]
    public var missingRequiredFocusTargets: [String]
    public var missingRequiredSurfaceActions: [String]
    public var missingRequiredSurfaceFocusTargets: [String]
    public var unexpectedSurfaceKinds: [String]
    public var unexpectedSurfaceActions: [String]
    public var unexpectedSurfaceFocusTargets: [String]
    public var missingRequiredCommandIDs: [String]
    public var missingClickProbeContractIDs: [String]
    public var clickProbeValidationIssues: [String]
    public var duplicateContractIDs: [String]
    public var validationIssues: [String]

    public var isValid: Bool {
        missingDesignKinds.isEmpty
            && missingSurfaceFamilies.isEmpty
            && missingRequiredSurfaceKinds.isEmpty
            && missingRequiredFocusTargets.isEmpty
            && missingRequiredSurfaceActions.isEmpty
            && missingRequiredSurfaceFocusTargets.isEmpty
            && unexpectedSurfaceKinds.isEmpty
            && unexpectedSurfaceActions.isEmpty
            && unexpectedSurfaceFocusTargets.isEmpty
            && missingRequiredCommandIDs.isEmpty
            && missingClickProbeContractIDs.isEmpty
            && clickProbeValidationIssues.isEmpty
            && duplicateContractIDs.isEmpty
            && validationIssues.isEmpty
    }

    public var dictionary: [String: Any] {
        [
            "minimumHitTarget": minimumHitTarget,
            "minimumTargetClearance": minimumTargetClearance,
            "pressScale": pressScale,
            "isValid": isValid,
            "surfacePolicies": surfacePolicies.map(\.dictionary),
            "designSystemContracts": designSystemContracts.map(\.dictionary),
            "surfaceContracts": surfaceContracts.map(\.dictionary),
            "clickProbes": clickProbes.map(\.dictionary),
            "missingDesignKinds": missingDesignKinds,
            "coveredSurfaceFamilies": coveredSurfaceFamilies,
            "missingSurfaceFamilies": missingSurfaceFamilies,
            "missingRequiredSurfaceKinds": missingRequiredSurfaceKinds,
            "coveredFocusTargets": coveredFocusTargets,
            "missingRequiredFocusTargets": missingRequiredFocusTargets,
            "missingRequiredSurfaceActions": missingRequiredSurfaceActions,
            "missingRequiredSurfaceFocusTargets": missingRequiredSurfaceFocusTargets,
            "unexpectedSurfaceKinds": unexpectedSurfaceKinds,
            "unexpectedSurfaceActions": unexpectedSurfaceActions,
            "unexpectedSurfaceFocusTargets": unexpectedSurfaceFocusTargets,
            "missingRequiredCommandIDs": missingRequiredCommandIDs,
            "missingClickProbeContractIDs": missingClickProbeContractIDs,
            "clickProbeValidationIssues": clickProbeValidationIssues,
            "duplicateContractIDs": duplicateContractIDs,
            "validationIssues": validationIssues
        ]
    }
}
