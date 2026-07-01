import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func missingClickProbeContractIDs(
        contracts: [QuillCodeNativeHitTargetContract],
        probes: [QuillCodeNativeHitTargetProbe]
    ) -> [String] {
        let probedContractIDs = Set(probes.map(\.contractID))
        return contracts
            .map(\.id)
            .filter { !probedContractIDs.contains($0) }
            .sorted()
    }

    static func clickProbes(
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

    static let requiredClickSamplePointNames: Set<String> = [
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

    static let normalizedClickSamplePoints: [QuillCodeNativeHitTargetProbePoint] = [
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

    static let expectedClickSamplePointsByName = Dictionary(
        uniqueKeysWithValues: normalizedClickSamplePoints.map { ($0.name, $0) }
    )
}
