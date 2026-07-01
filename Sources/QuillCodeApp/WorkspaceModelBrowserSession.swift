import Foundation

extension QuillCodeWorkspaceModel {
    @discardableResult
    public func addBrowserComment(_ text: String) -> Bool {
        mutateBrowserState { browser, _ in
            WorkspaceBrowserWorkflow.addComment(text, browser: &browser)
        }
    }

    @discardableResult
    public func applyBrowserSessionUpdate(_ update: BrowserSessionUpdate) -> Bool {
        applyBrowserSessionMutation {
            WorkspaceBrowserWorkflow.applySessionUpdate(update, browser: &$0)
        }
    }

    @discardableResult
    public func newBrowserTab() -> UUID {
        let tabID = mutateBrowserState { browser, _ in
            WorkspaceBrowserWorkflow.newTab(browser: &browser)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return tabID
    }

    @discardableResult
    public func selectBrowserTab(id: UUID) -> Bool {
        applyBrowserSessionMutation {
            WorkspaceBrowserWorkflow.selectTab(id: id, browser: &$0)
        }
    }

    @discardableResult
    public func closeBrowserTab(id: UUID) -> Bool {
        applyBrowserSessionMutation {
            WorkspaceBrowserWorkflow.closeTab(id: id, browser: &$0)
        }
    }

    private func applyBrowserSessionMutation(_ mutation: (inout BrowserState) -> Bool) -> Bool {
        let applied = mutateBrowserState { browser, _ in
            mutation(&browser)
        }
        guard applied else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }
}
