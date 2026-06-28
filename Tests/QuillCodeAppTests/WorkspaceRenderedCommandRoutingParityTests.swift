import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceRenderedCommandRoutingParityTests: XCTestCase {
    func testNativeCommandSurfaceIDsAreCoveredByRenderedHarnessRoutingAudit() throws {
        let registry = try RenderedHarnessCommandRoutingRegistry.loadFromPackage()
        let commandIDs = Set(richNativeCommandSurface().map(\.id))
        let missingIDs = commandIDs
            .filter { !registry.routes($0) }
            .sorted()

        XCTAssertEqual(
            missingIDs,
            [],
            """
            Native command IDs should stay covered by the rendered harness command-routing audit.
            Add static IDs or dynamic prefixes to E2E/harness/index.html when adding new native commands.
            """
        )
    }

    func testRenderedHarnessRegistryIncludesEveryPullRequestCommandDescriptor() throws {
        let registry = try RenderedHarnessCommandRoutingRegistry.loadFromPackage()
        let missingIDs = WorkspacePullRequestCommandCatalog.descriptors
            .map(\.id)
            .filter { !registry.routes($0) }
            .sorted()

        XCTAssertEqual(
            missingIDs,
            [],
            "Pull request command additions should not silently drop out of rendered click routing."
        )
    }

    private func richNativeCommandSurface() -> [WorkspaceCommandSurface] {
        let thread = ChatThread(
            title: "Ship QuillCode",
            messages: [.init(role: .user, content: "Run tests")]
        )
        let selectedThreads = [
            ChatThread(title: "Pinned", isPinned: true),
            ChatThread(title: "Open"),
            ChatThread(title: "Archived", isArchived: true)
        ]
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            localActions: [
                LocalEnvironmentAction(
                    id: "local-env:.quillcode/actions/bootstrap.sh",
                    title: "Bootstrap",
                    detail: "Install dependencies.",
                    relativePath: ".quillcode/actions/bootstrap.sh",
                    command: "sh .quillcode/actions/bootstrap.sh"
                )
            ],
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "plugin:github",
                    kind: .plugin,
                    name: "GitHub",
                    relativePath: ".quillcode/plugins/github.json",
                    installCommand: "quill plugin install github",
                    updateCommand: "quill plugin update github"
                ),
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    launchExecutable: "quill-mcp"
                )
            ]
        )

        return WorkspaceCommandSurfaceBuilder(
            selectedThread: thread,
            selectedProject: project,
            selectedSidebarThreads: selectedThreads,
            sidebarSelectionIsActive: true,
            sidebarItemCount: selectedThreads.count,
            hasActiveWorkspaceRoot: true,
            canRetryLastUserTurn: true,
            composerIsSending: true,
            terminalHasEntries: true,
            terminalIsRunning: true,
            browserCanGoBack: true,
            browserCanGoForward: true,
            browserCanReload: true,
            browserCanOpenSession: true,
            mcpServerStatuses: ["mcp_server:filesystem": .ready],
            mcpServerProbeSummaries: [
                "mcp_server:filesystem": MCPServerProbeSummary(
                    resourceNames: ["README"],
                    resourceURIs: ["file:///workspace/README.md"],
                    promptNames: ["summarize_project"]
                )
            ],
            computerUseStatus: .permissionStatus(
                screenRecordingGranted: false,
                accessibilityGranted: false
            )
        )
        .commands
    }
}

private struct RenderedHarnessCommandRoutingRegistry {
    var staticCommandIDs: Set<String>
    var dynamicPrefixes: [String]

    static func loadFromPackage(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Self {
        let harnessURL = packageRoot()
            .appendingPathComponent("E2E/harness/index.html")
        let harnessText = try String(contentsOf: harnessURL, encoding: .utf8)
        return Self(
            staticCommandIDs: Set(try stringLiterals(
                after: "const harnessStaticCommandIDs = new Set([",
                before: "]);",
                in: harnessText,
                file: file,
                line: line
            )),
            dynamicPrefixes: try stringLiterals(
                after: "const harnessRoutableCommandPrefixes = [",
                before: "];",
                in: harnessText,
                file: file,
                line: line
            )
        )
    }

    func routes(_ commandID: String) -> Bool {
        staticCommandIDs.contains(commandID)
            || dynamicPrefixes.contains { commandID.hasPrefix($0) }
    }

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func stringLiterals(
        after startMarker: String,
        before endMarker: String,
        in text: String,
        file: StaticString,
        line: UInt
    ) throws -> [String] {
        guard let startRange = text.range(of: startMarker) else {
            XCTFail("Missing harness command registry marker: \(startMarker)", file: file, line: line)
            return []
        }
        let suffix = text[startRange.upperBound...]
        guard let endRange = suffix.range(of: endMarker) else {
            XCTFail("Missing harness command registry end marker: \(endMarker)", file: file, line: line)
            return []
        }
        let body = String(suffix[..<endRange.lowerBound])
        let regex = try NSRegularExpression(pattern: #"'([^']+)'"#)
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.matches(in: body, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: body) else {
                return nil
            }
            return String(body[capture])
        }
    }
}
