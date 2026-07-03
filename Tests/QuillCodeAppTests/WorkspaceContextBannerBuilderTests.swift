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
        XCTAssertEqual(banner.subtitle, "Older turns may drop out soon. Compact the thread, start fresh, or fork with latest, summarized, or full visible context.")
        XCTAssertEqual(banner.newThreadCommand.id, "new-chat")
        XCTAssertEqual(banner.forkCommand.id, "fork-from-last")
        XCTAssertEqual(banner.forkCommands.map(\.id), [
            "fork-from-last",
            "fork-with-summary",
            "fork-full-context"
        ])
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

    func testBannerShowsRunningContextSummaryProgressAndDisablesContextMoves() throws {
        let thread = ChatThread(
            messages: [
                .init(role: .user, content: String(repeating: "x", count: 102_376))
            ],
            events: [
                ThreadEvent(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact)
                )
            ]
        )

        let banner = try XCTUnwrap(WorkspaceContextBannerBuilder(thread: thread).banner())
        let progress = try XCTUnwrap(banner.progress)

        XCTAssertEqual(progress.activeCommandID, "compact-context")
        XCTAssertEqual(progress.title, "Compacting context")
        XCTAssertEqual(progress.statusLabel, "Running")
        XCTAssertFalse(banner.compactCommand.isEnabled)
        XCTAssertFalse(banner.forkCommand.isEnabled)
        XCTAssertTrue(banner.newThreadCommand.isEnabled)
        XCTAssertEqual(Set(banner.forkCommands.map(\.isEnabled)), [false])
    }

    func testFinishedContextSummaryNoticeClearsBannerProgress() throws {
        let thread = ChatThread(
            messages: [
                .init(role: .user, content: String(repeating: "x", count: 102_376))
            ],
            events: [
                ThreadEvent(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary)
                ),
                ThreadEvent(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                        outcome: WorkspaceContextSummaryOutcome(summaryOverride: "ready", source: .model),
                        purpose: .forkSummary
                    )
                )
            ]
        )

        let banner = try XCTUnwrap(WorkspaceContextBannerBuilder(thread: thread).banner())

        XCTAssertNil(banner.progress)
        XCTAssertTrue(banner.compactCommand.isEnabled)
        XCTAssertEqual(Set(banner.forkCommands.map(\.isEnabled)), [true])
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

    @MainActor
    func testSurfaceShowsBannerNearEstimatedLimitAndEnablesCommands() throws {
        let longMessage = "context " + String(repeating: "word ", count: 26_000)
        let thread = ChatThread(title: "Long context", messages: [
            .init(role: .user, content: longMessage)
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let surface = model.surface()
        let banner = try XCTUnwrap(surface.contextBanner)

        XCTAssertTrue(banner.usedPercent >= 80)
        XCTAssertTrue(banner.title.contains("Context"))
        XCTAssertEqual(banner.newThreadCommand.id, "new-chat")
        XCTAssertEqual(banner.forkCommand.id, "fork-from-last")
        XCTAssertEqual(banner.forkCommands.map(\.id), [
            "fork-from-last",
            "fork-with-summary",
            "fork-full-context"
        ])
        XCTAssertEqual(banner.compactCommand.id, "compact-context")
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-with-summary" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-full-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, true)
    }

    @MainActor
    func testSurfaceHidesBannerForShortThreadAndDisablesForkCommands() {
        let thread = ChatThread(title: "Short")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let surface = model.surface()

        XCTAssertNil(surface.contextBanner)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-with-summary" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-full-context" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, false)
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

    func testProviderUsageOverridesCharacterEstimate() throws {
        let usage = ModelTokenUsage(promptTokens: 25, completionTokens: 0, totalTokens: 25)
        let thread = ChatThread(
            messages: [
                .init(role: .user, content: "short")
            ],
            events: [
                ModelTokenUsageEvent.event(usage: usage)
            ]
        )
        let builder = WorkspaceContextBannerBuilder(
            thread: thread,
            tokenBudget: 25,
            warningThresholdPercent: 100
        )

        let banner = try XCTUnwrap(builder.banner())

        XCTAssertEqual(WorkspaceContextBannerBuilder.latestProviderUsage(for: thread), usage)
        XCTAssertEqual(builder.contextUsedPercent(for: thread), 100)
        XCTAssertEqual(banner.title, "Context limit reached (100% used)")
        XCTAssertEqual(
            banner.subtitle,
            "Provider-reported token usage is near the limit. Compact the thread, start fresh, or fork with latest, summarized, or full visible context."
        )
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
