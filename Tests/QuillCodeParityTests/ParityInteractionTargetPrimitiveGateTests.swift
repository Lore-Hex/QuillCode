import XCTest

final class ParityInteractionTargetPrimitiveGateTests: QuillCodeParityTestCase {
    func testHTMLButtonPrimitiveDefaultsToSharedHitTargetClass() throws {
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")

        Self.assertInteractionTargetText(
            primitivesText,
            containsAll: [
                "classesWithDefaultHitTarget",
                "defaultKind: WorkspaceHTMLHitTargetKind = .text",
                "return trimmed + [defaultKind.className]",
                "enum WorkspaceHTMLHitTargetKind",
                "case icon",
                "case textEntry = \"text-entry\"",
                "case segmented",
                "case switchRow = \"switch-row\"",
                "case formAction = \"form-action\"",
                "case adjustable = \"adjustable\"",
                "var nativeKind: QuillCodeNativeHitTargetKind",
                "var className: String",
            ],
            reason: "HTML primitives should declare semantic hit-target vocabulary."
        )
        Self.assertInteractionTargetText(
            primitivesText,
            containsAll: [
                #"static let hitTargetKindAttributeName = "data-hit-target-kind""#,
                #"static let hitTargetActionAttributeName = "data-hit-target-action""#,
                #"static let hitTargetSourceAttributeName = "data-hit-target-source""#,
                "static func hitTargetKindAttribute(forClasses classes: [String])",
                "static func hitTargetAttributes(kind: WorkspaceHTMLHitTargetKind",
                "static func hitTargetAttributes(classes: [String])",
                "hitTargetKindByClass",
            ],
            reason: "HTML primitives should emit auditable kind/action/source metadata."
        )
        Self.assertInteractionTargetText(
            primitivesText,
            containsAll: [
                ##"#"\#(hitTargetActionAttributeName)="\#(escape(kind.action))""#"##,
                ##"#"\#(hitTargetSourceAttributeName)="explicit""#"##,
                ##"parts.append(#"\#(hitTargetKindAttributeName)="\#(escape(hitTargetKind.rawValue))""#)"##,
                ##"parts.append(#"\#(hitTargetActionAttributeName)="\#(escape(hitTargetKind.action))""#)"##,
                ##"parts.append(#"\#(hitTargetSourceAttributeName)="explicit""#)"##,
            ],
            reason: "Primitive-generated attributes should use explicit semantic values."
        )
        Self.assertInteractionTargetText(
            primitivesText,
            containsAll: [
                "static func summary(",
                "<summary\\(elementAttributes(",
                "private static func isHitTargetClass",
                "ownedHitTargetClass",
                "linkHitTargetClass",
                "textEntryHitTargetClass",
                "segmentedHitTargetClass",
                "switchRowHitTargetClass",
                "formActionHitTargetClass",
                "adjustableHitTargetClass",
                "nativeKind.renderedClassName",
            ],
            reason: "HTML summaries and target-class recognition should stay centralized."
        )
    }

    func testHTMLRenderersUseSharedClickTargetPrimitives() throws {
        let rendererFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            .filter {
                $0.lastPathComponent.hasPrefix("WorkspaceHTML")
                    && $0.lastPathComponent != "WorkspaceHTMLPrimitives.swift"
            }
        let violations = try HTMLSourceInteractionTargetAudit(
            packageRoot: Self.packageRoot()
        )
        .violations(in: rendererFiles)

        XCTAssertTrue(
            violations.isEmpty,
            """
            Generated HTML controls must route through shared click-target primitives.
            \(violations.joined(separator: "\n"))
            """
        )
    }

    func testRenderedHTMLPrimitiveCallSitesDeclareExplicitHitTargetKinds() throws {
        let appFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            .filter { $0.lastPathComponent != "WorkspaceHTMLPrimitives.swift" }
        let violations = try HTMLPrimitiveHitTargetKindAudit(packageRoot: Self.packageRoot())
            .violations(in: appFiles)

        XCTAssertTrue(
            violations.isEmpty,
            """
            Rendered HTML primitive call sites must choose a semantic click-target kind.
            \(violations.joined(separator: "\n"))
            """
        )
    }

    func testHTMLSourceAuditRequiresSemanticKindForRawSharedTargets() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum BadHTMLRenderer {
            func render() -> String {
                #"""
                <input class="\#(WorkspaceHTMLPrimitives.textEntryHitTargetClass)" aria-label="Search">
                """#
            }
        }
        """##)

        let violations = try HTMLSourceInteractionTargetAudit(
            packageRoot: file.deletingLastPathComponent()
        )
        .violations(in: [file])

        XCTAssertTrue(
            violations.contains {
                $0.contains("shared hit-target class without full semantic data-hit-target-kind")
            },
            "Raw shared hit-target classes should also declare the full semantic contract."
        )
    }

    func testHTMLSourceAuditAcceptsRawSharedTargetsWithSemanticKind() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum GoodHTMLRenderer {
            func render() -> String {
                #"""
                <input\#(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) aria-label="Search">
                """#
            }
        }
        """##)

        let violations = try HTMLSourceInteractionTargetAudit(
            packageRoot: file.deletingLastPathComponent()
        )
        .violations(in: [file])

        XCTAssertEqual(violations, [])
    }
}
