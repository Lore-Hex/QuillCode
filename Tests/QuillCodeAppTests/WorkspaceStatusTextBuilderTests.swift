import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceStatusTextBuilderTests: XCTestCase {
    func testStatusTextUsesSharedLabels() {
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Agent Rules",
            content: "Use Swift.",
            byteCount: 10
        )
        let memory = MemoryNote(
            id: "memory-1",
            scope: .project,
            title: "Preference",
            content: "Prefer small PRs.",
            relativePath: ".quillcode/memories/preference.md",
            byteCount: 17
        )
        let context = WorkspaceStatusContext(
            projectName: "QuillCode",
            threadTitle: "Status thread",
            instructions: [instruction],
            memories: [memory],
            goal: ThreadGoal(objective: "Ship QuillCode"),
            mode: .review,
            model: TrustedRouterDefaults.prometheusModel,
            agentStatus: "Running"
        )

        XCTAssertEqual(WorkspaceStatusTextBuilder.statusText(for: context), """
        Project: QuillCode
        Thread: Status thread
        Instructions: 1 instruction file loaded
        Memories: 1 memory
        Goal: Active - Ship QuillCode
        Mode: Review
        Model: Prometheus 1.0 (/prometheus)
        Agent: Running
        """)
    }

    func testInstructionAndMemoryLabelsHandleEmptyPluralAndTruncatedStates() {
        XCTAssertEqual(WorkspaceStatusTextBuilder.instructionLabel(for: []), "No project instructions")
        XCTAssertEqual(WorkspaceStatusTextBuilder.memoryLabel(for: []), "No memories")
        XCTAssertEqual(WorkspaceStatusTextBuilder.goalLabel(for: nil), "No durable goal")

        let instructions = [
            ProjectInstruction(path: "AGENTS.md", title: "Agent Rules", content: "", byteCount: 0),
            ProjectInstruction(path: ".quillcode/rules.md", title: "Rules", content: "", byteCount: 0, wasTruncated: true)
        ]
        let memories = [
            MemoryNote(id: "one", scope: .global, title: "One", content: "", relativePath: "one.md", byteCount: 0),
            MemoryNote(id: "two", scope: .project, title: "Two", content: "", relativePath: "two.md", byteCount: 0, wasTruncated: true)
        ]

        XCTAssertEqual(WorkspaceStatusTextBuilder.instructionLabel(for: instructions), "2 instruction files loaded, truncated")
        XCTAssertEqual(WorkspaceStatusTextBuilder.memoryLabel(for: memories), "2 memories, truncated")
    }

    func testModeLabelsAndTopBarSubtitles() {
        XCTAssertEqual(WorkspaceStatusTextBuilder.modeLabel(.readOnly), "Read-only")
        XCTAssertEqual(WorkspaceStatusTextBuilder.modeLabel(.review), "Review")
        XCTAssertEqual(WorkspaceStatusTextBuilder.modeLabel(.auto), "Auto")
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.topBarSubtitle(projectName: "QuillCode", thread: nil),
            "QuillCode - Not started"
        )

        let thread = ChatThread(
            title: "Run tests",
            mode: .auto,
            model: TrustedRouterDefaults.fastModel
        )
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.topBarSubtitle(projectName: "QuillCode", thread: thread),
            "QuillCode - Auto - Nike 1.0"
        )
    }

    func testModelLabelsPreferBrandingForRecommendedModels() {
        XCTAssertEqual(WorkspaceStatusTextBuilder.subtitleModelLabel("trustedrouter/fusion"), "Prometheus 1.0")
        XCTAssertEqual(WorkspaceStatusTextBuilder.statusModelLabel("trustedrouter/fusion"), "Prometheus 1.0 (/prometheus)")
        XCTAssertEqual(WorkspaceStatusTextBuilder.subtitleModelLabel(TrustedRouterDefaults.platoModel), "Plato 1.0")
        XCTAssertEqual(WorkspaceStatusTextBuilder.statusModelLabel(TrustedRouterDefaults.platoModel), "Plato 1.0 (/plato)")
        XCTAssertEqual(WorkspaceStatusTextBuilder.subtitleModelLabel("anthropic/claude-opus-4.1"), "anthropic/claude-opus-4.1")
        XCTAssertEqual(WorkspaceStatusTextBuilder.statusModelLabel("anthropic/claude-opus-4.1"), "anthropic/claude-opus-4.1")
    }

    /// The E2E route is deliberately NOT a recommended model (it must never be suggested), but it has
    /// a display name — the top bar must say "E2E Encrypted" like the composer chip does, not leak the
    /// raw route id into a confidential chat's subtitle.
    func testModelLabelsUseDisplayOnlyNamesForTheE2ERoute() {
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.subtitleModelLabel(TrustedRouterDefaults.e2eModel),
            TrustedRouterDefaults.e2eModelDisplayName
        )
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.statusModelLabel(TrustedRouterDefaults.e2eModel),
            "\(TrustedRouterDefaults.e2eModelDisplayName) (\(TrustedRouterDefaults.e2eModel))"
        )
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.subtitleModelLabel("e2e"),
            TrustedRouterDefaults.e2eModelDisplayName,
            "aliases resolve to the display name too"
        )

        let confidential = WorkspaceThreadCreationEngine.confidentialThread(projectID: nil, mode: .auto)
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.topBarSubtitle(projectName: "QuillCode", thread: confidential),
            "QuillCode - Auto - \(TrustedRouterDefaults.e2eModelDisplayName)"
        )
    }
}
