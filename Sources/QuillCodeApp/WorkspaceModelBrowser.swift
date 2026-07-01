import Foundation

extension QuillCodeWorkspaceModel {
    public func setBrowserAddressDraft(_ draft: String) {
        mutateBrowserState { browser, _ in
            browser.addressDraft = draft
        }
    }

    public func toggleBrowser() {
        mutateBrowserState { browser, _ in
            browser.isVisible.toggle()
        }
    }

    @discardableResult
    public func openBrowserPreview(_ input: String? = nil, workspaceRoot: URL? = nil) -> Bool {
        let opened = mutateBrowserState { browser, lastError in
            WorkspaceBrowserWorkflow.openPreview(
                input,
                workspaceRoot: workspaceRoot,
                browser: &browser,
                lastError: &lastError
            )
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return opened
    }

    @discardableResult
    public func goBackInBrowser() -> Bool {
        let movedBack = mutateBrowserState { browser, lastError in
            WorkspaceBrowserWorkflow.goBack(browser: &browser, lastError: &lastError)
        }
        guard movedBack else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func goForwardInBrowser() -> Bool {
        let movedForward = mutateBrowserState { browser, lastError in
            WorkspaceBrowserWorkflow.goForward(browser: &browser, lastError: &lastError)
        }
        guard movedForward else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func reloadBrowserPreview() -> Bool {
        let reloaded = mutateBrowserState { browser, lastError in
            WorkspaceBrowserWorkflow.reload(browser: &browser, lastError: &lastError)
        }
        guard reloaded else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }
}
