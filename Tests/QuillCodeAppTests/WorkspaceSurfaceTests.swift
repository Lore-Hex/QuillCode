import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceSurfaceTests: XCTestCase {
    func testSurfaceIncludesTopBarSidebarComposerAndCommands() {
        let thread = ChatThread(title: "Run whoami", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "Output:\njperla")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.setDraft("git status")

        let surface = model.surface()

        XCTAssertEqual(surface.topBar.primaryTitle, "Run whoami")
        XCTAssertEqual(surface.topBar.modelLabel, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(surface.topBar.modeLabel, "Auto")
        XCTAssertEqual(surface.sidebar.items.count, 1)
        XCTAssertEqual(surface.sidebar.items[0].title, "Run whoami")
        XCTAssertTrue(surface.sidebar.items[0].isSelected)
        XCTAssertEqual(surface.transcript.messages.count, 2)
        XCTAssertEqual(surface.composer.placeholder, "Message QuillCode")
        XCTAssertTrue(surface.composer.canSend)
        XCTAssertEqual(surface.commands.map(\.id), ["new-chat", "search", "stop-all", "settings", "computer-use-setup"])
    }

    func testEmptySurfaceShowsCodexLikeEmptyState() {
        let surface = QuillCodeWorkspaceModel().surface()

        XCTAssertEqual(surface.topBar.primaryTitle, "QuillCode")
        XCTAssertEqual(surface.sidebar.items.count, 0)
        XCTAssertEqual(surface.transcript.emptyTitle, "Ask QuillCode to inspect, edit, or run this project.")
        XCTAssertFalse(surface.composer.canSend)
        XCTAssertTrue(surface.topBar.showsComputerUseSetup)
    }

    func testHTMLRendererEscapesAndLabelsPrimaryRegions() {
        var thread = ChatThread(title: "Unsafe <title>")
        thread.messages = [
            .init(role: .user, content: "<script>alert(1)</script>")
        ]
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="top-bar""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar""#))
        XCTAssertTrue(html.contains(#"data-testid="transcript""#))
        XCTAssertTrue(html.contains(#"data-testid="composer""#))
        XCTAssertTrue(html.contains("Unsafe &lt;title&gt;"))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    }

    func testHTMLRendererIncludesToolCardOutput() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card""#))
        XCTAssertTrue(html.contains(#"data-status="done""#))
        XCTAssertTrue(html.contains("host.shell.run"))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-output""#))
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeSurfaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
