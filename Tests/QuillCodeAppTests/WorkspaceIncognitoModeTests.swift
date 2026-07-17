import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceIncognitoModeTests: XCTestCase {
    func testIncognitoThreadFactoryPinsE2EModelAndCarriesNoWorkspaceContext() {
        let projectID = UUID()

        let thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: projectID, mode: .plan)

        XCTAssertTrue(thread.runtimeContext.isIncognito)
        XCTAssertTrue(thread.runtimeContext.isEphemeral)
        XCTAssertEqual(thread.model, TrustedRouterDefaults.e2eModel)
        XCTAssertEqual(thread.projectID, projectID)
        XCTAssertEqual(thread.mode, .plan)
        XCTAssertEqual(thread.title, "Incognito")
        // An incognito conversation neither reads from nor contributes to durable workspace context.
        XCTAssertTrue(thread.instructions.isEmpty)
        XCTAssertTrue(thread.memories.isEmpty)
        XCTAssertTrue(thread.messages.isEmpty)
        XCTAssertEqual(thread.events.map(\.summary), ["Incognito chat: not saved, routed end-to-end encrypted"])
    }

    func testNewIncognitoChatSelectsPinnedThreadAndStaysOutOfTheSidebar() throws {
        let existing = ChatThread(title: "Regular work")
        let model = model(threads: [existing], selectedThreadID: existing.id)

        let incognitoID = model.newIncognitoChat()
        let selected = try XCTUnwrap(model.selectedThread)

        XCTAssertEqual(selected.id, incognitoID)
        XCTAssertTrue(selected.runtimeContext.isIncognito)
        XCTAssertEqual(selected.model, TrustedRouterDefaults.e2eModel)
        // Ephemeral threads never appear in the sidebar (or its unfiltered variant) — the incognito
        // chat exists only as the current selection.
        XCTAssertEqual(model.root.sidebarItems.map(\.id), [existing.id])
        XCTAssertEqual(model.root.allSidebarItems.map(\.id), [existing.id])
    }

    func testSetModelIsANoOpInsideAnIncognitoChat() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let defaultModelBefore = model.root.config.defaultModel
        _ = model.newIncognitoChat()

        let returned = model.setModel(TrustedRouterDefaults.zeusModel)

        let selected = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(returned, TrustedRouterDefaults.e2eModel, "the gesture reports the pinned model")
        XCTAssertEqual(selected.model, TrustedRouterDefaults.e2eModel, "the thread's model stays pinned")
        XCTAssertEqual(
            model.root.config.defaultModel,
            defaultModelBefore,
            "a switch attempted inside incognito must not quietly reconfigure future normal chats"
        )
    }

    func testSetModelStillWorksForStandardThreadsAfterIncognitoGuard() throws {
        let regular = ChatThread(title: "Regular")
        let model = model(threads: [regular], selectedThreadID: regular.id)

        let returned = model.setModel(TrustedRouterDefaults.zeusModel)

        XCTAssertEqual(returned, TrustedRouterDefaults.zeusModel)
        XCTAssertEqual(try XCTUnwrap(model.selectedThread).model, TrustedRouterDefaults.zeusModel)
    }

    func testE2ERouteIsInTheBundledCatalogAndAliasMap() {
        let entry = TrustedRouterDefaults.bundledModelCatalog.first { $0.id == TrustedRouterDefaults.e2eModel }
        XCTAssertEqual(entry?.displayName, TrustedRouterDefaults.e2eModelDisplayName)
        XCTAssertEqual(entry?.category, TrustedRouterDefaults.privateCategory)
        XCTAssertEqual(entry?.provider, TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.modelIDAliases["e2e"], TrustedRouterDefaults.e2eModel)
        XCTAssertEqual(TrustedRouterDefaults.modelIDAliases["tr/e2e"], TrustedRouterDefaults.e2eModel)
        // The E2E route is a privacy pin, not a general recommendation: keep it out of Recommended.
        XCTAssertFalse(TrustedRouterDefaults.recommendedModelIDs.contains(TrustedRouterDefaults.e2eModel))
    }

    private func model(threads: [ChatThread], selectedThreadID: UUID?) -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: threads,
            selectedThreadID: selectedThreadID
        ))
    }
}
