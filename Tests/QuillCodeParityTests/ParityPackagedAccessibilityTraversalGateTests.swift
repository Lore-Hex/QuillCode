import XCTest

final class ParityPackagedAccessibilityTraversalGateTests: QuillCodeParityTestCase {
    func testPackagedAccessibilityReadinessUsesCollisionSafeTargetedTraversal() throws {
        let tree = try Self.desktopSourceText(
            named: "QuillCodeDesktopAccessibilityTree.swift"
        )
        let sampler = try Self.desktopSourceText(
            named: "QuillCodeDesktopAccessibilityElementSetSampler.swift"
        )
        let verifier = try Self.desktopSourceText(
            named: "QuillCodeDesktopAccessibilityInteractionVerifier.swift"
        )

        Self.assertSource(tree, containsAll: [
            "struct QuillCodeDesktopAccessibilityElementIdentity: Hashable",
            "CFEqual(lhs.element, rhs.element)",
            "matchingIdentifiers identifiers: Set<String>",
            "identifiers.contains(identifier)",
            "snapshot.frameArea > 0",
            "matchedIdentifiers == identifiers"
        ])
        Self.assertSource(tree, excludes: "Set<CFHashCode>")
        Self.assertSource(sampler, contains: "var sampleCount: Int")
        Self.assertSource(verifier, containsAll: [
            "matchingIdentifiers:",
            "targetedSampleDescription",
            "count == 1 ? \"sample\" : \"samples\"",
            "sample.missingIdentifiers.sorted()"
        ])
    }
}
