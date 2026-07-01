import XCTest

extension QuillCodeParityTestCase {
    func nativeSourceAuditViolations(
        for source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String] {
        let swiftFile = try makeTemporarySwiftFile(source)
        return try SwiftSourceInteractionTargetAudit(packageRoot: swiftFile.deletingLastPathComponent())
            .violations(in: [swiftFile])
    }

    func assertNoNativeSourceAuditViolations(
        for source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try nativeSourceAuditViolations(for: source, file: file, line: line),
            [],
            file: file,
            line: line
        )
    }

    func assertNativeSourceAuditContains(
        _ expectedFragment: String,
        in source: String,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let violations = try nativeSourceAuditViolations(for: source, file: file, line: line)
        XCTAssertTrue(
            violations.contains { $0.contains(expectedFragment) },
            message,
            file: file,
            line: line
        )
    }

    func assertNativeSourceAuditViolationCount(
        containing expectedFragment: String,
        in source: String,
        equals expectedCount: Int,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let violations = try nativeSourceAuditViolations(for: source, file: file, line: line)
        XCTAssertEqual(
            violations.filter { $0.contains(expectedFragment) }.count,
            expectedCount,
            message,
            file: file,
            line: line
        )
    }
}
