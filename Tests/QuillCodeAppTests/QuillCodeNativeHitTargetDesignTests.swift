import XCTest
@testable import QuillCodeApp

@MainActor
final class QuillCodeNativeHitTargetDesignTests: QuillCodeNativeHitTargetAuditTestCase {
    func testDesignSystemHitTargetSpecsUseNativeSemantics() {
        let cases: [(spec: QuillCodeHitTargetSpec, kind: QuillCodeNativeHitTargetKind, action: QuillCodeNativeHitTargetAction)] = [
            (.icon(), .icon, .press),
            (.textButton(), .textButton, .press),
            (.formAction(), .formAction, .press),
            (.textEntry(), .textEntry, .textInput),
            (.segmentedControl(), .segmentedControl, .press),
            (.adjustableControl(), .adjustableControl, .adjust),
            (.link(), .link, .link),
            (.switchRow(), .switchRow, .press),
            (.ownedGesture(), .ownedGesture, .ownedGesture),
            (.fullRow(), .fullRow, .press),
            (.capsule(), .capsule, .press)
        ]

        XCTAssertEqual(Set(cases.map(\.kind)), Set(QuillCodeNativeHitTargetKind.allCases))
        for hitTargetCase in cases {
            XCTAssertEqual(hitTargetCase.spec.kind, hitTargetCase.kind)
            XCTAssertEqual(hitTargetCase.spec.action, hitTargetCase.action.rawValue)
            XCTAssertFalse(hitTargetCase.spec.kind.renderedKind.isEmpty)
            XCTAssertTrue(hitTargetCase.spec.kind.renderedClassName.hasPrefix("hit-target-"))
            XCTAssertEqual(hitTargetCase.spec.allowsNestedInteractiveChildren, hitTargetCase.kind.allowsNestedInteractiveChildren)
            XCTAssertEqual(hitTargetCase.spec.requiresUnblockedInterior, hitTargetCase.kind.requiresUnblockedInterior)
            XCTAssertEqual(hitTargetCase.spec.requiresTactileFeedback, hitTargetCase.kind.requiresTactileFeedback)
            XCTAssertEqual(hitTargetCase.spec.allowsTextSelection, hitTargetCase.kind.allowsTextSelection)
            XCTAssertGreaterThanOrEqual(hitTargetCase.spec.requiredMinWidth, QuillCodeMetrics.minimumHitTarget)
            XCTAssertGreaterThanOrEqual(hitTargetCase.spec.requiredMinHeight, QuillCodeMetrics.minimumHitTarget)
            XCTAssertGreaterThanOrEqual(hitTargetCase.spec.minHeight, QuillCodeMetrics.minimumHitTarget)
        }
    }

    func testRenderedHitTargetKindsBridgeToNativeSemantics() {
        let expectedNativeKinds: [WorkspaceHTMLHitTargetKind: QuillCodeNativeHitTargetKind] = [
            .icon: .icon,
            .text: .textButton,
            .textEntry: .textEntry,
            .segmented: .segmentedControl,
            .row: .fullRow,
            .switchRow: .switchRow,
            .capsule: .capsule,
            .formAction: .formAction,
            .adjustable: .adjustableControl,
            .link: .link,
            .owned: .ownedGesture
        ]

        XCTAssertEqual(Set(WorkspaceHTMLHitTargetKind.allCases), Set(expectedNativeKinds.keys))
        XCTAssertEqual(
            Set(WorkspaceHTMLHitTargetKind.allCases.map(\.nativeKind)),
            Set(QuillCodeNativeHitTargetKind.allCases),
            "Rendered and native click-target APIs should cover the same semantic vocabulary."
        )

        for kind in WorkspaceHTMLHitTargetKind.allCases {
            XCTAssertEqual(kind.nativeKind, expectedNativeKinds[kind], kind.rawValue)
            XCTAssertEqual(kind.rawValue, kind.nativeKind.renderedKind, kind.rawValue)
            XCTAssertEqual(kind.className, kind.nativeKind.renderedClassName, kind.rawValue)
            XCTAssertEqual(kind.action, kind.nativeKind.action.rawValue, kind.rawValue)
        }
    }

    func testDesignSystemHitTargetFactoriesClampTinyInputsToTheMinimumTarget() {
        let tinyTargets: [(name: String, spec: QuillCodeHitTargetSpec)] = [
            ("icon", .icon(size: 12)),
            ("text button", .textButton(minWidth: 12, minHeight: 12)),
            ("form action", .formAction(minWidth: 12, minHeight: 12)),
            ("text entry", .textEntry(minWidth: nil, minHeight: 12)),
            ("segmented control", .segmentedControl(minHeight: 12)),
            ("adjustable control", .adjustableControl(minHeight: 12)),
            ("link", .link(minWidth: nil, minHeight: 12)),
            ("switch row", .switchRow(minHeight: 12)),
            ("owned gesture", .ownedGesture(minHeight: 12)),
            ("full row", .fullRow(minHeight: 12)),
            ("capsule", .capsule(minWidth: nil, minHeight: 12))
        ]

        for target in tinyTargets {
            XCTAssertEqual(target.spec.requiredMinWidth, QuillCodeMetrics.minimumHitTarget, target.name)
            XCTAssertEqual(target.spec.requiredMinHeight, QuillCodeMetrics.minimumHitTarget, target.name)
            XCTAssertGreaterThanOrEqual(target.spec.minWidth ?? 0, QuillCodeMetrics.minimumHitTarget, target.name)
            XCTAssertGreaterThanOrEqual(target.spec.minHeight, QuillCodeMetrics.minimumHitTarget, target.name)
            if let width = target.spec.width {
                XCTAssertGreaterThanOrEqual(width, QuillCodeMetrics.minimumHitTarget, target.name)
            }
            if let height = target.spec.height {
                XCTAssertGreaterThanOrEqual(height, QuillCodeMetrics.minimumHitTarget, target.name)
            }
        }
    }
}
