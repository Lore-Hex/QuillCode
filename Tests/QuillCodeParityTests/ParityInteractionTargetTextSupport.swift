import Foundation

enum ParityInteractionTargetTextSupport {
    static func auditText(packageRoot: URL) throws -> String {
        try joinedPlaywrightText(
            packageRoot: packageRoot,
            names: [
                "interaction-audit-contracts.ts",
                "interaction-audit-report.ts",
                "interaction-audit-targets.ts",
            ]
        )
    }

    static func specText(packageRoot: URL, names: [String]) throws -> String {
        try joinedPlaywrightText(packageRoot: packageRoot, names: names)
    }

    static func harnessText(packageRoot: URL) throws -> String {
        try String(
            contentsOf: packageRoot
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
    }

    private static func joinedPlaywrightText(
        packageRoot: URL,
        names: [String]
    ) throws -> String {
        let testRoot = packageRoot.appendingPathComponent("E2E/playwright/tests")
        return try names
            .map { name in
                try String(contentsOf: testRoot.appendingPathComponent(name), encoding: .utf8)
            }
            .joined(separator: "\n")
    }
}
