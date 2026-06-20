import XCTest

final class ParityGateTests: XCTestCase {
    func testQuillCodeAppHasNoLinuxConditionals() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            packageRoot.appendingPathComponent("Sources/QuillCodeApp"),
            packageRoot.appendingPathComponent("Sources/quill-code-desktop")
        ]
        let files = try sourceRoots.flatMap { root in
            try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "swift" }
        }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("#if os(Linux)"), "\(file.path) contains app-level Linux conditional")
            XCTAssertFalse(text.contains("#if linux"), "\(file.path) contains app-level Linux conditional")
        }
    }

    func testParityDocsExist() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in ["DECISIONS.md", "CODEX_RESEARCH.md", "CODEX_PARITY_MATRIX.md", "ROADMAP.md", "TEST_PLAN.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/\(name)").path), name)
        }
    }
}
