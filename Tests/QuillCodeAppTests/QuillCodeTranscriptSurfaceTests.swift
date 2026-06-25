import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeTranscriptSurfaceTests: XCTestCase {
    func testTranscriptSurfaceBuildsDefaultTimelineFromMessagesAndToolCards() {
        let message = MessageSurface(
            message: ChatMessage(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                role: .user,
                content: "run whoami"
            )
        )
        let toolCard = ToolCardState(
            id: "shell-1",
            title: "Run Shell",
            subtitle: "Completed",
            status: .done
        )

        let transcript = TranscriptSurface(messages: [message], toolCards: [toolCard])

        XCTAssertEqual(transcript.emptyTitle, "Ask QuillCode to inspect, edit, or run this project.")
        XCTAssertEqual(transcript.emptySubtitle, "Use Auto for normal coding work, Review for manual gates, or Read-only for exploration.")
        XCTAssertEqual(transcript.timelineItems.map(\.kind), [.message, .toolCard])
        XCTAssertEqual(transcript.timelineItems.map(\.id), [
            "message-00000000-0000-0000-0000-000000000401",
            "timeline-tool-shell-1"
        ])
        XCTAssertEqual(transcript.timelineItems[0].message?.text, "run whoami")
        XCTAssertEqual(transcript.timelineItems[1].toolCard?.title, "Run Shell")
    }

    func testMessageSurfaceMapsRoleContentAccessibilityAndFeedback() {
        let message = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
            role: .assistant,
            content: "Output:\nquill"
        )

        let surface = MessageSurface(message: message, feedback: .helpful)

        XCTAssertEqual(surface.id, message.id)
        XCTAssertEqual(surface.role, .assistant)
        XCTAssertEqual(surface.text, "Output:\nquill")
        XCTAssertEqual(surface.accessibilityLabel, "assistant: Output:\nquill")
        XCTAssertEqual(surface.feedback, .helpful)
    }

    func testComposerSurfaceComputesSendabilityAndSlashSuggestions() {
        let ready = ComposerSurface(composer: ComposerState(draft: "/pr l"))
        let blank = ComposerSurface(composer: ComposerState(draft: "   \n  "))
        let sending = ComposerSurface(composer: ComposerState(draft: "run tests", isSending: true))

        XCTAssertTrue(ready.canSend)
        XCTAssertEqual(ready.placeholder, "Message QuillCode")
        XCTAssertEqual(ready.slashSuggestions.first?.usage, "/pr labels add|remove label")
        XCTAssertEqual(ready.slashSuggestions.first?.insertText, "/pr labels add ")
        XCTAssertFalse(blank.canSend)
        XCTAssertEqual(blank.slashSuggestions, [])
        XCTAssertFalse(sending.canSend)
    }

    func testComposerSurfaceShowsFilteredSlashSuggestions() {
        func suggestions(for draft: String) -> [SlashCommandSuggestionSurface] {
            ComposerSurface(composer: ComposerState(draft: draft)).slashSuggestions
        }

        XCTAssertEqual(suggestions(for: "/").prefix(3).map(\.usage), ["/help", "/status", "/new"])
        XCTAssertEqual(suggestions(for: "/workt").first?.usage, "/worktrees")
        XCTAssertEqual(suggestions(for: "/workt").first?.insertText, "/worktrees")
        XCTAssertEqual(suggestions(for: "/fol").first?.usage, "/follow-up when")
        XCTAssertEqual(suggestions(for: "/fol").first?.insertText, "/follow-up in ")
        XCTAssertEqual(suggestions(for: "/workspace-c").first?.usage, "/workspace-check when")
        XCTAssertEqual(suggestions(for: "/workspace-c").first?.insertText, "/workspace-check in ")
        XCTAssertEqual(suggestions(for: "/project r").prefix(2).map(\.usage), ["/project refresh", "/project rename name"])
        XCTAssertEqual(suggestions(for: "/pr l").first?.usage, "/pr labels add|remove label")
        XCTAssertEqual(suggestions(for: "/pr l").first?.insertText, "/pr labels add ")
        XCTAssertEqual(suggestions(for: "run /help"), [])
    }

    func testContextBannerDecodesOlderPayloadWithoutCompactCommand() throws {
        let data = """
        {
          "usedPercent": 88,
          "title": "Approaching context limit",
          "subtitle": "Older turns may drop out soon.",
          "newThreadCommand": {"id":"new-chat","title":"New thread"},
          "forkCommand": {"id":"fork-from-last","title":"Fork from last","isEnabled":true}
        }
        """.data(using: .utf8)!

        let banner = try JSONDecoder().decode(ContextBannerSurface.self, from: data)

        XCTAssertEqual(banner.usedPercent, 88)
        XCTAssertEqual(banner.title, "Approaching context limit")
        XCTAssertEqual(banner.compactCommand.id, "compact-context")
        XCTAssertEqual(banner.compactCommand.title, "Compact context")
        XCTAssertEqual(banner.compactCommand.category, WorkspaceCommandPalette.threadCategory)
        XCTAssertEqual(banner.compactCommand.keywords, ["thread", "context", "summarize", "compact"])
        XCTAssertEqual(banner.compactCommand.isEnabled, true)
    }
}
