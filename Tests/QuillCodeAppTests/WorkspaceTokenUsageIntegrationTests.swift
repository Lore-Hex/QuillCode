import XCTest
@testable import QuillCodeApp
import QuillCodeCore

@MainActor
final class WorkspaceTokenUsageIntegrationTests: XCTestCase {
    private func usageEvent(prompt: Int, completion: Int) -> ThreadEvent {
        ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: prompt, completionTokens: completion))
    }

    func testUsageChipReflectsLatestProviderUsageOfSelectedThread() {
        let thread = ChatThread(title: "Work", events: [usageEvent(prompt: 500, completion: 347)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        XCTAssertEqual(model.surface().topBar.usageStatusLabel, "847 ctx · ↑500 ↓347")
    }

    func testUsesTheMostRecentUsageEvent() {
        let thread = ChatThread(title: "Work", events: [
            usageEvent(prompt: 100, completion: 50),
            usageEvent(prompt: 900, completion: 600)
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        XCTAssertEqual(model.surface().topBar.usageStatusLabel, "1.5k ctx · ↑900 ↓600")
    }

    func testNoUsageChipWithoutAUsageEvent() {
        let thread = ChatThread(title: "Fresh")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        XCTAssertNil(model.surface().topBar.usageStatusLabel)
    }

    func testUsageChipIsDerivedPerThreadAndDoesNotBleed() {
        let used = ChatThread(title: "Used", events: [usageEvent(prompt: 100, completion: 50)])
        let fresh = ChatThread(title: "Fresh")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [used, fresh], selectedThreadID: used.id)
        )
        XCTAssertEqual(model.surface().topBar.usageStatusLabel, "150 ctx · ↑100 ↓50")

        // Selecting the fresh thread shows no usage even though another thread has it.
        model.selectThread(fresh.id)
        XCTAssertNil(model.surface().topBar.usageStatusLabel)
    }
}
