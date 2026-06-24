import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceEnvironmentSlashCommandPlannerTests: XCTestCase {
    func testEmptyQueryListsAvailableActions() {
        let plan = WorkspaceEnvironmentSlashCommandPlanner.plan(
            query: nil,
            userText: "/env",
            actions: [
                Self.action(
                    id: "local-env:.quillcode/actions/bootstrap.sh",
                    title: "Bootstrap",
                    relativePath: ".quillcode/actions/bootstrap.sh"
                )
            ]
        )

        guard case .transcript(let transcript) = plan else {
            return XCTFail("Expected transcript plan")
        }
        XCTAssertEqual(transcript.title, "Local environment actions")
        XCTAssertTrue(transcript.assistantText.contains("/env Bootstrap"))
    }

    func testBlankQueryListsAvailableActions() {
        let plan = WorkspaceEnvironmentSlashCommandPlanner.plan(
            query: " \n\t ",
            userText: "/env",
            actions: []
        )

        XCTAssertEqual(
            plan,
            .transcript(WorkspaceSlashCommandTranscriptPlanner.environmentActions(userText: "/env", actions: []))
        )
    }

    func testMatchingQueryRunsActionByID() {
        let action = Self.action(
            id: "local-env:.quillcode/actions/prepare.sh",
            title: "Prepare Workspace",
            relativePath: ".quillcode/actions/prepare.sh"
        )

        XCTAssertEqual(
            WorkspaceEnvironmentSlashCommandPlanner.plan(
                query: "prepare workspace",
                userText: "/env prepare workspace",
                actions: [action]
            ),
            .runAction(id: action.id)
        )
    }

    func testMissingQueryReturnsNotFoundTranscriptWithTrimmedQuery() {
        let plan = WorkspaceEnvironmentSlashCommandPlanner.plan(
            query: "  deploy  ",
            userText: "/env deploy",
            actions: []
        )

        XCTAssertEqual(
            plan,
            .transcript(WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound(
                userText: "/env deploy",
                query: "deploy"
            ))
        )
    }

    private static func action(id: String, title: String, relativePath: String) -> LocalEnvironmentAction {
        LocalEnvironmentAction(
            id: id,
            title: title,
            relativePath: relativePath,
            command: "bash \(relativePath)"
        )
    }
}
