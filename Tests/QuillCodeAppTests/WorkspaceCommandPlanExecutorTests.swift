import Foundation
import XCTest
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceCommandPlanExecutorTests: XCTestCase {
    func testExecutorRunsDraftPlanWithoutCommandIDParsing() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommandPlan(.setDraft("/remember "), workspaceRoot: try makeTempDirectory()))
        XCTAssertEqual(model.composer.draft, "/remember ")
    }

    func testExecutorRunsStaticActionPlan() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.terminal.isVisible)
        XCTAssertTrue(model.runWorkspaceCommandPlan(.action(.toggleTerminal), workspaceRoot: try makeTempDirectory()))
        XCTAssertTrue(model.terminal.isVisible)
    }

    func testExecutorRunsSidebarToggleCommand() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.chrome.isSidebarVisible)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-sidebar", workspaceRoot: try makeTempDirectory()))
        XCTAssertFalse(model.chrome.isSidebarVisible)
    }

    func testExecutorRunsWorkspaceNavigationCommands() throws {
        let firstThread = ChatThread(title: "First")
        let secondThread = ChatThread(title: "Second")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [firstThread, secondThread],
            selectedThreadID: firstThread.id
        ))
        model.selectThread(secondThread.id)

        XCTAssertTrue(model.runWorkspaceCommand("workspace-back", workspaceRoot: try makeTempDirectory()))
        XCTAssertEqual(model.root.selectedThreadID, firstThread.id)
        XCTAssertTrue(model.runWorkspaceCommand("workspace-forward", workspaceRoot: try makeTempDirectory()))
        XCTAssertEqual(model.root.selectedThreadID, secondThread.id)
    }

    func testExecutorRunsNewChatCommandPlan() throws {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [ChatThread(title: "Existing")],
            selectedThreadID: nil
        ))

        XCTAssertTrue(model.runWorkspaceCommand("new-chat", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.root.threads.count, 2)
        XCTAssertEqual(model.selectedThread?.title, "New chat")
    }

    func testExecutorRunsBrowserTabCommandPlans() throws {
        let model = QuillCodeWorkspaceModel()
        let root = try makeTempDirectory()
        let firstTabID = model.browser.selectedTabID

        XCTAssertTrue(model.runWorkspaceCommand("browser-tab-new", workspaceRoot: root))
        let secondTabID = model.browser.selectedTabID
        XCTAssertNotEqual(firstTabID, secondTabID)
        XCTAssertEqual(model.browser.tabs.count, 2)

        XCTAssertTrue(model.runWorkspaceCommand("browser-tab-select:\(firstTabID.uuidString)", workspaceRoot: root))
        XCTAssertEqual(model.browser.selectedTabID, firstTabID)
        XCTAssertTrue(model.runWorkspaceCommand("browser-tab-close:\(firstTabID.uuidString)", workspaceRoot: root))
        XCTAssertEqual(model.browser.selectedTabID, secondTabID)
        XCTAssertEqual(model.browser.tabs.count, 1)
    }

    func testExecutorOpensActivityInstructionSourceWithFileReadTool() throws {
        let root = try makeTempDirectory()
        try "Use Swift patterns.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let thread = ChatThread(
            title: "Inspect source",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "AGENTS.md",
                    content: "Use Swift patterns.",
                    byteCount: 19
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("activity-source-open:AGENTS.md", workspaceRoot: root))

        let selectedThread = try XCTUnwrap(model.selectedThread)
        let card = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).toolCards().last)
        XCTAssertEqual(card.title, ToolDefinition.fileRead.name)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.inputJSON, ToolArguments.json(["path": "AGENTS.md"]))
    }

    func testExecutorOpensActivityInstructionSourceAtLineWithFileReadWindow() throws {
        let root = try makeTempDirectory()
        try "First line.\nUse Swift patterns.\nThird line.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let thread = ChatThread(
            title: "Inspect source",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "AGENTS.md",
                    content: "First line.\nUse Swift patterns.\nThird line.",
                    byteCount: 42
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("activity-source-open-line:2:AGENTS.md", workspaceRoot: root))

        let selectedThread = try XCTUnwrap(model.selectedThread)
        let card = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).toolCards().last)
        XCTAssertEqual(card.title, ToolDefinition.fileRead.name)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.inputJSON, ToolArguments.json([
            "limit": 120,
            "offset": 2,
            "path": "AGENTS.md"
        ]))
    }

    func testExecutorPreparesActivityInstructionEditDraft() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand(
            "activity-source-edit:.quillcode/rules.md",
            workspaceRoot: try makeTempDirectory()
        ))

        XCTAssertEqual(model.composer.draft, "Edit instruction source .quillcode/rules.md: ")
    }

    func testExecutorPreparesActivityInstructionLineEditDraft() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand(
            "activity-source-edit-line:12:.quillcode/rules.md",
            workspaceRoot: try makeTempDirectory()
        ))

        XCTAssertEqual(model.composer.draft, "Edit instruction source .quillcode/rules.md:12: ")
    }

    func testExecutorPreparesInstructionDiagnosticResolutionDraft() throws {
        let thread = ChatThread(
            title: "Inspect conflicts",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "AGENTS.md",
                    content: "Root guidance.\nAlways run tests before final answers.",
                    byteCount: 53
                ),
                ProjectInstruction(
                    path: "Sources/Feature/AGENTS.md",
                    title: "Feature AGENTS.md",
                    content: "Feature guidance.\nDo not run tests for feature changes.",
                    byteCount: 55
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let diagnosticID = try XCTUnwrap(ProjectInstructionDiagnosticsBuilder
            .diagnostics(for: thread.instructions)
            .first { $0.statusLabel == "conflict" }?
            .id)

        XCTAssertTrue(model.runWorkspaceCommand(
            "activity-instruction-resolve:\(diagnosticID)",
            workspaceRoot: try makeTempDirectory()
        ))

        XCTAssertTrue(model.composer.draft.hasPrefix("Resolve instruction issue \"Conflicting instruction intent\""))
        XCTAssertTrue(model.composer.draft.contains("AGENTS.md says require"))
        XCTAssertTrue(model.composer.draft.contains("Sources/Feature/AGENTS.md says avoid"))
        XCTAssertTrue(model.composer.draft.contains("- AGENTS.md:2 [requires tests]"))
        XCTAssertTrue(model.composer.draft.contains("Current: Always run tests before final answers."))
        XCTAssertTrue(model.composer.draft.contains("- Sources/Feature/AGENTS.md:2 [avoids tests]"))
        XCTAssertTrue(model.composer.draft.contains("Current: Do not run tests for feature changes."))
        XCTAssertTrue(model.composer.draft.contains("Suggested fix: Choose one intent for tests guidance"))
    }

    func testExecutorAppliesInstructionDiagnosticPatchAndRefreshesContext() throws {
        let root = try makeTempDirectory()
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init", cwd: root)).ok)
        let featureDirectory = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: featureDirectory, withIntermediateDirectories: true)
        let rootInstruction = "Root guidance.\nAlways run tests before final answers.\n"
        let featureInstruction = "Feature guidance.\nDo not run tests for feature changes.\n"
        try rootInstruction.write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try featureInstruction.write(
            to: featureDirectory.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "AGENTS.md",
                content: rootInstruction,
                byteCount: rootInstruction.utf8.count
            ),
            ProjectInstruction(
                path: "Sources/Feature/AGENTS.md",
                title: "Feature AGENTS.md",
                content: featureInstruction,
                byteCount: featureInstruction.utf8.count
            )
        ]
        let projectStore = JSONProjectStore(fileURL: root.appendingPathComponent("projects.json"))
        let project = ProjectRef(name: "QuillCode", path: root.path, instructions: instructions)
        let thread = ChatThread(
            title: "Inspect conflicts",
            projectID: project.id,
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            activity: ActivityState(isVisible: true),
            projectStore: projectStore
        )
        let diagnosticID = try XCTUnwrap(ProjectInstructionDiagnosticsBuilder
            .diagnostics(for: instructions)
            .first { $0.statusLabel == "conflict" }?
            .id)

        XCTAssertTrue(model.runWorkspaceCommand(
            "activity-instruction-apply:0:\(diagnosticID)",
            workspaceRoot: root
        ))

        let editedFeatureInstruction = try String(
            contentsOf: featureDirectory.appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )
        XCTAssertFalse(editedFeatureInstruction.contains("Do not run tests for feature changes."))
        let selectedThread = try XCTUnwrap(model.selectedThread)
        let cards = WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).toolCards()
        XCTAssertEqual(cards.suffix(2).map(\.title), [ToolDefinition.applyPatch.name, ToolDefinition.gitDiff.name])
        XCTAssertFalse(model.surface().activity.sources.contains { $0.id == diagnosticID })
        XCTAssertEqual(model.root.projects.first?.resolvedInstructionDiagnosticIDs, [diagnosticID])
        XCTAssertEqual(try projectStore.load().first?.resolvedInstructionDiagnosticIDs, [diagnosticID])
    }

    func testExecutorClearsExactDuplicateInstructionSourceAndRefreshesContext() throws {
        let root = try makeTempDirectory()
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init", cwd: root)).ok)
        let rulesDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: rulesDirectory, withIntermediateDirectories: true)
        let instruction = "Prefer small diffs.\nRun focused tests.\n"
        try instruction.write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try instruction.write(
            to: rulesDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "AGENTS.md",
                content: instruction,
                byteCount: instruction.utf8.count
            ),
            ProjectInstruction(
                path: ".quillcode/rules.md",
                title: "rules.md",
                content: instruction,
                byteCount: instruction.utf8.count
            )
        ]
        let projectStore = JSONProjectStore(fileURL: root.appendingPathComponent("projects.json"))
        let project = ProjectRef(name: "QuillCode", path: root.path, instructions: instructions)
        let thread = ChatThread(
            title: "Inspect duplicates",
            projectID: project.id,
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            activity: ActivityState(isVisible: true),
            projectStore: projectStore
        )
        let diagnosticID = try XCTUnwrap(ProjectInstructionDiagnosticsBuilder
            .diagnostics(for: instructions)
            .first(where: \.isDuplicateScope)?
            .id)

        XCTAssertTrue(model.runWorkspaceCommand(
            "activity-instruction-apply:1:\(diagnosticID)",
            workspaceRoot: root
        ))

        let editedRules = try String(
            contentsOf: rulesDirectory.appendingPathComponent("rules.md"),
            encoding: .utf8
        )
        XCTAssertEqual(editedRules, "")
        let selectedThread = try XCTUnwrap(model.selectedThread)
        let card = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).toolCards().last)
        XCTAssertEqual(card.title, ToolDefinition.fileWrite.name)
        XCTAssertEqual(card.status, .done)
        XCTAssertFalse(model.surface().activity.sources.contains { $0.id == diagnosticID })
        XCTAssertEqual(model.root.projects.first?.resolvedInstructionDiagnosticIDs, [diagnosticID])
        XCTAssertEqual(try projectStore.load().first?.resolvedInstructionDiagnosticIDs, [diagnosticID])
    }

    func testExecutorRejectsMissingInstructionDiagnosticResolution() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.runWorkspaceCommand(
            "activity-instruction-resolve:not-found",
            workspaceRoot: try makeTempDirectory()
        ))
        XCTAssertEqual(model.composer.draft, "")
    }

    func testExecutorDismissesInstructionDiagnostic() throws {
        let root = try makeTempDirectory()
        let store = JSONProjectStore(fileURL: root.appendingPathComponent("projects.json"))
        let project = ProjectRef(
            name: "QuillCode",
            path: root.path,
            instructions: Self.conflictingInstructions
        )
        let thread = ChatThread(
            title: "Inspect conflicts",
            projectID: project.id,
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: Self.conflictingInstructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            activity: ActivityState(isVisible: true),
            projectStore: store
        )
        let diagnosticID = try XCTUnwrap(ProjectInstructionDiagnosticsBuilder
            .diagnostics(for: Self.conflictingInstructions)
            .first { $0.statusLabel == "conflict" }?
            .id)

        XCTAssertTrue(model.runWorkspaceCommand(
            "activity-instruction-dismiss:\(diagnosticID)",
            workspaceRoot: root
        ))

        XCTAssertTrue(model.activity.isVisible)
        XCTAssertEqual(model.activity.dismissedInstructionDiagnosticIDs, [diagnosticID])
        XCTAssertEqual(model.root.projects.first?.dismissedInstructionDiagnosticIDs, [diagnosticID])
        XCTAssertFalse(model.surface().activity.sources.contains { $0.id == diagnosticID })
        XCTAssertEqual(try store.load().first?.dismissedInstructionDiagnosticIDs, [diagnosticID])
    }

    private static let conflictingInstructions = [
        ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Always run tests before final answers.",
            byteCount: 38
        ),
        ProjectInstruction(
            path: "Sources/Feature/AGENTS.md",
            title: "Feature AGENTS.md",
            content: "Do not run tests for feature changes.",
            byteCount: 37
        )
    ]

}
