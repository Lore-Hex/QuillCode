import XCTest
@testable import QuillCodeApp

@MainActor
final class QuillCodeNativeHitTargetValidationTests: QuillCodeNativeHitTargetAuditTestCase {
    func testAuditReportRejectsBlankMetadataDuplicateIDsAndNarrowIcons() {
        let invalidContract = QuillCodeNativeHitTargetContract(
            id: "",
            family: .topBar,
            surface: "",
            label: "",
            kind: .icon,
            minWidth: nil,
            minHeight: 20,
            testID: "",
            commandID: "",
            source: ""
        )

        XCTAssertTrue(invalidContract.validationIssues.contains("hit target contract has an empty id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty surface label"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty accessible label"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty source"))
        XCTAssertEqual(invalidContract.collisionScope, "top-bar")
        XCTAssertTrue(invalidContract.validationIssues.contains(" icon target should declare an explicit minimum width"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" minHeight 20.0 is below 44.0"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty test id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty command id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" does not declare a stable test id, command id, or focus target"))

        let blankScopeContract = QuillCodeNativeHitTargetContract(
            id: "blank.scope",
            family: .topBar,
            surface: "Top bar",
            label: "More",
            kind: .icon,
            minWidth: 44,
            collisionScope: "",
            testID: "quillcode-more",
            source: "SwiftUI"
        )
        XCTAssertTrue(blankScopeContract.validationIssues.contains("blank.scope has an empty collision scope"))

        let report = QuillCodeNativeHitTargetAuditReport(
            minimumHitTarget: 44,
            minimumTargetClearance: 8,
            pressScale: 0.96,
            surfacePolicies: [
                QuillCodeNativeSurfaceTargetPolicy(family: .topBar, requiredKinds: [.icon])
            ],
            designSystemContracts: [],
            surfaceContracts: [invalidContract],
            clickProbes: [],
            missingDesignKinds: [],
            coveredSurfaceFamilies: [],
            missingSurfaceFamilies: [],
            missingRequiredSurfaceKinds: ["top-bar:icon"],
            coveredFocusTargets: [],
            missingRequiredFocusTargets: [],
            missingRequiredSurfaceActions: ["top-bar:press"],
            missingRequiredSurfaceFocusTargets: ["composer:composer.message"],
            unexpectedSurfaceKinds: ["top-bar:top-bar.overflow:textButton"],
            unexpectedSurfaceActions: ["top-bar:top-bar.overflow:link"],
            unexpectedSurfaceFocusTargets: ["composer:composer.input:composer.message"],
            missingRequiredCommandIDs: [],
            missingClickProbeContractIDs: ["top-bar.overflow"],
            clickProbeValidationIssues: ["top-bar.overflow click probe selector drift"],
            duplicateContractIDs: ["top-bar.overflow"],
            validationIssues: invalidContract.validationIssues
        )

        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.duplicateContractIDs, ["top-bar.overflow"])
        XCTAssertEqual(report.dictionary["missingRequiredSurfaceKinds"] as? [String], ["top-bar:icon"])
        XCTAssertEqual(report.dictionary["missingRequiredSurfaceActions"] as? [String], ["top-bar:press"])
        XCTAssertEqual(report.dictionary["missingRequiredSurfaceFocusTargets"] as? [String], ["composer:composer.message"])
        XCTAssertEqual(report.dictionary["unexpectedSurfaceKinds"] as? [String], ["top-bar:top-bar.overflow:textButton"])
        XCTAssertEqual(report.dictionary["unexpectedSurfaceActions"] as? [String], ["top-bar:top-bar.overflow:link"])
        XCTAssertEqual(report.dictionary["unexpectedSurfaceFocusTargets"] as? [String], ["composer:composer.input:composer.message"])
        XCTAssertEqual(report.dictionary["missingClickProbeContractIDs"] as? [String], ["top-bar.overflow"])
        XCTAssertEqual(report.dictionary["clickProbeValidationIssues"] as? [String], ["top-bar.overflow click probe selector drift"])
        XCTAssertEqual(report.dictionary["duplicateContractIDs"] as? [String], ["top-bar.overflow"])
        XCTAssertEqual((invalidContract.dictionary["testID"] as? String), "")
        XCTAssertEqual((invalidContract.dictionary["commandID"] as? String), "")
        XCTAssertEqual((invalidContract.dictionary["collisionScope"] as? String), "top-bar")
    }

    func testClickProbeValidationRejectsSelectorSemanticAndGeometryDrift() {
        let contract = QuillCodeNativeHitTargetContract(
            id: "composer.send",
            family: .composer,
            surface: "Composer",
            label: "Send message",
            kind: .icon,
            minWidth: 44,
            testID: "quillcode-send-button",
            source: "SwiftUI"
        )
        let probe = QuillCodeNativeHitTargetProbe(
            contractID: "composer.send",
            family: .topBar,
            label: "Send message",
            kind: .textButton,
            action: .link,
            allowsNestedInteractiveChildren: true,
            requiresUnblockedInterior: false,
            requiresTactileFeedback: false,
            allowsTextSelection: true,
            selectorKind: .testID,
            selector: "quillcode-wrong-button",
            requiredMinWidth: 20,
            requiredMinHeight: 20,
            requiredPeerClearance: 2,
            samplePoints: [
                QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5),
                QuillCodeNativeHitTargetProbePoint(name: "leading-interior", x: 0.2, y: 0.5),
                QuillCodeNativeHitTargetProbePoint(name: "", x: 0.5, y: 0.5),
                QuillCodeNativeHitTargetProbePoint(name: "outside", x: 1.2, y: 0.5)
            ]
        )

        let issues = QuillCodeNativeHitTargetAudit.validateClickProbes(
            contracts: [contract],
            probes: [probe]
        )

        XCTAssertTrue(issues.contains("composer.send click probe selector quillcode-wrong-button does not match test-id contract selector"))
        XCTAssertTrue(issues.contains("composer.send click probe kind textButton does not match icon"))
        XCTAssertTrue(issues.contains("composer.send click probe action link does not match press"))
        XCTAssertTrue(issues.contains("composer.send click probe family top-bar does not match composer"))
        XCTAssertTrue(issues.contains("composer.send click probe collision scope does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe nested-child policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe interior-blocking policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe tactile-feedback policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe text-selection policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredMinWidth 20.0 is below 44.0"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredMinHeight 20.0 is below 44.0"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredPeerClearance 2.0 is below 8.0"))
        XCTAssertTrue(issues.contains("composer.send click probe has an unnamed sample point"))
        XCTAssertTrue(issues.contains("composer.send click probe has unknown sample point outside"))
        XCTAssertTrue(issues.contains("composer.send click probe sample point leading-interior has unexpected coordinates"))
        XCTAssertTrue(issues.contains("composer.send click probe sample point outside is outside the target interior"))
        XCTAssertTrue(issues.contains("composer.send click probe is missing sample points: bottom-edge, bottom-interior, leading-edge, top-edge, top-interior, trailing-edge, trailing-interior"))
    }
}
