import Foundation

extension QuillCodeNativeHitTargetAudit {
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

            issues += selectorValidationIssues(probe: probe, contract: contract)
            issues += semanticValidationIssues(probe: probe, contract: contract)
            issues += dimensionValidationIssues(probe: probe)
            issues += samplePointValidationIssues(probe: probe)
        }

        return issues.sorted()
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
                requiredMinWidth: max(contract.minWidth ?? minimumHitTarget, minimumHitTarget),
                requiredMinHeight: max(contract.minHeight, minimumHitTarget),
                requiredPeerClearance: minimumTargetClearance,
                samplePoints: normalizedClickSamplePoints
            )
        }
        .sorted { lhs, rhs in
            lhs.contractID < rhs.contractID
        }
    }

    private static func selectorValidationIssues(
        probe: QuillCodeNativeHitTargetProbe,
        contract: QuillCodeNativeHitTargetContract
    ) -> [String] {
        let selector = probe.selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else {
            return ["\(probe.contractID) click probe has an empty selector"]
        }
        guard selector == expectedSelector(for: probe.selectorKind, contract: contract) else {
            return [
                "\(probe.contractID) click probe selector \(selector) does not match " +
                    "\(probe.selectorKind.rawValue) contract selector"
            ]
        }
        return []
    }

    private static func expectedSelector(
        for kind: QuillCodeNativeHitTargetProbeSelectorKind,
        contract: QuillCodeNativeHitTargetContract
    ) -> String? {
        switch kind {
        case .testID:
            return contract.testID
        case .commandID:
            return contract.commandID
        case .focusTarget:
            return contract.focusTarget?.rawValue
        }
    }

    private static func semanticValidationIssues(
        probe: QuillCodeNativeHitTargetProbe,
        contract: QuillCodeNativeHitTargetContract
    ) -> [String] {
        var issues: [String] = []
        appendMismatch(&issues, probe: probe, label: "kind", actual: probe.kind, expected: contract.kind)
        appendMismatch(&issues, probe: probe, label: "action", actual: probe.action, expected: contract.action)
        appendMismatch(&issues, probe: probe, label: "family", actual: probe.family, expected: contract.family)
        if probe.collisionScope != contract.collisionScope {
            issues.append("\(probe.contractID) click probe collision scope does not match contract")
        }
        appendPolicyMismatch(
            &issues,
            probe: probe,
            message: "click probe nested-child policy does not match contract",
            actual: probe.allowsNestedInteractiveChildren,
            expected: contract.allowsNestedInteractiveChildren
        )
        appendPolicyMismatch(
            &issues,
            probe: probe,
            message: "click probe interior-blocking policy does not match contract",
            actual: probe.requiresUnblockedInterior,
            expected: contract.requiresUnblockedInterior
        )
        appendPolicyMismatch(
            &issues,
            probe: probe,
            message: "click probe tactile-feedback policy does not match contract",
            actual: probe.requiresTactileFeedback,
            expected: contract.requiresTactileFeedback
        )
        appendPolicyMismatch(
            &issues,
            probe: probe,
            message: "click probe text-selection policy does not match contract",
            actual: probe.allowsTextSelection,
            expected: contract.allowsTextSelection
        )
        return issues
    }

    private static func appendMismatch<Value: RawRepresentable>(
        _ issues: inout [String],
        probe: QuillCodeNativeHitTargetProbe,
        label: String,
        actual: Value,
        expected: Value
    ) where Value.RawValue == String {
        guard actual.rawValue != expected.rawValue else { return }
        issues.append(
            "\(probe.contractID) click probe \(label) \(actual.rawValue) does not match \(expected.rawValue)"
        )
    }

    private static func appendPolicyMismatch(
        _ issues: inout [String],
        probe: QuillCodeNativeHitTargetProbe,
        message: String,
        actual: Bool,
        expected: Bool
    ) {
        guard actual != expected else { return }
        issues.append("\(probe.contractID) \(message)")
    }

    private static func dimensionValidationIssues(
        probe: QuillCodeNativeHitTargetProbe
    ) -> [String] {
        var issues: [String] = []
        appendMinimumDimensionIssue(
            &issues,
            contractID: probe.contractID,
            label: "requiredMinWidth",
            actual: probe.requiredMinWidth,
            minimum: minimumHitTarget
        )
        appendMinimumDimensionIssue(
            &issues,
            contractID: probe.contractID,
            label: "requiredMinHeight",
            actual: probe.requiredMinHeight,
            minimum: minimumHitTarget
        )
        appendMinimumDimensionIssue(
            &issues,
            contractID: probe.contractID,
            label: "requiredPeerClearance",
            actual: probe.requiredPeerClearance,
            minimum: minimumTargetClearance
        )
        return issues
    }

    private static func appendMinimumDimensionIssue(
        _ issues: inout [String],
        contractID: String,
        label: String,
        actual: Double,
        minimum: Double
    ) {
        guard actual < minimum else { return }
        issues.append("\(contractID) click probe \(label) \(actual) is below \(minimum)")
    }

    private static func samplePointValidationIssues(
        probe: QuillCodeNativeHitTargetProbe
    ) -> [String] {
        var issues: [String] = []
        appendMissingSamplePointIssue(&issues, probe: probe)
        for point in probe.samplePoints {
            appendSamplePointIssues(&issues, probe: probe, point: point)
        }
        return issues
    }

    private static func appendMissingSamplePointIssue(
        _ issues: inout [String],
        probe: QuillCodeNativeHitTargetProbe
    ) {
        let pointNames = Set(probe.samplePoints.map(\.name))
        let missingPointNames = requiredClickSamplePointNames
            .filter { !pointNames.contains($0) }
            .sorted()
        guard !missingPointNames.isEmpty else { return }
        issues.append(
            "\(probe.contractID) click probe is missing sample points: " +
                missingPointNames.joined(separator: ", ")
        )
    }

    private static func appendSamplePointIssues(
        _ issues: inout [String],
        probe: QuillCodeNativeHitTargetProbe,
        point: QuillCodeNativeHitTargetProbePoint
    ) {
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

    private static var minimumHitTarget: Double {
        Double(QuillCodeMetrics.minimumHitTarget)
    }

    private static var minimumTargetClearance: Double {
        Double(QuillCodeMetrics.minimumTargetClearance)
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
