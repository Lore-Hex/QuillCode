import Foundation
import QuillCodeCore

public struct ComputerUseToolExecutor: Sendable {
    public static let defaultArtifactDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuillCode", isDirectory: true)
        .appendingPathComponent("screenshots", isDirectory: true)

    private let backend: any ComputerUseBackend
    private let artifactDirectory: URL
    private let appApprovalPolicy: ComputerUseAppApprovalPolicy
    private let originThreadID: String?
    private let projectID: String?
    private let workspaceRoot: String?

    public init(
        backend: any ComputerUseBackend,
        appApprovalPolicy: ComputerUseAppApprovalPolicy = .unrestricted,
        artifactDirectory: URL = Self.defaultArtifactDirectory,
        originThreadID: String? = nil,
        projectID: String? = nil,
        workspaceRoot: String? = nil
    ) {
        self.backend = backend
        self.appApprovalPolicy = appApprovalPolicy
        self.artifactDirectory = artifactDirectory
        self.originThreadID = originThreadID
        self.projectID = projectID
        self.workspaceRoot = workspaceRoot
    }

    public func execute(_ call: ToolCall) async -> ToolResult? {
        if let failure = await preflightFailure(for: call.name) {
            return failure
        }

        do {
            return try await executePreflighted(call)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func executePreflighted(_ call: ToolCall) async throws -> ToolResult? {
        let args = try ToolArguments(call.argumentsJSON)
        switch call.name {
        case ToolDefinition.computerScreenshot.name:
            return try await executeScreenshot()
        case ToolDefinition.computerClick.name:
            return try await executeClick(args)
        case ToolDefinition.computerType.name:
            return try await executeType(args)
        case ToolDefinition.computerScroll.name:
            return try await executeScroll(args)
        case ToolDefinition.computerMove.name:
            return try await executeMove(args)
        case ToolDefinition.computerKey.name:
            return try await executeKey(args)
        case ToolDefinition.workflowRecordStart.name:
            return try await executeWorkflowRecordStart(args)
        case ToolDefinition.workflowRecordStop.name:
            return try await executeWorkflowRecordStop()
        default:
            return nil
        }
    }

    private func executeScreenshot() async throws -> ToolResult {
        let screenshot = try await backend.screenshot()
        let path = try writeScreenshotArtifact(screenshot)
        let foregroundApplication = await currentForegroundApplication()
        let accessibilitySnapshot = await currentAccessibilitySnapshot(limit: 8)
        let output = ComputerScreenshotToolOutput(
            width: screenshot.width,
            height: screenshot.height,
            path: path,
            foregroundApplication: foregroundApplication,
            accessibilitySnapshot: accessibilitySnapshot,
            visualSummary: Self.screenshotVisualSummary(
                width: screenshot.width,
                height: screenshot.height,
                path: path,
                foregroundApplication: foregroundApplication,
                accessibilitySnapshot: accessibilitySnapshot
            )
        )
        return ToolResult(
            ok: true,
            stdout: try JSONHelpers.encodePretty(output),
            artifacts: path.map { [$0] } ?? []
        )
    }

    private func currentForegroundApplication() async -> ComputerUseApplication? {
        await foregroundApplicationProvider()?.foregroundApplication()
    }

    private func foregroundApplicationProvider() -> (any ComputerUseForegroundApplicationProviding)? {
        backend as? any ComputerUseForegroundApplicationProviding
    }

    private func currentAccessibilitySnapshot(limit: Int) async -> ComputerUseAccessibilitySnapshot? {
        await accessibilitySnapshotProvider()?.accessibilitySnapshot(limit: limit)
    }

    private func accessibilitySnapshotProvider() -> (any ComputerUseAccessibilitySnapshotProviding)? {
        backend as? any ComputerUseAccessibilitySnapshotProviding
    }

    private func executeClick(_ args: ToolArguments) async throws -> ToolResult {
        let x = try args.requiredInt("x")
        let y = try args.requiredInt("y")
        try await backend.leftClick(x: x, y: y)
        return ToolResult(ok: true, stdout: "Clicked \(x) \(y).")
    }

    private func executeType(_ args: ToolArguments) async throws -> ToolResult {
        let text = try args.requiredString("text")
        try await backend.type(text)
        return ToolResult(ok: true, stdout: "Typed \(text.count) characters.")
    }

    private func executeScroll(_ args: ToolArguments) async throws -> ToolResult {
        let dx = args.int("dx") ?? 0
        let dy = args.int("dy") ?? 0
        try await backend.scroll(dx: dx, dy: dy)
        return ToolResult(ok: true, stdout: "Scrolled dx \(dx), dy \(dy).")
    }

    private func executeMove(_ args: ToolArguments) async throws -> ToolResult {
        let x = try args.requiredInt("x")
        let y = try args.requiredInt("y")
        try await backend.moveCursor(x: x, y: y)
        return ToolResult(ok: true, stdout: "Moved cursor to \(x) \(y).")
    }

    private func executeKey(_ args: ToolArguments) async throws -> ToolResult {
        let key = try args.requiredString("key")
        try await backend.pressKey(key)
        return ToolResult(ok: true, stdout: "Pressed \(key).")
    }

    private func executeWorkflowRecordStart(_ args: ToolArguments) async throws -> ToolResult {
        guard let recorder = workflowRecordingBackend() else {
            return ToolResult(ok: false, error: "Workflow recording is unavailable on this Computer Use backend.")
        }
        let goal = try args.requiredString("goal").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else {
            return ToolResult(ok: false, error: "Describe the workflow before recording it.")
        }
        let sessionDirectory = artifactDirectory
            .appendingPathComponent("workflow-recording-\(UUID().uuidString)", isDirectory: true)
        let status = try await recorder.startWorkflowRecording(WorkflowRecordingRequest(
            goal: goal,
            originThreadID: originThreadID,
            projectID: projectID,
            workspaceRoot: workspaceRoot,
            artifactDirectory: sessionDirectory.path
        ))
        return ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(status))
    }

    private func executeWorkflowRecordStop() async throws -> ToolResult {
        guard let recorder = workflowRecordingBackend() else {
            return ToolResult(ok: false, error: "Workflow recording is unavailable on this Computer Use backend.")
        }
        let capture = try await recorder.stopWorkflowRecording()
        return ToolResult(
            ok: true,
            stdout: try JSONHelpers.encodePretty(capture),
            artifacts: capture.artifactPaths
        )
    }

    private func workflowRecordingBackend() -> (any WorkflowRecordingBackend)? {
        backend as? any WorkflowRecordingBackend
    }

    private func preflightFailure(for toolName: String) async -> ToolResult? {
        guard Self.isComputerUseTool(toolName) else {
            return nil
        }
        // Stopping must remain available even if permissions are revoked mid-recording.
        guard toolName != ToolDefinition.workflowRecordStop.name else { return nil }

        let status = backend.status
        if let unavailableReason = status.unavailableReason {
            return ToolResult(
                ok: false,
                error: Self.unavailablePreflightMessage(
                    reason: unavailableReason,
                    toolName: toolName
                )
            )
        }

        let missingPermissions = Self.missingPermissions(for: toolName, status: status)
        guard !missingPermissions.isEmpty else {
            guard Self.requiresAppApproval(toolName) else { return nil }
            return await appApprovalPreflightFailure(for: toolName)
        }

        return ToolResult(
            ok: false,
            error: Self.permissionPreflightMessage(
                missingPermissions: missingPermissions,
                toolName: toolName
            )
        )
    }

    private func appApprovalPreflightFailure(for toolName: String) async -> ToolResult? {
        guard !appApprovalPolicy.isUnrestricted else { return nil }
        guard let foregroundProvider = foregroundApplicationProvider() else {
            return ToolResult(
                ok: false,
                error: "Computer Use \(Self.toolDisplayName(for: toolName)) needs app approval, "
                    + "but this backend cannot identify the focused application."
            )
        }
        let application = await foregroundProvider.foregroundApplication()
        guard let failureMessage = appApprovalPolicy.failureMessage(for: application) else {
            return nil
        }
        return ToolResult(ok: false, error: failureMessage)
    }

    private static func isComputerUseTool(_ toolName: String) -> Bool {
        (ToolDefinition.computerUseDefinitions + ToolDefinition.workflowRecordingDefinitions)
            .contains { $0.name == toolName }
    }

    private static func requiresAppApproval(_ toolName: String) -> Bool {
        ToolDefinition.computerUseDefinitions.contains { $0.name == toolName }
    }

    private static func missingPermissions(
        for toolName: String,
        status: ComputerUseStatus
    ) -> [ComputerUsePermissionRequirement] {
        switch toolName {
        case ToolDefinition.computerScreenshot.name:
            return status.screenRecordingGranted ? [] : [.screenRecording]
        case ToolDefinition.computerClick.name,
             ToolDefinition.computerType.name,
             ToolDefinition.computerScroll.name,
             ToolDefinition.computerMove.name,
             ToolDefinition.computerKey.name:
            return status.accessibilityGranted ? [] : [.accessibility]
        case ToolDefinition.workflowRecordStart.name:
            var requirements: [ComputerUsePermissionRequirement] = []
            if !status.screenRecordingGranted { requirements.append(.screenRecording) }
            if !status.accessibilityGranted { requirements.append(.accessibility) }
            return requirements
        case ToolDefinition.workflowRecordStop.name:
            return []
        default:
            return []
        }
    }

    private static func permissionPreflightMessage(
        missingPermissions: [ComputerUsePermissionRequirement],
        toolName: String
    ) -> String {
        let permissionList = missingPermissions
            .map(\.displayName)
            .joined(separator: " + ")
        return "Computer Use \(toolDisplayName(for: toolName)) needs \(permissionList). "
            + "Open Computer Use setup from Settings, grant \(permissionList), then refresh status."
    }

    private static func unavailablePreflightMessage(
        reason: String,
        toolName: String
    ) -> String {
        "Computer Use \(toolDisplayName(for: toolName)) is unavailable: \(reason)"
    }

    private static func toolDisplayName(for toolName: String) -> String {
        switch toolName {
        case ToolDefinition.computerScreenshot.name:
            return "screenshot"
        case ToolDefinition.computerClick.name:
            return "click"
        case ToolDefinition.computerType.name:
            return "typing"
        case ToolDefinition.computerScroll.name:
            return "scroll"
        case ToolDefinition.computerMove.name:
            return "cursor movement"
        case ToolDefinition.computerKey.name:
            return "keyboard"
        case ToolDefinition.workflowRecordStart.name:
            return "workflow recording"
        case ToolDefinition.workflowRecordStop.name:
            return "workflow recording stop"
        default:
            return "action"
        }
    }

    private static func screenshotVisualSummary(
        width: Int,
        height: Int,
        path: String?,
        foregroundApplication: ComputerUseApplication?,
        accessibilitySnapshot: ComputerUseAccessibilitySnapshot?
    ) -> String {
        var parts = [
            "Captured \(width) x \(height) desktop screenshot"
        ]
        if let foregroundApplication {
            parts.append("foreground app: \(foregroundApplication.displayLabel)")
        }
        if let summary = accessibilitySnapshot?.summary {
            parts.append("visible controls: \(summary)")
        }
        if let path {
            parts.append("preview artifact: \(URL(fileURLWithPath: path).lastPathComponent)")
        }
        return parts.joined(separator: "; ")
    }

    private func writeScreenshotArtifact(_ screenshot: ComputerScreenshot) throws -> String? {
        guard let data = Data(base64Encoded: screenshot.pngBase64) else {
            return nil
        }
        try FileManager.default.createDirectory(
            at: artifactDirectory,
            withIntermediateDirectories: true
        )
        let url = artifactDirectory
            .appendingPathComponent("screenshot-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("png")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url.path
    }
}

private enum ComputerUsePermissionRequirement {
    case screenRecording
    case accessibility

    var displayName: String {
        switch self {
        case .screenRecording:
            return "Screen Recording"
        case .accessibility:
            return "Accessibility"
        }
    }
}
