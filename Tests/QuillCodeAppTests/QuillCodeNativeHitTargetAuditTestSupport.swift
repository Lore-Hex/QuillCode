import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
class QuillCodeNativeHitTargetAuditTestCase: XCTestCase {
    let requiredRepresentativeContractIDs = [
        "composer.input",
        "composer.send",
        "composer.model-picker",
        "composer.mode-picker",
        "top-bar.overflow",
        "sidebar.tools-menu",
        "project.clear",
        "workspace.chrome",
        "sidebar.thread-row",
        "sidebar.thread-action",
        "transcript.message-action",
        "transcript.artifact-link",
        "transcript.tool-card",
        "transcript.tool-card-action",
        "transcript.context-banner-action",
        "command-palette.input",
        "command-palette.result",
        "search.input",
        "search.result",
        "settings.text-entry",
        "settings.action",
        "model-picker.search",
        "model-picker.option",
        "model-picker.option-action",
        "review.body",
        "review.thread-reply",
        "review.mode",
        "review.file-row",
        "review.action",
        "secondary-pane.tab",
        "menu-bar.action",
        "command.add-project",
        "command.new-chat",
        "command.search",
        "command.toggle-extensions",
        "command.toggle-automations",
        "command.toggle-terminal",
        "command.toggle-browser",
        "command.toggle-memories",
        "command.toggle-activity",
        "command.command-palette",
        "command.keyboard-shortcuts",
        "command.settings",
        "terminal.command",
        "terminal.family-action",
        "terminal.run",
        "terminal.clear",
        "browser.address",
        "browser.family-action",
        "browser.family-icon",
        "browser.open",
        "browser.new-tab",
        "browser.comment",
        "browser.add-comment",
        "extensions.action",
        "extensions.reference-action",
        "extensions.mcp-reference",
        "memories.add",
        "memories.item-action",
        "memories.edit",
        "memories.delete",
        "automations.create",
        "automations.run",
        "automations.primary",
        "automations.delete",
        "transcript.thinking-trace"
    ]

    let expectedSamplePoints = [
        QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "leading-edge", x: 0.08, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "leading-interior", x: 0.18, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "trailing-edge", x: 0.92, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "trailing-interior", x: 0.82, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "top-edge", x: 0.5, y: 0.08),
        QuillCodeNativeHitTargetProbePoint(name: "top-interior", x: 0.5, y: 0.18),
        QuillCodeNativeHitTargetProbePoint(name: "bottom-edge", x: 0.5, y: 0.92),
        QuillCodeNativeHitTargetProbePoint(name: "bottom-interior", x: 0.5, y: 0.82)
    ]

    func representativeSurface() -> WorkspaceSurface {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Native target audit", messages: [
            .init(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))
        var surface = model.surface()
        surface.transcript.thinking = TranscriptThinkingSurface(
            id: "thinking-native-target-audit",
            title: "Thinking",
            subtitle: "Running: host.shell.run running",
            traceLines: [
                "Queued: host.shell.run queued",
                "Running: host.shell.run running"
            ]
        )

        surface.terminal.isVisible = true
        surface.terminal.draft = "pwd"
        surface.terminal.entries = [
            TerminalCommandSurface(entry: TerminalCommandState(
                command: "pwd",
                stdout: "/tmp/QuillCode\n",
                stderr: "",
                exitCode: 0,
                ok: true
            ))
        ]

        var browser = BrowserState(isVisible: true, addressDraft: "localhost:5173")
        browser.comments = [
            BrowserCommentState(url: "http://localhost:5173", text: "Looks good")
        ]
        surface.browser = BrowserSurface(browser: browser)

        surface.extensions = WorkspaceExtensionsSurface(
            isVisible: true,
            manifests: [mcpManifest()],
            mcpServerStatuses: ["mcp:filesystem": .ready],
            mcpServerProbeSummaries: ["mcp:filesystem": mcpProbe()]
        )

        surface.memories = WorkspaceMemoriesSurface(
            isVisible: true,
            notes: [
                MemoryNote(
                    id: "global-preferences",
                    scope: .global,
                    title: "Preferences",
                    content: "Prefer small reviewable changes.",
                    relativePath: "memories/preferences.md",
                    byteCount: 32
                )
            ]
        )

        surface.automations = WorkspaceAutomationsSurface(
            isVisible: true,
            automations: [automation()],
            createThreadFollowUpCommand: .automationCreateThreadFollowUp(isEnabled: true),
            createWorkspaceScheduleCommand: .automationCreateWorkspaceSchedule(isEnabled: true)
        )

        return surface
    }

    func packageRoot(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func swiftSourceFiles(in directory: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys)
        )
        guard let enumerator else { return [] }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true, url.pathExtension == "swift" else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    func sourceAuditIssues(
        for source: String,
        fileName: String = "SourceAuditProbe.swift"
    ) throws -> [String] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeNativeHitTargetAuditTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        return try sourceHitTargetContractIssues(in: fileURL, sourceRoot: directory)
    }

    func sourceHitTargetContractIssues(in fileURL: URL, sourceRoot: URL) throws -> [String] {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = source.components(separatedBy: .newlines)
        let interactivePattern = try NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_])(Button|Link|NavigationLink|Menu|DisclosureGroup|TextField|SecureField|TextEditor|Picker|Toggle|Slider|Stepper)\s*(?:\(|\{)"#
        )
        let gesturePattern = try NSRegularExpression(
            pattern: #"\.(onTapGesture|onLongPressGesture|gesture|simultaneousGesture|highPriorityGesture)\s*(?:\(|\{)|\b(?:TapGesture|LongPressGesture)\s*\("#
        )
        let geometryMarkers = [
            ".quillCodeTextButtonTarget",
            ".quillCodeFormActionTarget",
            ".quillCodeTextEntryTarget",
            ".quillCodeSegmentedControlTarget",
            ".quillCodeAdjustableControlTarget",
            ".quillCodeLinkTarget",
            ".quillCodeSwitchRowTarget",
            ".quillCodeOwnedGestureTarget",
            ".quillCodeIconButtonTarget",
            ".quillCodeFullRowButtonTarget",
            ".quillCodeSidebarRowChrome",
            ".quillCodeSidebarRowTarget",
            ".quillCodeSidebarIconButtonTarget",
            ".quillCodeCapsuleButtonTarget"
        ]
        let platformMenuItemMarker = ".quillCodePlatformMenuItemTarget"

        var issues: [String] = []
        issues.append(contentsOf: interactiveControlIssues(
            lines: lines,
            fileURL: fileURL,
            sourceRoot: sourceRoot,
            interactivePattern: interactivePattern,
            geometryMarkers: geometryMarkers,
            platformMenuItemMarker: platformMenuItemMarker
        ))
        issues.append(contentsOf: gestureControlIssues(
            lines: lines,
            fileURL: fileURL,
            sourceRoot: sourceRoot,
            gesturePattern: gesturePattern,
            interactivePattern: interactivePattern
        ))
        return issues
    }

    private func interactiveControlIssues(
        lines: [String],
        fileURL: URL,
        sourceRoot: URL,
        interactivePattern: NSRegularExpression,
        geometryMarkers: [String],
        platformMenuItemMarker: String
    ) -> [String] {
        var issues: [String] = []

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = interactivePattern.firstMatch(in: line, range: range),
                  let kindRange = Range(match.range(at: 1), in: line) else { continue }
            let kind = String(line[kindRange])
            let snippet = interactiveControlSnippet(
                from: index,
                in: lines,
                interactivePattern: interactivePattern
            )
            let markers = kind == "Menu"
                ? geometryMarkers
                : geometryMarkers + [platformMenuItemMarker]
            let location = sourceLocation(fileURL: fileURL, sourceRoot: sourceRoot, line: index + 1)
            let summary = "`\(line.trimmingCharacters(in: .whitespaces))`"
            if !markers.contains(where: snippet.contains) {
                issues.append("\(location) missing QuillCode hit-target marker near \(summary)")
                continue
            }
            if kind == "NavigationLink",
               snippet.contains(".quillCodeLinkTarget") {
                issues.append("\(location) NavigationLink should use press-style hit-target semantics near \(summary)")
            }
            if ["Button", "Menu", "NavigationLink"].contains(kind),
               !snippet.contains(platformMenuItemMarker),
               !snippet.contains(".buttonStyle(QuillCodePressableButtonStyle"),
               !snippet.contains(".buttonStyle(QuillCodeActionButtonStyle") {
                issues.append("\(location) missing QuillCode press/action button style near \(summary)")
            }
            if ["TextField", "SecureField", "TextEditor"].contains(kind),
               !snippet.contains(".accessibilityIdentifier(") {
                issues.append("\(location) text-entry target should declare a stable accessibilityIdentifier near \(summary)")
            }
        }

        return issues
    }

    private func gestureControlIssues(
        lines: [String],
        fileURL: URL,
        sourceRoot: URL,
        gesturePattern: NSRegularExpression,
        interactivePattern: NSRegularExpression
    ) -> [String] {
        var issues: [String] = []

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard gesturePattern.firstMatch(in: line, range: range) != nil else { continue }
            let snippet = gestureControlSnippet(
                from: index,
                in: lines,
                gesturePattern: gesturePattern,
                interactivePattern: interactivePattern
            )
            if snippet.contains(".quillCodeOwnedGestureTarget") {
                continue
            }
            let location = sourceLocation(fileURL: fileURL, sourceRoot: sourceRoot, line: index + 1)
            let summary = "`\(line.trimmingCharacters(in: .whitespaces))`"
            issues.append("\(location) gesture-based click target should use Button, Link, or quillCodeOwnedGestureTarget near \(summary)")
        }

        return issues
    }

    private func interactiveControlSnippet(
        from startIndex: Int,
        in lines: [String],
        interactivePattern: NSRegularExpression
    ) -> String {
        let startIndent = leadingWhitespaceCount(lines[startIndex])
        var endIndex = min(startIndex + 64, lines.endIndex)
        if startIndex + 1 < endIndex {
            for candidateIndex in (startIndex + 1)..<endIndex {
                let line = lines[candidateIndex]
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                let startsPeerControl = interactivePattern.firstMatch(in: line, range: range) != nil
                    && leadingWhitespaceCount(line) <= startIndent
                if startsPeerControl {
                    endIndex = candidateIndex
                    break
                }
            }
        }
        return lines[startIndex..<endIndex].joined(separator: "\n")
    }

    private func gestureControlSnippet(
        from gestureIndex: Int,
        in lines: [String],
        gesturePattern: NSRegularExpression,
        interactivePattern: NSRegularExpression
    ) -> String {
        let startIndex = gestureOwnerStartIndex(for: gestureIndex, in: lines)
        let startIndent = leadingWhitespaceCount(lines[startIndex])
        let upperBound = min(lines.endIndex, gestureIndex + 80)
        var endIndex = upperBound

        if gestureIndex + 1 < upperBound {
            for peerIndex in (gestureIndex + 1)..<upperBound {
                let peerLine = lines[peerIndex]
                let range = NSRange(peerLine.startIndex..<peerLine.endIndex, in: peerLine)
                let startsPeerControl = interactivePattern.firstMatch(in: peerLine, range: range) != nil
                    && leadingWhitespaceCount(peerLine) <= startIndent
                let startsPeerGesture = gesturePattern.firstMatch(in: peerLine, range: range) != nil
                    && leadingWhitespaceCount(peerLine) <= startIndent
                if startsPeerGesture || startsPeerControl || isPeerViewExpression(peerLine, ownerIndent: startIndent) {
                    endIndex = peerIndex
                    break
                }
            }
        }

        return lines[startIndex..<endIndex].joined(separator: "\n")
    }

    private func gestureOwnerStartIndex(for gestureIndex: Int, in lines: [String]) -> Int {
        let gestureIndent = leadingWhitespaceCount(lines[gestureIndex])
        let lowerBound = max(0, gestureIndex - 80)
        for candidateIndex in stride(from: gestureIndex, through: lowerBound, by: -1) {
            let line = lines[candidateIndex]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isModifierOrStructuralLine(trimmed),
                  leadingWhitespaceCount(line) <= gestureIndent else { continue }
            return candidateIndex
        }
        return max(0, gestureIndex - 8)
    }

    private func isPeerViewExpression(_ line: String, ownerIndent: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard leadingWhitespaceCount(line) <= ownerIndent,
              !isModifierOrStructuralLine(trimmed) else { return false }
        return true
    }

    private func isModifierOrStructuralLine(_ trimmedLine: String) -> Bool {
        trimmedLine.isEmpty
            || trimmedLine.hasPrefix(".")
            || trimmedLine.hasPrefix("//")
            || trimmedLine == "}"
            || trimmedLine == ")"
            || trimmedLine == "},"
            || trimmedLine == "),"
            || trimmedLine.hasPrefix("var body:")
    }

    private func leadingWhitespaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private func sourceLocation(fileURL: URL, sourceRoot: URL, line: Int) -> String {
        let relativePath = fileURL.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
        return "\(relativePath):\(line)"
    }

    private func mcpManifest() -> ProjectExtensionManifest {
        ProjectExtensionManifest(
            id: "mcp:filesystem",
            kind: .mcpServer,
            name: "Filesystem",
            summary: "Expose workspace files.",
            relativePath: ".quillcode/mcp/filesystem.json",
            transport: .stdio,
            launchExecutable: "quill-mcp",
            launchCommand: "quill-mcp --root .",
            updateCommand: "quill-mcp update"
        )
    }

    private func mcpProbe() -> MCPServerProbeSummary {
        MCPServerProbeSummary(
            protocolVersion: "2024-11-05",
            serverName: "Filesystem",
            serverVersion: "1.0",
            toolDescriptors: [
                MCPToolDescriptor(name: "read_file", description: "Read a file", requiredArguments: ["path"])
            ],
            resourceNames: ["README"],
            resourceURIs: ["file://README.md"],
            promptNames: ["review"]
        )
    }

    private func automation() -> QuillAutomation {
        QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            title: "Morning check",
            detail: "Check the workspace.",
            kind: .workspaceSchedule,
            status: .active,
            scheduleKind: .cron,
            scheduleDescription: "Every morning",
            nextRunAt: Date(timeIntervalSince1970: 100)
        )
    }
}
