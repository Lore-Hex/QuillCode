import Foundation
import QuillCodeCore

struct WorkspaceBrowserToolExecutor: Sendable {
    private static let browserOpenArgumentKeys = ["url", "address", "href", "target", "page"]

    static func execute(
        _ call: ToolCall,
        workspaceRoot: URL?,
        browser: inout BrowserState,
        lastError: inout String?,
        domainPolicy: BrowserDomainPolicy = .unrestricted
    ) -> ToolResult? {
        switch call.name {
        case ToolDefinition.browserInspect.name:
            return BrowserInspector.toolResult(from: browser)
        case ToolDefinition.browserOpen.name:
            return open(
                call,
                workspaceRoot: workspaceRoot,
                browser: &browser,
                lastError: &lastError,
                domainPolicy: domainPolicy
            )
        default:
            return nil
        }
    }

    private static func open(
        _ call: ToolCall,
        workspaceRoot: URL?,
        browser: inout BrowserState,
        lastError: inout String?,
        domainPolicy: BrowserDomainPolicy
    ) -> ToolResult {
        guard let target = browserOpenTarget(from: call) else {
            return ToolResult(ok: false, error: "No browser URL was specified.")
        }
        guard WorkspaceBrowserWorkflow.openPreview(
            target,
            workspaceRoot: workspaceRoot,
            browser: &browser,
            lastError: &lastError,
            domainPolicy: domainPolicy
        ) else {
            return ToolResult(ok: false, error: lastError ?? WorkspaceBrowserWorkflow.invalidAddressError)
        }
        return BrowserInspector.toolResult(from: browser)
    }

    private static func browserOpenTarget(from call: ToolCall) -> String? {
        guard let arguments = try? ToolArguments(call.argumentsJSON) else { return nil }
        for key in browserOpenArgumentKeys {
            guard let value = arguments.string(key) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
