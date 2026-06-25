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

    @discardableResult
    public func openBrowserPreview(
        _ input: String? = nil,
        workspaceRoot: URL? = nil,
        pageFetcher: any BrowserPageFetching
    ) async -> Bool {
        guard openBrowserPreview(input, workspaceRoot: workspaceRoot) else { return false }
        _ = await refreshBrowserSnapshot(pageFetcher: pageFetcher)
        return true
    }

    @discardableResult
    public func refreshBrowserSnapshot(pageFetcher: any BrowserPageFetching) async -> Bool {
        let request = mutateBrowserState { browser, _ in
            WorkspaceBrowserWorkflow.beginSnapshotFetch(browser: &browser)
        }
        guard let request else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)

        do {
            let fetchedPage = try await pageFetcher.fetchHTML(from: request.fetchURL)
            let applied = mutateBrowserState { browser, lastError in
                WorkspaceBrowserWorkflow.applySnapshotFetchSuccess(
                    fetchedPage,
                    request: request,
                    browser: &browser,
                    lastError: &lastError
                )
            }
            guard applied else { return false }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        } catch {
            let applied = mutateBrowserState { browser, lastError in
                WorkspaceBrowserWorkflow.applySnapshotFetchFailure(
                    error,
                    request: request,
                    browser: &browser,
                    lastError: &lastError
                )
            }
            guard applied else { return false }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return false
        }
    }

    @discardableResult
    public func refreshRenderedBrowserSnapshot(capturer: any BrowserLiveDOMCapturing) async -> Bool {
        let request = mutateBrowserState { browser, _ in
            WorkspaceBrowserWorkflow.beginLiveDOMCapture(browser: &browser)
        }
        guard let request else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)

        do {
            let snapshot = try await capturer.captureLiveDOM(for: request.captureURL)
            let applied = mutateBrowserState { browser, lastError in
                WorkspaceBrowserWorkflow.applyLiveDOMCaptureSuccess(
                    snapshot,
                    request: request,
                    browser: &browser,
                    lastError: &lastError
                )
            }
            guard applied else { return false }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        } catch {
            let applied = mutateBrowserState { browser, lastError in
                WorkspaceBrowserWorkflow.applyLiveDOMCaptureFailure(
                    error,
                    request: request,
                    browser: &browser,
                    lastError: &lastError
                )
            }
            guard applied else { return false }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return false
        }
    }

    @discardableResult
    public func addBrowserComment(_ text: String) -> Bool {
        mutateBrowserState { browser, _ in
            WorkspaceBrowserWorkflow.addComment(text, browser: &browser)
        }
    }
}
