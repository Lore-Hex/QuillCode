import Foundation
import QuillCodeApp

#if canImport(WebKit)
import WebKit

enum DesktopBrowserLiveDOMProfile: Sendable {
    case persistent
    case ephemeral

    @MainActor
    func websiteDataStore() -> WKWebsiteDataStore {
        switch self {
        case .persistent:
            return .default()
        case .ephemeral:
            return .nonPersistent()
        }
    }
}

final class DesktopBrowserLiveDOMCapturer: BrowserLiveDOMCapturing, @unchecked Sendable {
    private let profile: DesktopBrowserLiveDOMProfile
    private let timeoutNanoseconds: UInt64
    private let settleDelayNanoseconds: UInt64

    init(
        profile: DesktopBrowserLiveDOMProfile = .persistent,
        timeout: TimeInterval = 8,
        settleDelay: TimeInterval = 0.25
    ) {
        self.profile = profile
        self.timeoutNanoseconds = Self.nanoseconds(for: timeout)
        self.settleDelayNanoseconds = Self.nanoseconds(for: settleDelay)
    }

    func captureLiveDOM(for url: URL) async throws -> BrowserLiveDOMSnapshot {
        let session = await WebKitBrowserLiveDOMCaptureSession(
            profile: profile,
            timeoutNanoseconds: timeoutNanoseconds,
            settleDelayNanoseconds: settleDelayNanoseconds
        )
        return try await session.capture(url)
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }
}

@MainActor
private final class WebKitBrowserLiveDOMCaptureSession: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let timeoutNanoseconds: UInt64
    private let settleDelayNanoseconds: UInt64
    private var continuation: CheckedContinuation<BrowserLiveDOMSnapshot, any Error>?
    private var requestedURL: URL?
    private var timeoutTask: Task<Void, Never>?

    init(
        profile: DesktopBrowserLiveDOMProfile,
        timeoutNanoseconds: UInt64,
        settleDelayNanoseconds: UInt64
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.websiteDataStore()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.timeoutNanoseconds = timeoutNanoseconds
        self.settleDelayNanoseconds = settleDelayNanoseconds
        super.init()
        webView.navigationDelegate = self
    }

    func capture(_ url: URL) async throws -> BrowserLiveDOMSnapshot {
        guard continuation == nil else {
            throw BrowserLiveDOMCaptureFailure.pageNotReady
        }

        requestedURL = url
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                finish(.failure(BrowserLiveDOMCaptureFailure.transport("Timed out while rendering \(url.absoluteString).")))
            }

            var request = URLRequest(url: url)
            request.setValue("QuillCode BrowserPreview", forHTTPHeaderField: "User-Agent")
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: settleDelayNanoseconds)
            await captureRenderedDOM()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        finish(.failure(BrowserLiveDOMCaptureFailure.transport(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        finish(.failure(BrowserLiveDOMCaptureFailure.transport(error.localizedDescription)))
    }

    private func captureRenderedDOM() async {
        do {
            finish(.success(try await DesktopBrowserLiveDOMSnapshotExtractor.snapshot(
                from: webView,
                fallbackURL: requestedURL
            )))
        } catch let failure as BrowserLiveDOMCaptureFailure {
            finish(.failure(failure))
        } catch {
            finish(.failure(BrowserLiveDOMCaptureFailure.transport(error.localizedDescription)))
        }
    }

    private func finish(_ result: Result<BrowserLiveDOMSnapshot, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil

        switch result {
        case .success(let snapshot):
            continuation.resume(returning: snapshot)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
#elseif os(Linux)
typealias DesktopBrowserLiveDOMCapturer = ChromiumBrowserLiveDOMCapturer
#else
final class DesktopBrowserLiveDOMCapturer: BrowserLiveDOMCapturing, @unchecked Sendable {
    func captureLiveDOM(for url: URL) async throws -> BrowserLiveDOMSnapshot {
        throw BrowserLiveDOMCaptureFailure.noRenderedSession
    }
}
#endif
