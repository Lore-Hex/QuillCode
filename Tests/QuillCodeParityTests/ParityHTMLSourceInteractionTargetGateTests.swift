import XCTest

final class ParityHTMLSourceInteractionTargetGateTests: QuillCodeParityTestCase {
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

        XCTAssertEqual(violations, [])
    }

    func testRenderedHTMLPrimitiveCallSitesDeclareExplicitHitTargetKinds() throws {
        let appFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            .filter { $0.lastPathComponent != "WorkspaceHTMLPrimitives.swift" }
        let violations = try HTMLPrimitiveHitTargetKindAudit(
            packageRoot: Self.packageRoot()
        )
        .violations(in: appFiles)

        XCTAssertEqual(violations, [])
    }

    func testHTMLSourceAuditRequiresSemanticKindForRawSharedTargets() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum BadHTMLRenderer {
            func render() -> String {
                #"<input class="\#(WorkspaceHTMLPrimitives.textEntryHitTargetClass)">"#
            }
        }
        """##)

        let violations = try HTMLSourceInteractionTargetAudit(
            packageRoot: file.deletingLastPathComponent()
        )
        .violations(in: [file])
        let expected = "shared hit-target class without full semantic data-hit-target-kind"

        XCTAssertTrue(violations.contains { $0.contains(expected) })
    }

    func testHTMLSourceAuditAcceptsRawSharedTargetsWithSemanticKind() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum GoodHTMLRenderer {
            func render() -> String {
                #"<input\#(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry))>"#
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
