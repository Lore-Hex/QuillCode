import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceTopBarStateBuilderTests: XCTestCase {
    func testSelectedThreadProjectAndThreadSettingsDriveTopBarState() {
        let projectID = UUID()
        let selectedProjectID = UUID()
        let thread = ChatThread(
            title: "Fix parser",
            projectID: projectID,
            mode: .review,
            model: TrustedRouterDefaults.prometheusModel
        )
        let root = QuillCodeRootState(
            config: AppConfig(defaultModel: TrustedRouterDefaults.defaultModel, mode: .auto),
            projects: [
                ProjectRef(id: selectedProjectID, name: "Selected Project", path: "/tmp/selected"),
                ProjectRef(id: projectID, name: "Thread Project", path: "/tmp/thread")
            ],
            selectedProjectID: selectedProjectID,
            threads: [thread],
            selectedThreadID: thread.id,
            topBar: TopBarState(
                appName: "QuillCode",
                agentStatus: TopBarAgentStatusLabel.streaming,
                computerUseStatus: .permissionStatus(
                    screenRecordingGranted: true,
                    accessibilityGranted: true
                )
            )
        )

        let state = WorkspaceTopBarStateBuilder.state(from: root, agentStatus: TopBarAgentStatusLabel.running)

        XCTAssertEqual(state.appName, "QuillCode")
        XCTAssertEqual(state.projectName, "Thread Project")
        XCTAssertEqual(state.threadTitle, "Fix parser")
        XCTAssertEqual(state.model, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(state.mode, AgentMode.review)
        XCTAssertEqual(state.agentStatus, TopBarAgentStatusLabel.running)
        XCTAssertEqual(state.computerUseStatus.message, "Computer Use ready")
    }

    func testFallsBackToSelectedProjectAndConfigWhenNoThreadIsSelected() {
        let selectedProjectID = UUID()
        let root = QuillCodeRootState(
            config: AppConfig(defaultModel: "z-ai/glm-5.2", mode: .readOnly),
            projects: [
                ProjectRef(id: selectedProjectID, name: "Selected Project", path: "/tmp/selected")
            ],
            selectedProjectID: selectedProjectID,
            topBar: TopBarState(agentStatus: TopBarAgentStatusLabel.terminal)
        )

        let state = WorkspaceTopBarStateBuilder.state(from: root)

        XCTAssertEqual(state.projectName, "Selected Project")
        XCTAssertNil(state.threadTitle)
        XCTAssertEqual(state.model, "z-ai/glm-5.2")
        XCTAssertEqual(state.mode, AgentMode.readOnly)
        XCTAssertEqual(state.agentStatus, TopBarAgentStatusLabel.terminal)
    }
}
