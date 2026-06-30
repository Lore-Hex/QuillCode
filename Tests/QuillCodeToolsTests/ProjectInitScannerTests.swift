import XCTest
@testable import QuillCodeTools

final class ProjectInitScannerTests: XCTestCase {
    private func scanRoot(withFiles files: [String], directories: [String] = []) throws -> ProjectInitScaffolder.Signals {
        let root = try makeTempDirectory()
        for file in files {
            try "x".write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        for directory in directories {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        return ProjectInitScanner.scan(root: root)
    }

    func testDetectsLanguagesFromRootMarkers() throws {
        XCTAssertEqual(try scanRoot(withFiles: ["Package.swift"]).languages, [.swift])
        XCTAssertEqual(try scanRoot(withFiles: ["package.json"]).languages, [.node])
        XCTAssertEqual(try scanRoot(withFiles: ["Cargo.toml"]).languages, [.rust])
        XCTAssertEqual(try scanRoot(withFiles: ["go.mod"]).languages, [.go])
        XCTAssertEqual(try scanRoot(withFiles: ["pyproject.toml"]).languages, [.python])
        XCTAssertEqual(try scanRoot(withFiles: ["requirements.txt"]).languages, [.python])
    }

    func testDeDupesPythonMarkersAndDetectsMakefile() throws {
        let signals = try scanRoot(withFiles: ["pyproject.toml", "requirements.txt", "setup.py", "Makefile"])
        XCTAssertEqual(signals.languages, [.python])
        XCTAssertTrue(signals.hasMakefile)
    }

    func testCollectsTopLevelDirectoriesAndSkipsBuildArtifacts() throws {
        let signals = try scanRoot(withFiles: ["Package.swift"], directories: ["Sources", "Tests", ".build", "node_modules"])
        XCTAssertEqual(signals.topLevelDirectories, ["Sources", "Tests"])
    }

    func testEmptyDirectoryHasNoSignals() throws {
        let signals = try scanRoot(withFiles: [])
        XCTAssertTrue(signals.languages.isEmpty)
        XCTAssertFalse(signals.hasMakefile)
    }
}
