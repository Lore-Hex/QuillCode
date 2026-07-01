import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ComposerPlanProgressStripTests: XCTestCase {
    private func composer(planProgress: WorkspacePlanProgress?) -> ComposerSurface {
        ComposerSurface(composer: ComposerState(), planProgress: planProgress)
    }

    private func makeTopBar() -> TopBarSurface {
        TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Task",
            subtitle: "QuillCode - Auto",
            instructionLabel: "No instructions",
            instructionSources: [],
            memoryLabel: "No memories",
            memorySources: [],
            modelLabel: "Nike 1.0",
            selectedModelID: "trustedrouter/fast",
            modelCategories: [],
            modeLabel: "Auto",
            agentStatus: "Running",
            computerUseLabel: "Computer Use unavailable",
            showsComputerUseSetup: false
        )
    }

    private func sampleProgress() -> WorkspacePlanProgress {
        WorkspacePlanProgress(
            totalCount: 7,
            completedCount: 2,
            currentStepIndex: 3,
            currentStepTitle: "Running the tests",
            isRunning: true,
            isComplete: false,
            fraction: 0.5,
            stepCounterLabel: "3/7"
        )
    }

    // MARK: - Codable safety (the optional-add claim)

    func testLegacyComposerJSONWithoutPlanProgressDecodesToNil() throws {
        // A ComposerSurface persisted before this field existed must still decode (missing key ⇒ nil).
        let legacy = """
        {
          "draft": "hi",
          "placeholder": "Message",
          "isSending": false,
          "canSend": true,
          "slashSuggestions": [],
          "fileMentionSuggestions": [],
          "sentMessageHistory": [],
          "focusToken": 0
        }
        """
        let decoded = try JSONDecoder().decode(ComposerSurface.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.planProgress)
        XCTAssertEqual(decoded.draft, "hi")
    }

    func testPlanProgressRoundTrips() throws {
        let surface = composer(planProgress: sampleProgress())
        let data = try JSONEncoder().encode(surface)
        let decoded = try JSONDecoder().decode(ComposerSurface.self, from: data)
        XCTAssertEqual(decoded.planProgress, sampleProgress())
    }

    // MARK: - HTML surface

    func testHTMLComposerEmitsStripWhenPlanProgressPresent() {
        let html = WorkspaceHTMLTranscriptRenderer.renderComposer(composer(planProgress: sampleProgress()), topBar: makeTopBar())
        XCTAssertTrue(html.contains("data-testid=\"composer-plan-progress\""), html)
        XCTAssertTrue(html.contains("data-state=\"running\""), html)
        XCTAssertTrue(html.contains("width:50%"), html)
        XCTAssertTrue(html.contains(">3/7<"), html)
        XCTAssertTrue(html.contains("Running the tests"), html)
        XCTAssertTrue(html.contains("aria-valuemax=\"7\""), html)
        XCTAssertTrue(html.contains("aria-valuenow=\"2\""), html)
    }

    func testHTMLComposerOmitsStripWhenNoPlan() {
        let html = WorkspaceHTMLTranscriptRenderer.renderComposer(composer(planProgress: nil), topBar: makeTopBar())
        XCTAssertFalse(html.contains("composer-plan-progress"), html)
    }

    func testHTMLComposerCompleteStateAndFullBar() {
        let done = WorkspacePlanProgress(
            totalCount: 4, completedCount: 4, currentStepIndex: 4, currentStepTitle: "Wrap up",
            isRunning: false, isComplete: true, fraction: 1.0, stepCounterLabel: "4/4"
        )
        let html = WorkspaceHTMLTranscriptRenderer.renderComposer(composer(planProgress: done), topBar: makeTopBar())
        XCTAssertTrue(html.contains("data-state=\"complete\""), html)
        XCTAssertTrue(html.contains("width:100%"), html)
    }
}
