import AppKit
import ApplicationServices
import Foundation
import QuillCodeApp

struct QuillCodeDesktopAccessibilityFrameSample {
    var contractID: String
    var selectorKind: String
    var selector: String
    var collisionScope: String
    var kind: String
    var action: String
    var resolvedIdentifier: String
    var role: String
    var label: String
    var frame: CGRect
    var requiredMinWidth: Double
    var requiredMinHeight: Double
    var requiredPeerClearance: Double
    var allowsNestedInteractiveChildren: Bool
    var requiresUnblockedInterior: Bool
    var requiresTactileFeedback: Bool
    var allowsTextSelection: Bool
    var samplePoints: [[String: Any]]

    var dictionary: [String: Any] {
        [
            "contractID": contractID,
            "selectorKind": selectorKind,
            "selector": selector,
            "collisionScope": collisionScope,
            "kind": kind,
            "action": action,
            "resolvedIdentifier": resolvedIdentifier,
            "role": role,
            "label": label,
            "frame": [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height
            ],
            "requiredMinWidth": requiredMinWidth,
            "requiredMinHeight": requiredMinHeight,
            "requiredPeerClearance": requiredPeerClearance,
            "allowsNestedInteractiveChildren": allowsNestedInteractiveChildren,
            "allowsTextSelection": allowsTextSelection,
            "requiresUnblockedInterior": requiresUnblockedInterior,
            "requiresTactileFeedback": requiresTactileFeedback,
            "samplePoints": samplePoints
        ]
    }
}

struct QuillCodeDesktopAccessibilityFrameSampleReport {
    var liveAccessibilitySampling: String
    var minimumHitTarget: Double
    var minimumTargetClearance: Double
    var requiredContractIDs: [String]
    var sampledContractIDs: [String]
    var unresolvedRequiredContractIDs: [String]
    var skippedContractIDs: [String]
    var samples: [QuillCodeDesktopAccessibilityFrameSample]
    var validationIssues: [String]

    var ok: Bool {
        validationIssues.isEmpty
    }

    var dictionary: [String: Any] {
        [
            "ok": ok,
            "liveAccessibilitySampling": liveAccessibilitySampling,
            "minimumHitTarget": minimumHitTarget,
            "minimumTargetClearance": minimumTargetClearance,
            "requiredContractIDs": requiredContractIDs,
            "sampledContractIDs": sampledContractIDs,
            "unresolvedRequiredContractIDs": unresolvedRequiredContractIDs,
            "skippedContractIDs": skippedContractIDs,
            "sampleCount": samples.count,
            "samples": samples.map(\.dictionary),
            "validationIssues": validationIssues
        ]
    }
}

@MainActor
enum QuillCodeDesktopAccessibilityFrameSampler {
    private static let identifierPrefix = "quillcode-"
    static let requiredPrimarySidebarContractIDs: Set<String> = [
        "command.add-project",
        "command.new-chat",
        "command.search",
        "command.toggle-automations",
        "command.toggle-extensions",
        "command.settings",
        "project.clear"
    ]

    private static let requiredCoreLiveContractIDs: Set<String> = [
        "composer.input",
        "composer.send",
        "composer.model-picker",
        "composer.mode-picker",
        "top-bar.overflow",
        "sidebar.tools-menu"
    ]

    static let requiredLiveContractIDs = requiredCoreLiveContractIDs
        .union(requiredPrimarySidebarContractIDs)

    static func validatedReport(
        window _: NSWindow,
        contentView: NSView,
        nativeHitTargets: QuillCodeNativeHitTargetAuditReport
    ) throws -> QuillCodeDesktopAccessibilityFrameSampleReport {
        let report = sample(contentView: contentView, nativeHitTargets: nativeHitTargets)
        guard report.ok else {
            throw QuillCodeDesktopSmokeFailure.nativeAccessibilityFrameSamplingFailed(report.validationIssues)
        }
        return report
    }

    private static func sample(
        contentView: NSView,
        nativeHitTargets: QuillCodeNativeHitTargetAuditReport
    ) -> QuillCodeDesktopAccessibilityFrameSampleReport {
        let elements = QuillCodeDesktopAccessibilityTree(root: contentView).elements
        let samples = nativeHitTargets.clickProbes.compactMap { probe -> QuillCodeDesktopAccessibilityFrameSample? in
            guard let element = resolveElement(for: probe, in: elements),
                  let frame = element.frame
            else {
                return nil
            }

            return QuillCodeDesktopAccessibilityFrameSample(
                contractID: probe.contractID,
                selectorKind: probe.selectorKind.rawValue,
                selector: probe.selector,
                collisionScope: probe.collisionScope,
                kind: probe.kind.rawValue,
                action: probe.action.rawValue,
                resolvedIdentifier: element.identifier,
                role: element.role,
                label: element.bestLabel,
                frame: frame,
                requiredMinWidth: probe.requiredMinWidth,
                requiredMinHeight: probe.requiredMinHeight,
                requiredPeerClearance: probe.requiredPeerClearance,
                allowsNestedInteractiveChildren: probe.allowsNestedInteractiveChildren,
                requiresUnblockedInterior: probe.requiresUnblockedInterior,
                requiresTactileFeedback: probe.requiresTactileFeedback,
                allowsTextSelection: probe.allowsTextSelection,
                samplePoints: samplePoints(for: probe, target: element, in: frame)
            )
        }
        .sorted { $0.contractID < $1.contractID }

        let sampledIDs = Set(samples.map(\.contractID))
        let requiredIDs = requiredLiveContractIDs.sorted()
        let unresolvedRequiredIDs = requiredIDs.filter { !sampledIDs.contains($0) }
        let probedIDs = Set(nativeHitTargets.clickProbes.map(\.contractID))
        let skippedIDs = probedIDs.subtracting(sampledIDs).sorted()
        let issues = validationIssues(
            samples: samples,
            unresolvedRequiredIDs: unresolvedRequiredIDs
        )

        return QuillCodeDesktopAccessibilityFrameSampleReport(
            liveAccessibilitySampling: "frame-sampled",
            minimumHitTarget: Double(QuillCodeMetrics.minimumHitTarget),
            minimumTargetClearance: Double(QuillCodeMetrics.minimumTargetClearance),
            requiredContractIDs: requiredIDs,
            sampledContractIDs: samples.map(\.contractID),
            unresolvedRequiredContractIDs: unresolvedRequiredIDs,
            skippedContractIDs: skippedIDs,
            samples: samples,
            validationIssues: issues
        )
    }

    private static func resolveElement(
        for probe: QuillCodeNativeHitTargetProbe,
        in elements: [QuillCodeDesktopAccessibilityElementSnapshot]
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        resolveElementForActivation(probe, in: elements)
    }

    static func resolveElementForActivation(
        _ probe: QuillCodeNativeHitTargetProbe,
        in elements: [QuillCodeDesktopAccessibilityElementSnapshot]
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        if let primaryElement = largestElement(matching: identifiers(for: probe), in: elements) {
            return primaryElement
        }
        guard probe.selectorKind == .commandID else { return nil }
        if let identifiedMenuElement = largestElement(
            matching: ["\(identifierPrefix)menu-command-\(probe.selector)"],
            in: elements
        ) {
            return identifiedMenuElement
        }
        return largestNativeMenuItem(
            titled: nativeMenuTitles(for: probe),
            in: elements
        )
    }

    private static func largestElement(
        matching identifiers: Set<String>,
        in elements: [QuillCodeDesktopAccessibilityElementSnapshot]
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        elements
            .filter { identifiers.contains($0.identifier) }
            .max { lhs, rhs in lhs.frameArea < rhs.frameArea }
    }

    private static func largestNativeMenuItem(
        titled titles: Set<String>,
        in elements: [QuillCodeDesktopAccessibilityElementSnapshot]
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        elements
            .filter { element in
                element.role == kAXMenuItemRole as String && titles.contains(element.title)
            }
            .max { lhs, rhs in lhs.frameArea < rhs.frameArea }
    }

    private static func nativeMenuTitles(for probe: QuillCodeNativeHitTargetProbe) -> Set<String> {
        var titles = Set([probe.label])
        if probe.selector.hasPrefix("toggle-") {
            titles.insert("Toggle \(probe.label)")
        }
        return titles
    }

    private static func identifiers(for probe: QuillCodeNativeHitTargetProbe) -> Set<String> {
        switch probe.selectorKind {
        case .testID:
            return [probe.selector]
        case .commandID:
            return [
                "\(identifierPrefix)sidebar-command-\(probe.selector)",
                "\(identifierPrefix)top-bar-command-\(probe.selector)",
                "\(identifierPrefix)workspace-command-\(probe.selector)"
            ]
        case .focusTarget:
            return [normalizedFocusIdentifier(probe.selector)]
        }
    }

    private static func normalizedFocusIdentifier(_ focusTarget: String) -> String {
        let normalized = focusTarget.replacingOccurrences(of: ".", with: "-")
        return "\(identifierPrefix)\(normalized)"
    }

    private static func samplePoints(
        for probe: QuillCodeNativeHitTargetProbe,
        target: QuillCodeDesktopAccessibilityElementSnapshot,
        in frame: CGRect
    ) -> [[String: Any]] {
        probe.samplePoints.map { point in
            let absolutePoint = CGPoint(
                x: frame.minX + (frame.width * point.x),
                y: frame.minY + (frame.height * point.y)
            )
            let hitTest = QuillCodeDesktopAccessibilityTree.hitTest(at: absolutePoint)
            let hitTestSnapshot = hitTest.snapshot
            let hitTestAncestorIdentifiers = hitTestSnapshot?.ancestorIdentifiers ?? []
            let hitTestMatchesTarget = hitTestSnapshot?.identifier == target.identifier
                || hitTestAncestorIdentifiers.contains(target.identifier)

            return [
                "name": point.name,
                "x": absolutePoint.x,
                "y": absolutePoint.y,
                "hitTestAvailable": hitTest.isAvailable,
                "hitTestError": hitTest.errorDescription,
                "hitTestIdentifier": hitTestSnapshot?.identifier ?? "",
                "hitTestRole": hitTestSnapshot?.role ?? "",
                "hitTestLabel": hitTestSnapshot?.bestLabel ?? "",
                "hitTestAncestorIdentifiers": hitTestAncestorIdentifiers,
                "hitTestMatchesTarget": hitTestMatchesTarget
            ]
        }
    }

    private static func validationIssues(
        samples: [QuillCodeDesktopAccessibilityFrameSample],
        unresolvedRequiredIDs: [String]
    ) -> [String] {
        var issues = unresolvedRequiredIDs.map { "\($0) did not resolve to a live Accessibility frame" }

        for sample in samples {
            if sample.frame.width < sample.requiredMinWidth {
                issues.append("\(sample.contractID) live frame width \(sample.frame.width) is below \(sample.requiredMinWidth)")
            }
            if sample.frame.height < sample.requiredMinHeight {
                issues.append("\(sample.contractID) live frame height \(sample.frame.height) is below \(sample.requiredMinHeight)")
            }
            if sample.requiredPeerClearance < Double(QuillCodeMetrics.minimumTargetClearance) {
                issues.append("\(sample.contractID) live peer clearance \(sample.requiredPeerClearance) is below \(QuillCodeMetrics.minimumTargetClearance)")
            }
            if sample.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(sample.contractID) live Accessibility frame has no label")
            }
            for point in sample.samplePoints {
                guard let x = point["x"] as? CGFloat,
                      let y = point["y"] as? CGFloat
                else {
                    issues.append("\(sample.contractID) emitted a malformed live sample point")
                    continue
                }
                if !sample.frame.contains(CGPoint(x: x, y: y)) {
                    issues.append("\(sample.contractID) live sample point \(point["name"] ?? "?") is outside the target frame")
                }
                guard let hitTestAvailable = point["hitTestAvailable"] as? Bool,
                      let hitTestMatchesTarget = point["hitTestMatchesTarget"] as? Bool
                else {
                    issues.append("\(sample.contractID) emitted a malformed hit-test result for \(point["name"] ?? "?")")
                    continue
                }
                if sample.requiresUnblockedInterior && hitTestAvailable && !hitTestMatchesTarget {
                    let identifier = point["hitTestIdentifier"] as? String ?? ""
                    issues.append(
                        "\(sample.contractID) live sample point \(point["name"] ?? "?") "
                            + "hit \(identifier.isEmpty ? "no Accessibility element" : identifier)"
                    )
                }
            }
        }

        issues.append(contentsOf: peerSpacingIssues(in: samples))
        return issues.sorted()
    }

    private static func peerSpacingIssues(
        in samples: [QuillCodeDesktopAccessibilityFrameSample]
    ) -> [String] {
        let samplesByCollisionScope = Dictionary(grouping: samples, by: \.collisionScope)
        return samplesByCollisionScope.flatMap { collisionScope, scopedSamples in
            var issues: [String] = []
            for lhsIndex in scopedSamples.indices {
                for rhsIndex in scopedSamples.index(after: lhsIndex)..<scopedSamples.endIndex {
                    let lhs = scopedSamples[lhsIndex]
                    let rhs = scopedSamples[rhsIndex]
                    guard lhs.resolvedIdentifier != rhs.resolvedIdentifier else { continue }
                    let overlap = lhs.frame.intersection(rhs.frame)
                    if !overlap.isNull, overlap.width > 1, overlap.height > 1 {
                        issues.append(
                            "\(lhs.contractID) and \(rhs.contractID) overlap in \(collisionScope) "
                                + "by \(rounded(overlap.width))x\(rounded(overlap.height))"
                        )
                        continue
                    }

                    let verticalOverlap = min(lhs.frame.maxY, rhs.frame.maxY) - max(lhs.frame.minY, rhs.frame.minY)
                    let horizontalOverlap = min(lhs.frame.maxX, rhs.frame.maxX) - max(lhs.frame.minX, rhs.frame.minX)
                    let horizontalGap = max(lhs.frame.minX, rhs.frame.minX) - min(lhs.frame.maxX, rhs.frame.maxX)
                    let verticalGap = max(lhs.frame.minY, rhs.frame.minY) - min(lhs.frame.maxY, rhs.frame.maxY)
                    let requiredClearance = CGFloat(max(lhs.requiredPeerClearance, rhs.requiredPeerClearance))
                    if verticalOverlap > 1,
                       horizontalGap >= 0,
                       horizontalGap < requiredClearance,
                       !allowsTightClearance(lhs, rhs, axis: .horizontal) {
                        issues.append(
                            "\(lhs.contractID) and \(rhs.contractID) have only \(rounded(horizontalGap)) horizontal clearance "
                                + "in \(collisionScope); expected \(rounded(requiredClearance))"
                        )
                    }
                    if horizontalOverlap > 1,
                       verticalGap >= 0,
                       verticalGap < requiredClearance,
                       !allowsTightClearance(lhs, rhs, axis: .vertical) {
                        issues.append(
                            "\(lhs.contractID) and \(rhs.contractID) have only \(rounded(verticalGap)) vertical clearance "
                                + "in \(collisionScope); expected \(rounded(requiredClearance))"
                        )
                    }
                }
            }
            return issues
        }
    }

    private enum PeerClearanceAxis {
        case horizontal
        case vertical
    }

    private static func allowsTightClearance(
        _ lhs: QuillCodeDesktopAccessibilityFrameSample,
        _ rhs: QuillCodeDesktopAccessibilityFrameSample,
        axis: PeerClearanceAxis
    ) -> Bool {
        if lhs.kind == QuillCodeNativeHitTargetKind.segmentedControl.rawValue
            || rhs.kind == QuillCodeNativeHitTargetKind.segmentedControl.rawValue {
            return true
        }
        if axis == .vertical {
            let rowKinds: Set<String> = [
                QuillCodeNativeHitTargetKind.fullRow.rawValue,
                QuillCodeNativeHitTargetKind.switchRow.rawValue
            ]
            return rowKinds.contains(lhs.kind) && rowKinds.contains(rhs.kind)
        }
        return false
    }

    private static func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
