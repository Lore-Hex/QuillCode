import Foundation
import QuillCodeCore

@MainActor
enum QuillCodeDesktopVisibleBrowserToolExecutor {
    static func execute(
        _ call: ToolCall,
        browserCoordinator: QuillCodeDesktopBrowserCoordinator
    ) async -> ToolResult? {
        switch call.name {
        case ToolDefinition.browserInspect.name:
            return await browserCoordinator.inspectLiveDOMSnapshotInOpenSession()
        case ToolDefinition.browserClick.name:
            return await click(call, browserCoordinator: browserCoordinator)
        case ToolDefinition.browserType.name:
            return await type(call, browserCoordinator: browserCoordinator)
        default:
            return nil
        }
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
}
