import Foundation

extension QuillCodeWorkspaceModel {
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
            WorkspaceBrowserWorkflow.beginSnapshotFetch(
                browser: &browser,
                domainPolicy: root.config.browserDomainPolicy
            )
        }
        guard let request else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)

        do {
            let fetchedPage = try await pageFetcher.fetchHTML(from: request.fetchURL)
            return applyBrowserSnapshotFetchSuccess(fetchedPage, request: request)
        } catch {
            return applyBrowserSnapshotFetchFailure(error, request: request)
        }
    }

    @discardableResult
    public func refreshRenderedBrowserSnapshot(capturer: any BrowserLiveDOMCapturing) async -> Bool {
        let request = mutateBrowserState { browser, _ in
            WorkspaceBrowserWorkflow.beginLiveDOMCapture(
                browser: &browser,
                domainPolicy: root.config.browserDomainPolicy
            )
        }
        guard let request else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)

        do {
            let snapshot = try await capturer.captureLiveDOM(for: request.captureURL)
            return applyBrowserLiveDOMCaptureSuccess(snapshot, request: request)
        } catch {
            return applyBrowserLiveDOMCaptureFailure(error, request: request)
        }
    }

    private func applyBrowserSnapshotFetchSuccess(
        _ fetchedPage: BrowserFetchedPage,
        request: WorkspaceBrowserSnapshotRequest
    ) -> Bool {
        applyBrowserAsyncMutation {
            WorkspaceBrowserWorkflow.applySnapshotFetchSuccess(
                fetchedPage,
                request: request,
                browser: &$0,
                lastError: &$1,
                domainPolicy: root.config.browserDomainPolicy
            )
        }
    }

    private func applyBrowserSnapshotFetchFailure(
        _ error: any Error,
        request: WorkspaceBrowserSnapshotRequest
    ) -> Bool {
        applyBrowserAsyncMutation {
            WorkspaceBrowserWorkflow.applySnapshotFetchFailure(
                error,
                request: request,
                browser: &$0,
                lastError: &$1
            )
        }
    }

    private func applyBrowserLiveDOMCaptureSuccess(
        _ snapshot: BrowserLiveDOMSnapshot,
        request: WorkspaceBrowserLiveDOMRequest
    ) -> Bool {
        applyBrowserAsyncMutation {
            WorkspaceBrowserWorkflow.applyLiveDOMCaptureSuccess(
                snapshot,
                request: request,
                browser: &$0,
                lastError: &$1,
                domainPolicy: root.config.browserDomainPolicy
            )
        }
    }

    private func applyBrowserLiveDOMCaptureFailure(
        _ error: any Error,
        request: WorkspaceBrowserLiveDOMRequest
    ) -> Bool {
        _ = applyBrowserAsyncMutation {
            WorkspaceBrowserWorkflow.applyLiveDOMCaptureFailure(
                error,
                request: request,
                browser: &$0,
                lastError: &$1
            )
        }
        return false
    }

    private func applyBrowserAsyncMutation(
        _ mutation: (inout BrowserState, inout String?) -> Bool
    ) -> Bool {
        let applied = mutateBrowserState(mutation)
        guard applied else { return false }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }
}
