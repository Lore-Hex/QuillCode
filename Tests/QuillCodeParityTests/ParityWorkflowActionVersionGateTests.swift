import XCTest

final class ParityWorkflowActionVersionGateTests: QuillCodeParityTestCase {
    func testWorkflowsUseCurrentOfficialArtifactActionMajors() throws {
        let expectations: [String: [String]] = [
            "ci.yml": ["actions/checkout@v7", "actions/upload-artifact@v7"],
            "download-builds.yml": [
                "actions/checkout@v7",
                "actions/upload-artifact@v7",
                "actions/download-artifact@v8"
            ],
            "live-trustedrouter-smoke.yml": [
                "actions/checkout@v7",
                "actions/upload-artifact@v7"
            ],
            "merge-train.yml": ["actions/checkout@v7"],
            "real-world-smoke.yml": [
                "actions/checkout@v7",
                "actions/upload-artifact@v7"
            ]
        ]

        for (fileName, actionReferences) in expectations {
            let workflow = try Self.workflowText(named: fileName)
            for actionReference in actionReferences {
                XCTAssertTrue(
                    workflow.contains(actionReference),
                    "\(fileName) must use \(actionReference)"
                )
            }
        }
    }

    func testWorkflowsDoNotReintroduceNode20ActionMajors() throws {
        let workflowDirectory = Self.packageRoot().appendingPathComponent(".github/workflows")
        let workflowURLs = try FileManager.default.contentsOfDirectory(
            at: workflowDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "yml" }

        for workflowURL in workflowURLs {
            let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
            XCTAssertFalse(
                workflow.contains("actions/checkout@v4")
                    || workflow.contains("actions/upload-artifact@v4")
                    || workflow.contains("actions/download-artifact@v4"),
                "\(workflowURL.lastPathComponent) reintroduced a Node 20 action major"
            )
        }
    }

    func testConfidentialCoworkSignerBuildsWorkspaceBeforeTesting() throws {
        let workflow = try Self.workflowText(named: "sign-tr-confidential-cowork.yml")
        let buildRange = try XCTUnwrap(workflow.range(of: "npm run build"))
        let testRange = try XCTUnwrap(workflow.range(of: "./test.sh"))

        XCTAssertLessThan(
            buildRange.lowerBound,
            testRange.lowerBound,
            "The signer must build workspace packages before tests resolve their dist exports"
        )
    }
}
