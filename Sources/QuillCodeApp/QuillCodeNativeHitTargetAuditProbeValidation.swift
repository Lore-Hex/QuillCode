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
            return [selectorMismatchMessage(probe: probe, selector: selector)]
        }
        return []
    }

    private static func selectorMismatchMessage(
        probe: QuillCodeNativeHitTargetProbe,
        selector: String
    ) -> String {
        "\(probe.contractID) click probe selector \(selector) does not match "
            + "\(probe.selectorKind.rawValue) contract selector"
    }

    private static func semanticValidationIssues(
        probe: QuillCodeNativeHitTargetProbe,
        contract: QuillCodeNativeHitTargetContract
    ) -> [String] {
        var issues: [String] = []
        if probe.kind != contract.kind {
            issues.append(
                semanticMismatchMessage(
                    contractID: probe.contractID,
                    field: "kind",
                    actual: probe.kind.rawValue,
                    expected: contract.kind.rawValue
                )
            )
        }
        if probe.action != contract.action {
            issues.append(
                semanticMismatchMessage(
                    contractID: probe.contractID,
                    field: "action",
                    actual: probe.action.rawValue,
                    expected: contract.action.rawValue
                )
            )
        }
        if probe.family != contract.family {
            issues.append(
                semanticMismatchMessage(
                    contractID: probe.contractID,
                    field: "family",
                    actual: probe.family.rawValue,
                    expected: contract.family.rawValue
                )
            )
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

    private static func semanticMismatchMessage(
        contractID: String,
        field: String,
        actual: String,
        expected: String
    ) -> String {
        "\(contractID) click probe \(field) \(actual) does not match \(expected)"
    }

    private static func dimensionValidationIssues(
        probe: QuillCodeNativeHitTargetProbe
    ) -> [String] {
        var issues: [String] = []
        let minimum = Double(QuillCodeMetrics.minimumHitTarget)
        let minimumClearance = Double(QuillCodeMetrics.minimumTargetClearance)
        if probe.requiredMinWidth < minimum {
            issues.append(
                minimumDimensionMessage(
                    contractID: probe.contractID,
                    dimension: "requiredMinWidth",
                    actual: probe.requiredMinWidth,
                    minimum: minimum
                )
            )
        }
        if probe.requiredMinHeight < minimum {
            issues.append(
                minimumDimensionMessage(
                    contractID: probe.contractID,
                    dimension: "requiredMinHeight",
                    actual: probe.requiredMinHeight,
                    minimum: minimum
                )
            )
        }
        if probe.requiredPeerClearance < minimumClearance {
            issues.append(
                minimumDimensionMessage(
                    contractID: probe.contractID,
                    dimension: "requiredPeerClearance",
                    actual: probe.requiredPeerClearance,
                    minimum: minimumClearance
                )
            )
        }
        return issues
    }

    private static func minimumDimensionMessage(
        contractID: String,
        dimension: String,
        actual: Double,
        minimum: Double
    ) -> String {
        "\(contractID) click probe \(dimension) \(actual) is below \(minimum)"
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
            issues.append(
                missingSamplePointsMessage(contractID: probe.contractID, pointNames: missingPointNames)
            )
        }
        for point in probe.samplePoints {
            issues.append(contentsOf: samplePointNamingIssues(probe: probe, point: point))
            if point.x <= 0 || point.x >= 1 || point.y <= 0 || point.y >= 1 {
                issues.append(samplePointOutsideInteriorMessage(probe: probe, point: point))
            }
        }
        return issues
    }

    private static func missingSamplePointsMessage(
        contractID: String,
        pointNames: [String]
    ) -> String {
        "\(contractID) click probe is missing sample points: \(pointNames.joined(separator: ", "))"
    }

    private static func samplePointOutsideInteriorMessage(
        probe: QuillCodeNativeHitTargetProbe,
        point: QuillCodeNativeHitTargetProbePoint
    ) -> String {
        "\(probe.contractID) click probe sample point \(point.name) is outside the target interior"
    }

    private static func samplePointNamingIssues(
        probe: QuillCodeNativeHitTargetProbe,
        point: QuillCodeNativeHitTargetProbePoint
    ) -> [String] {
        let pointName = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if pointName.isEmpty {
            return ["\(probe.contractID) click probe has an unnamed sample point"]
        }
        guard let expectedPoint = expectedClickSamplePointsByName[pointName] else {
            return ["\(probe.contractID) click probe has unknown sample point \(point.name)"]
        }
        if !point.x.isNearlyEqual(to: expectedPoint.x) || !point.y.isNearlyEqual(to: expectedPoint.y) {
            return ["\(probe.contractID) click probe sample point \(point.name) has unexpected coordinates"]
        }
        return []
    }
}

private extension Double {
    func isNearlyEqual(to other: Double) -> Bool {
        abs(self - other) <= 1e-9
    }
}
