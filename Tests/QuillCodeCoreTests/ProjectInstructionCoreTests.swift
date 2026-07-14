import Foundation
import XCTest
@testable import QuillCodeCore

final class ProjectInstructionCoreTests: XCTestCase {
    func testProjectInstructionDiagnosticResolutionsNormalizeAndDeduplicate() throws {
        var project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            instructionDiagnosticResolutions: [
                ProjectInstructionDiagnosticResolution(
                    diagnosticID: " instruction-conflict ",
                    updatedAt: Date(timeIntervalSince1970: 10)
                ),
                ProjectInstructionDiagnosticResolution(
                    diagnosticID: "instruction-conflict",
                    updatedAt: Date(timeIntervalSince1970: 20)
                ),
                ProjectInstructionDiagnosticResolution(
                    diagnosticID: " ",
                    updatedAt: Date(timeIntervalSince1970: 30)
                )
            ]
        )

        XCTAssertEqual(project.instructionDiagnosticResolutions.map(\.diagnosticID), ["instruction-conflict"])
        XCTAssertEqual(project.instructionDiagnosticResolutions.map(\.updatedAt), [Date(timeIntervalSince1970: 20)])
        XCTAssertEqual(project.dismissedInstructionDiagnosticIDs, ["instruction-conflict"])
        XCTAssertEqual(project.resolvedInstructionDiagnosticIDs, [])

        XCTAssertFalse(project.dismissInstructionDiagnostic(id: "instruction-conflict", at: Date(timeIntervalSince1970: 20)))
        XCTAssertFalse(project.dismissInstructionDiagnostic(id: "instruction-conflict", at: Date(timeIntervalSince1970: 40)))
        XCTAssertTrue(project.dismissInstructionDiagnostic(id: "new-conflict", at: Date(timeIntervalSince1970: 40)))
        XCTAssertTrue(project.resolveInstructionDiagnostic(id: "instruction-conflict", at: Date(timeIntervalSince1970: 60)))
        XCTAssertFalse(project.resolveInstructionDiagnostic(id: "instruction-conflict", at: Date(timeIntervalSince1970: 80)))
        XCTAssertEqual(project.instructionDiagnosticResolutions.map(\.diagnosticID), ["instruction-conflict", "new-conflict"])
        XCTAssertEqual(
            project.instructionDiagnosticResolutions.map(\.updatedAt),
            [Date(timeIntervalSince1970: 60), Date(timeIntervalSince1970: 40)]
        )
        XCTAssertEqual(project.dismissedInstructionDiagnosticIDs, ["new-conflict"])
        XCTAssertEqual(project.resolvedInstructionDiagnosticIDs, ["instruction-conflict"])
    }

    func testProjectInstructionDerivesScopedApplicabilityFromPath() throws {
        XCTAssertEqual(ProjectInstruction.scopePath(for: "AGENTS.md"), ".")
        XCTAssertEqual(ProjectInstruction.scopePath(for: ".quillcode/rules.md"), ".")
        XCTAssertEqual(ProjectInstruction.scopePath(for: ".quillcode/rules/imported.md"), ".")
        XCTAssertEqual(ProjectInstruction.scopePath(for: "Sources/.quillcode/rules/imported.md"), "Sources")
        XCTAssertEqual(ProjectInstruction.scopePath(for: "Sources/Feature/AGENTS.md"), "Sources/Feature")
        XCTAssertEqual(ProjectInstruction.scopePath(for: "Sources/Feature/.quillcode/rules.md"), "Sources/Feature")
        XCTAssertEqual(ProjectInstruction.scopePath(for: "Sources/Feature/.quillcode/instructions.md"), "Sources/Feature")

        let instruction = ProjectInstruction(
            path: "Sources/Feature/AGENTS.md",
            title: "Feature rules",
            content: "Prefer feature tests.",
            byteCount: 21
        )

        XCTAssertEqual(instruction.scopePath, "Sources/Feature")
        XCTAssertEqual(instruction.scopeLabel, "Sources/Feature/**")
        XCTAssertEqual(ProjectInstruction.scopeLabel(for: "."), "whole project")
        XCTAssertEqual(ProjectInstruction.scopeLabel(for: "Sources"), "Sources/**")
    }

    func testProjectInstructionDecodesOlderPayloadWithoutScopePath() throws {
        let instruction = try JSONHelpers.decode(ProjectInstruction.self, from: """
        {
          "path": "Sources/Feature/.quillcode/rules.md",
          "title": "Feature rules",
          "content": "Prefer feature tests.",
          "byteCount": 21,
          "wasTruncated": false
        }
        """)

        XCTAssertEqual(instruction.scopePath, "Sources/Feature")
        XCTAssertEqual(instruction.scopeLabel, "Sources/Feature/**")
    }
}
