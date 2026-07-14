import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceAgentImportIntegrationTests: XCTestCase {
    func testImportPersistsProjectsChatsContextAndReceipt() async throws {
        let fixture = try WorkspaceAgentImportFixture(testCase: self)
        let projectStore = JSONProjectStore(fileURL: fixture.paths.projectsFile)
        let threadStore = JSONThreadStore(directory: fixture.paths.threadsDirectory)
        let importer = ClaudeCodeAgentImporter(
            sourceHomeDirectory: fixture.sourceHome,
            destinationPaths: fixture.paths
        )
        let model = QuillCodeWorkspaceModel(
            threadStore: threadStore,
            projectStore: projectStore,
            agentImporter: importer
        )

        let preview = await model.discoverAgentImport()
        let outcome = await model.performAgentImport(AgentImportSelection(
            source: .claudeCode,
            candidateIDs: preview.defaultCandidateIDs,
            projectPaths: preview.defaultProjectPaths
        ))

        XCTAssertGreaterThan(outcome.importedCount, 0, outcome.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(model.root.projects.map(\.path), [fixture.project.path])
        XCTAssertEqual(model.root.threads.count, 1)
        XCTAssertEqual(model.root.threads.first?.messages.map(\.content), ["Continue this work", "Ready."])
        XCTAssertFalse(model.root.projects[0].instructions.isEmpty)
        XCTAssertEqual(try projectStore.load().map(\.path), [fixture.project.path])
        XCTAssertEqual(try threadStore.list().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.agentImportReceiptFile.path))

        let refreshed = await model.discoverAgentImport()
        XCTAssertTrue(refreshed.selectableCandidates.isEmpty)
    }

    func testReceiptFailureRollsBackWorkspaceAndCreatedArtifacts() async throws {
        let fixture = try WorkspaceAgentImportFixture(testCase: self)
        let projectStore = JSONProjectStore(fileURL: fixture.paths.projectsFile)
        let threadStore = JSONThreadStore(directory: fixture.paths.threadsDirectory)
        let importer = ClaudeCodeAgentImporter(
            sourceHomeDirectory: fixture.sourceHome,
            destinationPaths: fixture.paths
        )
        let model = QuillCodeWorkspaceModel(
            threadStore: threadStore,
            projectStore: projectStore,
            agentImporter: importer
        )
        let preview = await model.discoverAgentImport()
        try FileManager.default.removeItem(at: fixture.paths.importsDirectory)
        try Data("block receipt directory".utf8).write(to: fixture.paths.importsDirectory)

        let outcome = await model.performAgentImport(AgentImportSelection(
            source: .claudeCode,
            candidateIDs: preview.defaultCandidateIDs,
            projectPaths: preview.defaultProjectPaths
        ))

        XCTAssertTrue(outcome.diagnostics.contains { $0.contains("could not be committed") })
        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertTrue(model.root.threads.isEmpty)
        XCTAssertTrue(try projectStore.load().isEmpty)
        XCTAssertTrue(try threadStore.list().isEmpty)
        XCTAssertTrue(try regularFiles(inside: fixture.project).filter {
            $0.path.contains("/.quillcode/")
        }.isEmpty)
    }

    private func regularFiles(inside root: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ))
        return try enumerator.compactMap { value in
            let url = try XCTUnwrap(value as? URL)
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true ? url : nil
        }
    }
}

private struct WorkspaceAgentImportFixture {
    let sourceHome: URL
    let project: URL
    let paths: QuillCodePaths

    init(testCase: XCTestCase) throws {
        sourceHome = try testCase.makeQuillCodeTestDirectory()
        project = try testCase.makeQuillCodeTestDirectory().appendingPathComponent("imported-project")
        paths = QuillCodePaths(home: try testCase.makeQuillCodeTestDirectory().appendingPathComponent(".quillcode"))
        try paths.ensure()
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let claude = sourceHome.appendingPathComponent(".claude")
        let transcriptDirectory = claude.appendingPathComponent("projects/imported-project")
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        try Data("Always run focused tests.".utf8).write(to: claude.appendingPathComponent("CLAUDE.md"))
        try JSONSerialization.data(
            withJSONObject: ["projects": [project.path: ["lastCost": 0]]],
            options: [.sortedKeys]
        ).write(to: sourceHome.appendingPathComponent(".claude.json"))
        let timestamp = "2027-01-15T08:00:00Z"
        let rows: [[String: Any]] = [
            [
                "sessionId": "workspace-session", "cwd": project.path, "type": "user", "timestamp": timestamp,
                "message": ["role": "user", "content": "Continue this work"]
            ],
            [
                "sessionId": "workspace-session", "cwd": project.path, "type": "assistant", "timestamp": timestamp,
                "message": ["role": "assistant", "content": "Ready."]
            ]
        ]
        let transcript = transcriptDirectory.appendingPathComponent("workspace-session.jsonl")
        let text = try rows.map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self)
        }.joined(separator: "\n")
        try Data(text.utf8).write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: transcript.path)
    }
}
