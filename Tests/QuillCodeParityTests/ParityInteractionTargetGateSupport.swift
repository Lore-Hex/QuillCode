import XCTest

extension QuillCodeParityTestCase {
    static func assertInteractionTargetText(
        _ source: String,
        containsAll expected: [String],
        reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let missing = expected.filter { !source.contains($0) }
        XCTAssertTrue(
            missing.isEmpty,
            "\(reason)\nMissing:\n\(missing.joined(separator: "\n"))",
            file: file,
            line: line
        )
    }

    static func assertInteractionTargetText(
        _ source: String,
        containsAny expected: [String],
        reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            expected.contains { source.contains($0) },
            "\(reason)\nExpected one of:\n\(expected.joined(separator: "\n"))",
            file: file,
            line: line
        )
    }

    static func renderedHarnessText() throws -> String {
        try String(
            contentsOf: packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
    }

    static func playwrightInteractionAuditContractText() throws -> String {
        try playwrightInteractionAuditText(names: [
            "interaction-audit-contracts.ts",
            "interaction-audit-report.ts",
            "interaction-audit-targets.ts",
        ])
    }

    static func playwrightInteractionAuditText(names: [String]) throws -> String {
        let testRoot = packageRoot().appendingPathComponent("E2E/playwright/tests")
        return try names
            .map { name in
                try String(contentsOf: testRoot.appendingPathComponent(name), encoding: .utf8)
            }
            .joined(separator: "\n")
    }
}
