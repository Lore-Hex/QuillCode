import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceContextBannerBuilderTests: XCTestCase {
    func testBannerAppearsAtWarningThreshold() throws {
        let thread = ChatThread(messages: [
            .init(role: .user, content: String(repeating: "x", count: 102_376))
        ])

        let banner = try XCTUnwrap(WorkspaceContextBannerBuilder(thread: thread).banner())

        XCTAssertEqual(banner.usedPercent, 80)
        XCTAssertEqual(banner.title, "Approaching context limit (80% used)")
        XCTAssertEqual(banner.subtitle, "Older turns may drop out soon. Compact the thread, start fresh, or fork from the latest useful context.")
        XCTAssertEqual(banner.newThreadCommand.id, "new-chat")
        XCTAssertEqual(banner.forkCommand.id, "fork-from-last")
        XCTAssertEqual(banner.compactCommand.id, "compact-context")
    }

    func testBannerUsesFullContextTitleAtOneHundredPercent() throws {
        let thread = ChatThread(messages: [
            .init(role: .user, content: String(repeating: "x", count: 130_000))
        ])

        let banner = try XCTUnwrap(WorkspaceContextBannerBuilder(thread: thread).banner())

        XCTAssertEqual(banner.usedPercent, 100)
        XCTAssertEqual(banner.title, "Context limit reached (100% used)")
    }

    func testBannerHiddenForMissingEmptyOrShortThreads() {
        let emptyThread = ChatThread()
        let shortThread = ChatThread(messages: [
            .init(role: .user, content: "short")
        ])

        XCTAssertNil(WorkspaceContextBannerBuilder(thread: nil).banner())
        XCTAssertNil(WorkspaceContextBannerBuilder(thread: emptyThread).banner())
        XCTAssertNil(WorkspaceContextBannerBuilder(thread: shortThread).banner())
    }

    func testEstimateIncludesMessagesEventsAndInstructions() {
        let thread = ChatThread(
            messages: [
                .init(role: .user, content: "abcdefgh")
            ],
            events: [
                ThreadEvent(kind: .notice, summary: "event", payloadJSON: "payload")
            ],
            instructions: [
                ProjectInstruction(path: "AGENTS.md", title: "Rules", content: "abcd", byteCount: 4)
            ]
        )

        XCTAssertEqual(WorkspaceContextBannerBuilder.estimatedContextTokens(for: thread), 12)
    }

    func testCustomBudgetAndThresholdSupportSmallDeterministicTests() throws {
        let thread = ChatThread(messages: [
            .init(role: .user, content: String(repeating: "x", count: 76))
        ])
        let builder = WorkspaceContextBannerBuilder(
            thread: thread,
            tokenBudget: 25,
            warningThresholdPercent: 100
        )

        let banner = try XCTUnwrap(builder.banner())

        XCTAssertEqual(builder.contextUsedPercent(for: thread), 100)
        XCTAssertEqual(banner.title, "Context limit reached (100% used)")
    }

    func testCustomBudgetAndThresholdClampToSafeBounds() throws {
        let thread = ChatThread(messages: [
            .init(role: .user, content: "x")
        ])
        let builder = WorkspaceContextBannerBuilder(
            thread: thread,
            tokenBudget: 0,
            warningThresholdPercent: 200
        )

        let banner = try XCTUnwrap(builder.banner())

        XCTAssertEqual(builder.contextUsedPercent(for: thread), 100)
        XCTAssertEqual(banner.title, "Context limit reached (100% used)")
    }
}
