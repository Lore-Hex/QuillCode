import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class SlashWorkspaceCommandParserTests: XCTestCase {
    func testSupportsWorkspaceAliases() {
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("search"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("find"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("browser"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("preview"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("diff"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("git-status"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("git"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("branch"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("branches"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("worktree"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("worktrees"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("wt"))
        XCTAssertFalse(SlashWorkspaceCommandParser.supports("project"))
    }

    func testSearchAndFindAliasesOpenExistingWorkspaceCommands() {
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "search"), .workspaceCommand("search"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "find"), .workspaceCommand("find-in-chat"))
        XCTAssertEqual(SlashCommandParser.parse("/search"), .workspaceCommand("search"))
        XCTAssertEqual(SlashCommandParser.parse("/find"), .workspaceCommand("find-in-chat"))
    }

    func testBrowserAliasesToggleBrowserPane() {
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "browser"), .workspaceCommand("toggle-browser"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "preview"), .workspaceCommand("toggle-browser"))
        XCTAssertEqual(SlashCommandParser.parse("/browser"), .workspaceCommand("toggle-browser"))
        XCTAssertEqual(SlashCommandParser.parse("/preview"), .workspaceCommand("toggle-browser"))
    }

    func testGitDiffAndStatusAliasesRunGitCommands() {
        XCTAssertEqual(SlashCommandParser.parse("/diff"), .workspaceCommand("git-diff"))
        XCTAssertEqual(SlashCommandParser.parse("/changes"), .workspaceCommand("git-diff"))
        XCTAssertEqual(SlashCommandParser.parse("/git-status"), .workspaceCommand("git-status"))
        XCTAssertEqual(SlashCommandParser.parse("/gitstatus"), .workspaceCommand("git-status"))
        XCTAssertEqual(SlashCommandParser.parse("/git"), .workspaceCommand("git-status"))
        XCTAssertEqual(SlashCommandParser.parse("/git status"), .workspaceCommand("git-status"))
        XCTAssertEqual(SlashCommandParser.parse("/git diff"), .workspaceCommand("git-diff"))
    }

    func testGitFetchAndPullParseStructuredToolCalls() throws {
        guard case .toolCall(let fetchCall) = SlashCommandParser.parse("/git fetch origin --prune") else {
            return XCTFail("Expected /git fetch to dispatch host.git.fetch.")
        }
        XCTAssertEqual(fetchCall.name, ToolDefinition.gitFetch.name)
        let fetchArgs = try ToolArguments(fetchCall.argumentsJSON)
        XCTAssertEqual(fetchArgs.string("remote"), "origin")
        XCTAssertEqual(fetchArgs.bool("prune"), true)

        guard case .toolCall(let pullCall) = SlashCommandParser.parse("/git pull origin main") else {
            return XCTFail("Expected /git pull to dispatch host.git.pull.")
        }
        XCTAssertEqual(pullCall.name, ToolDefinition.gitPull.name)
        let pullArgs = try ToolArguments(pullCall.argumentsJSON)
        XCTAssertEqual(pullArgs.string("remote"), "origin")
        XCTAssertEqual(pullArgs.string("branch"), "main")
        XCTAssertEqual(pullArgs.bool("ffOnly"), true)

        guard case .toolCall(let mergePullCall) = SlashCommandParser.parse("/git pull origin main --merge") else {
            return XCTFail("Expected explicit merge pull to dispatch host.git.pull.")
        }
        XCTAssertEqual(try ToolArguments(mergePullCall.argumentsJSON).bool("ffOnly"), false)
    }

    func testGitSyncSubcommandsRejectAmbiguousArguments() {
        XCTAssertEqual(
            SlashCommandParser.parse("/git fetch origin upstream"),
            .invalid("Unexpected git fetch argument 'upstream'. Try /git fetch [remote] [--prune].")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/git pull --merge"),
            .invalid("Non-fast-forward git pull needs a remote or branch. Try /git pull origin main --merge.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/git pull origin main extra"),
            .invalid("Unexpected git pull argument 'extra'. Try /git pull [remote] [branch].")
        )
    }

    func testBranchAliasesListAndSwitchBranches() throws {
        XCTAssertEqual(SlashCommandParser.parse("/branch"), .workspaceCommand("git-branch-list"))
        XCTAssertEqual(SlashCommandParser.parse("/branches"), .workspaceCommand("git-branch-list"))
        guard case .toolCall(let listCall) = SlashCommandParser.parse("/branch list --local") else {
            return XCTFail("Expected branch list tool call.")
        }
        XCTAssertEqual(listCall.name, ToolDefinition.gitBranchList.name)
        XCTAssertEqual(try ToolArguments(listCall.argumentsJSON).bool("includeRemote"), false)

        guard case .toolCall(let switchCall) = SlashCommandParser.parse("/branch switch feature/quill") else {
            return XCTFail("Expected branch switch tool call.")
        }
        XCTAssertEqual(switchCall.name, ToolDefinition.gitBranchSwitch.name)
        XCTAssertEqual(try ToolArguments(switchCall.argumentsJSON).string("branch"), "feature/quill")

        guard case .toolCall(let shorthandCall) = SlashCommandParser.parse("/branch feature/quick") else {
            return XCTFail("Expected branch shorthand switch tool call.")
        }
        XCTAssertEqual(shorthandCall.name, ToolDefinition.gitBranchSwitch.name)
        XCTAssertEqual(try ToolArguments(shorthandCall.argumentsJSON).string("branch"), "feature/quick")
    }

    func testBranchCreateParsesBranchAndStartPoint() throws {
        guard case .toolCall(let call) = SlashCommandParser.parse("/branch create feature/quill --from origin/main") else {
            return XCTFail("Expected branch create tool call.")
        }

        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(call.name, ToolDefinition.gitBranchSwitch.name)
        XCTAssertEqual(arguments.string("branch"), "feature/quill")
        XCTAssertEqual(arguments.bool("create"), true)
        XCTAssertEqual(arguments.string("startPoint"), "origin/main")
    }

    func testBranchSubcommandsRejectAmbiguousArguments() {
        XCTAssertEqual(
            SlashCommandParser.parse("/branch list extra"),
            .invalid("Unknown branch list option 'extra'. Try /branch list [--local].")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/branch switch one two"),
            .invalid("Too many branch switch arguments. Branch names cannot contain spaces.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/branch create"),
            .invalid("Missing branch name. Try /branch create feature/name --from main.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/branch create feature --from"),
            .invalid("Missing start point after --from.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/branch unknown extra"),
            .invalid("Unknown branch command. Try /branch list, /branch switch name, or /branch create name.")
        )
    }

    func testInitAliasesScaffoldProjectInstructions() {
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("init"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("init-project"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "init"), .workspaceCommand("project-init"))
        XCTAssertEqual(SlashCommandParser.parse("/init"), .workspaceCommand("project-init"))
        XCTAssertEqual(SlashCommandParser.parse("/init-project"), .workspaceCommand("project-init"))
    }

    func testWorktreeAliasesListGitWorktrees() {
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "worktree"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "worktrees"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "wt"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/worktree"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/wt"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/worktree list"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/wt ls"), .workspaceCommand("git-worktree-list"))
    }

    func testWorktreeCreateParsesPathBranchAndBase() {
        XCTAssertEqual(
            SlashCommandParser.parse(#"/worktree create "../quill code feature" --branch feature/quill --base main"#),
            .worktreeCreate(.init(path: "../quill code feature", branch: "feature/quill", base: "main"))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/wt add ../quick --from origin/main -b quick/work"),
            .worktreeCreate(.init(path: "../quick", branch: "quick/work", base: "origin/main"))
        )
    }

    func testWorktreeOpenAndRemoveParseTypedRequests() {
        XCTAssertEqual(
            SlashCommandParser.parse(#"/worktree open "../quill code feature""#),
            .worktreeOpen(.init(path: "../quill code feature"))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree switch ../quick"),
            .worktreeOpen(.init(path: "../quick"))
        )
        XCTAssertEqual(
            SlashCommandParser.parse(#"/wt remove "../quill code feature" --force"#),
            .worktreeRemove(.init(path: "../quill code feature", force: true))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/wt rm ../quick -f"),
            .worktreeRemove(.init(path: "../quick", force: true))
        )
    }

    func testWorktreePruneParsesTypedRequest() {
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune --dry-run --verbose"),
            .worktreePrune(.init(dryRun: true, verbose: true))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/wt cleanup -n -v"),
            .worktreePrune(.init(dryRun: true, verbose: true))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune"),
            .worktreePrune(.init())
        )
    }

    func testWorktreeSubcommandsRejectAmbiguousOrMissingArguments() {
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree create"),
            .invalid("Missing worktree path. Try /worktree create ../feature --branch feature/name.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree open one two"),
            .invalid("Too many worktree open paths. Quote paths with spaces.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree open --bad"),
            .invalid("Unknown worktree open option '--bad'.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree list extra"),
            .invalid("Usage: /worktree list.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree create ../feature --branch"),
            .invalid("Missing branch after --branch.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree remove ../feature --hard"),
            .invalid("Unknown worktree remove option '--hard'.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune ../feature"),
            .invalid("Worktree prune does not take a path. Try /worktree prune --dry-run.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune --bad"),
            .invalid("Unknown worktree prune option '--bad'.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse(#"/worktree open "../feature"#),
            .invalid("Unclosed quote in worktree command.")
        )
    }
}
