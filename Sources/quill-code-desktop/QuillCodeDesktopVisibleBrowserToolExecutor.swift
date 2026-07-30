import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
enum QuillCodeDesktopVisibleBrowserToolExecutor {
    static func execute(
        _ call: ToolCall,
        browserCoordinator: QuillCodeDesktopBrowserCoordinator,
        navigationContext: BrowserNavigationContext? = nil
    ) async -> ToolResult? {
        switch call.name {
        case ToolDefinition.browserOpen.name:
            return await open(call, browserCoordinator: browserCoordinator, context: navigationContext)
        case ToolDefinition.browserInspect.name:
            return await browserCoordinator.inspectLiveDOMSnapshotInOpenSession()
        case ToolDefinition.browserClick.name:
            return await click(call, browserCoordinator: browserCoordinator)
        case ToolDefinition.browserType.name:
            return await type(call, browserCoordinator: browserCoordinator)
        case ToolDefinition.browserScript.name:
            return await script(call, browserCoordinator: browserCoordinator)
        default:
            return nil
        }
    }

    /// What `host.browser.open` needs beyond the coordinator: the workspace model whose browser
    /// state must stay in sync, the root used to resolve relative/file targets, and the UI refresh.
    /// Optional so every existing caller (and every test) keeps compiling and keeps the old
    /// metadata-only behavior when no live surface is wired.
    @MainActor
    struct BrowserNavigationContext {
        var model: QuillCodeWorkspaceModel
        var workspaceRoot: URL
        var refresh: @MainActor () -> Void

        init(
            model: QuillCodeWorkspaceModel,
            workspaceRoot: URL,
            refresh: @escaping @MainActor () -> Void
        ) {
            self.model = model
            self.workspaceRoot = workspaceRoot
            self.refresh = refresh
        }
    }

    private static func open(
        _ call: ToolCall,
        browserCoordinator: QuillCodeDesktopBrowserCoordinator,
        context: BrowserNavigationContext?
    ) async -> ToolResult? {
        // No live surface wired -> nil, so the caller falls back to the legacy state-only executor.
        guard let context else { return nil }
        guard let address = openTarget(from: call) else { return nil }
        return await browserCoordinator.openSessionAndCaptureLiveDOM(
            model: context.model,
            addressDraft: address,
            workspaceRoot: context.workspaceRoot,
            refresh: context.refresh
        )
    }

    /// Mirrors the argument keys the legacy state-only executor accepts, so a model that already
    /// says `{"address": …}` or `{"href": …}` keeps working on the navigating path too.
    private static let openArgumentKeys = ["url", "address", "href", "target", "page"]

    private static func openTarget(from call: ToolCall) -> String? {
        guard let arguments = try? ToolArguments(call.argumentsJSON) else { return nil }
        for key in openArgumentKeys {
            guard let value = arguments.string(key) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func click(
        _ call: ToolCall,
        browserCoordinator: QuillCodeDesktopBrowserCoordinator
    ) async -> ToolResult {
        do {
            let arguments = try ToolArguments(call.argumentsJSON)
            let selector = try arguments.requiredString("selector")
            let result = try await browserCoordinator.clickInOpenSession(selector: selector)
            return actionResult(action: "click", selector: selector, summary: result.summary)
        } catch {
            return ToolResult(ok: false, error: actionErrorMessage(error))
        }
    }

    private static func type(
        _ call: ToolCall,
        browserCoordinator: QuillCodeDesktopBrowserCoordinator
    ) async -> ToolResult {
        do {
            let arguments = try ToolArguments(call.argumentsJSON)
            let selector = try arguments.requiredString("selector")
            let text = try arguments.requiredString("text")
            let submit = arguments.bool("submit") ?? false
            let result = try await browserCoordinator.typeInOpenSession(
                selector: selector,
                text: text,
                submit: submit
            )
            return actionResult(
                action: "type",
                selector: selector,
                summary: result.summary,
                submitted: submit
            )
        } catch {
            return ToolResult(ok: false, error: actionErrorMessage(error))
        }
    }

    private static func actionResult(
        action: String,
        selector: String,
        summary: String,
        submitted: Bool? = nil
    ) -> ToolResult {
        let output = BrowserActionToolOutput(
            action: action,
            selector: selector,
            summary: summary,
            submitted: submitted
        )
        return ToolResult(
            ok: true,
            stdout: (try? JSONHelpers.encodePretty(output)) ?? summary
        )
    }

    private static func script(
        _ call: ToolCall,
        browserCoordinator: QuillCodeDesktopBrowserCoordinator
    ) async -> ToolResult {
        do {
            let arguments = try ToolArguments(call.argumentsJSON)
            let source = try arguments.requiredString("source", allowingEmpty: true)
            let result = try await browserCoordinator.evaluateJavaScriptInOpenSession(source)
            let output = BrowserScriptToolOutput(
                title: result.title,
                url: result.url.absoluteString,
                value: result.valueDescription
            )
            return ToolResult(
                ok: true,
                stdout: (try? JSONHelpers.encodePretty(output)) ?? result.valueDescription
            )
        } catch {
            return ToolResult(ok: false, error: scriptErrorMessage(error))
        }
    }

    private static func actionErrorMessage(_ error: Error) -> String {
        switch error {
        case DesktopBrowserSessionActionError.noOpenSession,
            DesktopBrowserSessionActionError.noSelectedTab:
            return "No visible browser session is open. Open a browser session first, then retry the browser action."
        case DesktopBrowserSessionActionError.emptySelector:
            return "No browser selector was specified."
        case DesktopBrowserSessionActionError.emptyText:
            return "No text was specified for the browser type action."
        case DesktopBrowserSessionActionError.actionFailed(let message),
            DesktopBrowserSessionActionError.decodingFailed(let message):
            return message
        default:
            return String(describing: error)
        }
    }

    private static func scriptErrorMessage(_ error: Error) -> String {
        switch error {
        case DesktopBrowserSessionScriptError.noOpenSession,
            DesktopBrowserSessionScriptError.noSelectedTab:
            return "No visible browser session is open. Open a browser session first, then retry the browser script."
        case DesktopBrowserSessionScriptError.emptySource:
            return "No browser script source was specified."
        default:
            return String(describing: error)
        }
    }
}
