import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceContextResolverTests: XCTestCase {
    func testResolvesInstructionsForKnownProjectOnly() {
        let targetID = UUID()
        let otherID = UUID()
        let resolver = WorkspaceContextResolver(
            projects: [
                Self.project(id: targetID, instructionTitle: "Target"),
                Self.project(id: otherID, instructionTitle: "Other")
            ],
            globalMemories: [],
            selectedProject: nil
        )

        XCTAssertEqual(resolver.instructions(for: targetID).map(\.title), ["Target"])
        XCTAssertEqual(resolver.instructions(for: otherID).map(\.title), ["Other"])
        XCTAssertEqual(resolver.instructions(for: UUID()), [])
        XCTAssertEqual(resolver.instructions(for: Optional<UUID>.none), [])
    }

    func testMergesGlobalMemoriesBeforeProjectMemories() {
        let projectID = UUID()
        let resolver = WorkspaceContextResolver(
            projects: [
                Self.project(id: projectID, memoryTitle: "Project preference")
            ],
            globalMemories: [
                Self.memory(id: "global-profile", scope: .global, title: "Global profile")
            ],
            selectedProject: nil
        )

        XCTAssertEqual(
            resolver.memoryNotes(for: projectID).map(\.title),
            ["Global profile", "Project preference"]
        )
        XCTAssertEqual(
            resolver.memoryNotes(for: UUID()).map(\.title),
            ["Global profile"]
        )
    }

    func testResolvesSelectedLocalActionByExactID() {
        let action = Self.localAction(
            id: "local-env:.quillcode/actions/test.sh",
            title: "Run Tests",
            relativePath: ".quillcode/actions/test.sh"
        )
        let resolver = WorkspaceContextResolver(
            projects: [],
            globalMemories: [],
            selectedProject: Self.project(localActions: [action])
        )

        XCTAssertEqual(resolver.selectedLocalAction(withID: action.id)?.title, "Run Tests")
        XCTAssertNil(resolver.selectedLocalAction(withID: "missing"))
    }

    func testMatchesSelectedLocalActionByTitlePathAndNormalizedAliases() {
        let action = Self.localAction(
            id: "local-env:.quillcode/actions/build-release.sh",
            title: "Build Release",
            relativePath: ".quillcode/actions/build-release.sh"
        )
        let resolver = WorkspaceContextResolver(
            projects: [],
            globalMemories: [],
            selectedProject: Self.project(localActions: [action])
        )

        XCTAssertEqual(resolver.selectedLocalAction(matching: "build release")?.id, action.id)
        XCTAssertEqual(resolver.selectedLocalAction(matching: "BUILD RELEASE")?.id, action.id)
        XCTAssertEqual(resolver.selectedLocalAction(matching: ".quillcode/actions/build-release.sh")?.id, action.id)
        XCTAssertEqual(resolver.selectedLocalAction(matching: "buildrelease")?.id, action.id)
        XCTAssertNil(resolver.selectedLocalAction(matching: "ship release"))
    }

    func testNoSelectedProjectMeansNoLocalActionMatch() {
        let resolver = WorkspaceContextResolver(
            projects: [],
            globalMemories: [],
            selectedProject: nil
        )

        XCTAssertNil(resolver.selectedLocalAction(withID: "local-env:.quillcode/actions/test.sh"))
        XCTAssertNil(resolver.selectedLocalAction(matching: "test"))
    }

    private static func project(
        id: UUID = UUID(),
        instructionTitle: String? = nil,
        memoryTitle: String? = nil,
        localActions: [LocalEnvironmentAction] = []
    ) -> ProjectRef {
        ProjectRef(
            id: id,
            name: "Project",
            path: "/tmp/project-\(id.uuidString)",
            instructions: instructionTitle.map {
                [ProjectInstruction(
                    path: "AGENTS.md",
                    title: $0,
                    content: "Instruction",
                    byteCount: 11
                )]
            } ?? [],
            localActions: localActions,
            memories: memoryTitle.map {
                [Self.memory(id: "project-\(id.uuidString)", scope: .project, title: $0)]
            } ?? []
        )
    }

    private static func localAction(
        id: String,
        title: String,
        relativePath: String
    ) -> LocalEnvironmentAction {
        LocalEnvironmentAction(
            id: id,
            title: title,
            relativePath: relativePath,
            command: "bash \(relativePath)"
        )
    }

    private static func memory(id: String, scope: MemoryScope, title: String) -> MemoryNote {
        MemoryNote(
            id: id,
            scope: scope,
            title: title,
            content: "Remember this",
            relativePath: "\(id).md",
            byteCount: 13
        )
    }
}
