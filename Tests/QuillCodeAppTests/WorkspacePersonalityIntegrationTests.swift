import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspacePersonalityIntegrationTests: XCTestCase {
    func testNewChatUsesDefaultWithoutChangingExistingChatOverride() {
        let existing = ChatThread(personality: .none)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultPersonality: .friendly),
            threads: [existing],
            selectedThreadID: existing.id
        ))

        _ = model.newChat()

        XCTAssertEqual(model.selectedThread?.personality, .friendly)
        XCTAssertEqual(
            model.root.threads.first { $0.id == existing.id }?.personality,
            Optional.some(QuillCodePersonality.none)
        )
    }

    func testChangingSelectedChatDoesNotRewriteDefaultOrOtherChats() {
        let selected = ChatThread(personality: .pragmatic)
        let other = ChatThread(personality: .none)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultPersonality: .pragmatic),
            threads: [selected, other],
            selectedThreadID: selected.id
        ))

        XCTAssertTrue(model.setPersonality(.friendly))

        XCTAssertEqual(model.selectedThread?.personality, .friendly)
        XCTAssertEqual(model.root.config.defaultPersonality, .pragmatic)
        XCTAssertEqual(
            model.root.threads.first { $0.id == other.id }?.personality,
            Optional.some(QuillCodePersonality.none)
        )
    }

    func testSlashPersonalityUpdatesChatAndWritesVisibleConfirmation() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/personality friendly")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.selectedThread?.personality, .friendly)
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Personality set to Friendly for this chat. Warm and conversational while staying focused on the work."
        )
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testExplicitlyUnsupportedModelHidesAndRejectsPersonality() async throws {
        let modelID = "provider/no-personality"
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: modelID),
            modelCatalog: [ModelInfo(
                id: modelID,
                provider: "provider",
                displayName: "No Personality",
                category: "Test",
                capabilities: ModelCapabilities(supportsPersonality: false)
            )]
        ))

        XCTAssertTrue(SlashCommandCatalog.suggestions(
            for: "/personality",
            supportsPersonality: true
        ).contains { $0.usage.hasPrefix("/personality ") })
        XCTAssertFalse(SlashCommandCatalog.suggestions(
            for: "/personality",
            supportsPersonality: false
        ).contains { $0.usage.hasPrefix("/personality ") })

        model.setDraft("/personality friendly")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.selectedThread?.personality, .pragmatic)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "provider/no-personality does not support personality controls. Choose another model to change this chat's communication style."
        )
    }

    func testSettingsDraftCarriesDefaultPersonalityIntoUpdate() {
        let surface = WorkspaceSettingsSurface(
            config: AppConfig(defaultPersonality: .friendly),
            hasStoredAPIKey: false
        )
        var draft = QuillCodeSettingsDraft(settings: surface)

        XCTAssertEqual(draft.defaultPersonality, .friendly)
        draft.defaultPersonality = .none
        XCTAssertEqual(draft.update.defaultPersonality, .none)
    }

    func testOlderSettingsSurfaceDefaultsToPragmatic() throws {
        let surface = WorkspaceSettingsSurface(
            config: AppConfig(defaultPersonality: .friendly),
            hasStoredAPIKey: false
        )
        let encoded = try JSONEncoder().encode(surface)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "defaultPersonality")

        let decoded = try JSONDecoder().decode(
            WorkspaceSettingsSurface.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.defaultPersonality, .pragmatic)
    }
}
