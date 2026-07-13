import XCTest

final class ParityPermissionWildcardGateTests: QuillCodeParityTestCase {
    func testPermissionGlobstarDirectorySemanticsStaySegmentBoundedAndOracleBacked() throws {
        let matcher = try Self.safetySourceText(named: "PermissionWildcardPattern.swift")
        let tests = try Self.safetyTestSourceText(named: "PermissionWildcardPatternTests.swift")

        Self.assertSource(matcher, contains: "case directoryBoundary")
        Self.assertSource(matcher, contains: "case directorySegment")
        Self.assertSource(matcher, contains: "mergeDirectoryBoundaryToSegment")
        Self.assertSource(matcher, contains: "mergeDirectorySegmentToBoundary")
        Self.assertSource(
            tests,
            contains: "testGlobstarDirectoryMatchesZeroOrMoreCompleteSegments"
        )
        Self.assertSource(
            tests,
            contains: "testGlobstarDirectoryDoesNotConsumePartialSegments"
        )
        Self.assertSource(
            tests,
            contains: "testMatcherAgreesWithRecursiveReferenceOracleAcrossGeneratedCorpus"
        )
        Self.assertSource(
            tests,
            contains: "testPermissionTableDenyCoversRootAndNestedSecretFiles"
        )
    }
}
