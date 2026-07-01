import XCTest

final class ParityHTMLPrimitiveHitTargetGateTests: QuillCodeParityTestCase {
    func testHTMLButtonPrimitiveDefaultsToSharedHitTargetClass() throws {
        let primitivesText = try Self.appSourceText(
            named: "WorkspaceHTMLPrimitives.swift"
        )

        Self.assertSource(primitivesText, containsAll: [
            "classesWithDefaultHitTarget",
            "defaultKind: WorkspaceHTMLHitTargetKind = .text",
            "return trimmed + [defaultKind.className]",
            "static func summary(",
            "<summary\\(elementAttributes(",
        ])
    }

    func testHTMLPrimitivesExposeSemanticTargetVocabulary() throws {
        let primitivesText = try Self.appSourceText(
            named: "WorkspaceHTMLPrimitives.swift"
        )

        Self.assertSource(primitivesText, containsAll: [
            "enum WorkspaceHTMLHitTargetKind",
            "case icon",
            "case textEntry = \"text-entry\"",
            "case segmented",
            "case switchRow = \"switch-row\"",
            "case formAction = \"form-action\"",
            "case adjustable = \"adjustable\"",
            "var nativeKind: QuillCodeNativeHitTargetKind",
            "var className: String",
            "nativeKind.renderedClassName",
        ])
    }

    func testHTMLPrimitivesEmitSemanticTargetAttributes() throws {
        let primitivesText = try Self.appSourceText(
            named: "WorkspaceHTMLPrimitives.swift"
        )

        Self.assertSource(primitivesText, containsAll: [
            #"static let hitTargetKindAttributeName = "data-hit-target-kind""#,
            #"static let hitTargetActionAttributeName = "data-hit-target-action""#,
            #"static let hitTargetSourceAttributeName = "data-hit-target-source""#,
            "static func hitTargetKindAttribute(forClasses classes: [String])",
            "static func hitTargetAttributes(kind: WorkspaceHTMLHitTargetKind",
            "static func hitTargetAttributes(classes: [String])",
            "hitTargetKindByClass",
            ##"#"\#(hitTargetActionAttributeName)="\#(escape(kind.action))""#"##,
            ##"#"\#(hitTargetSourceAttributeName)="explicit""#"##,
            ##"parts.append(#"\#(hitTargetKindAttributeName)="\#(escape(hitTargetKind.rawValue))""#)"##,
            ##"parts.append(#"\#(hitTargetActionAttributeName)="\#(escape(hitTargetKind.action))""#)"##,
            ##"parts.append(#"\#(hitTargetSourceAttributeName)="explicit""#)"##,
        ])
    }

    func testHTMLPrimitivesRecognizeEverySharedTargetClass() throws {
        let primitivesText = try Self.appSourceText(
            named: "WorkspaceHTMLPrimitives.swift"
        )

        Self.assertSource(primitivesText, containsAll: [
            "private static func isHitTargetClass",
            "ownedHitTargetClass",
            "linkHitTargetClass",
            "textEntryHitTargetClass",
            "segmentedHitTargetClass",
            "switchRowHitTargetClass",
            "formActionHitTargetClass",
            "adjustableHitTargetClass",
        ])
    }
}
