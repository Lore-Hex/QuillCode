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
    private struct RenderedDOMPayload: Decodable {
        var url: String
        var title: String?
        var text: String?
        var outline: [String]
        var html: String?
        var viewport: String?
    }

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
            let payload = try await evaluatePayload()
            let finalURL = URL(string: payload.url) ?? webView.url ?? requestedURL
            guard let finalURL else {
                finish(.failure(BrowserLiveDOMCaptureFailure.pageNotReady))
                return
            }

            finish(.success(BrowserLiveDOMSnapshot(
                finalURL: finalURL,
                title: payload.title,
                visibleText: payload.text,
                outline: payload.outline,
                html: payload.html,
                viewportDescription: payload.viewport
            )))
        } catch let failure as BrowserLiveDOMCaptureFailure {
            finish(.failure(failure))
        } catch {
            finish(.failure(BrowserLiveDOMCaptureFailure.transport(error.localizedDescription)))
        }
    }

    private func evaluatePayload() async throws -> RenderedDOMPayload {
        let result = try await webView.evaluateJavaScript(Self.liveDOMJavaScript)
        guard let json = result as? String,
              let data = json.data(using: .utf8)
        else {
            throw BrowserLiveDOMCaptureFailure.pageNotReady
        }
        return try JSONDecoder().decode(RenderedDOMPayload.self, from: data)
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

    private static let liveDOMJavaScript = #"""
    (() => {
      const compact = (value) => (value || '').toString().replace(/\s+/g, ' ').trim();
      const limit = (value, max) => value.length > max ? value.slice(0, max) : value;
      const outline = [];
      const push = (label) => {
        const text = compact(label);
        if (text && outline.length < 48) outline.push(text);
      };

      document.querySelectorAll('h1,h2,h3,h4,h5,h6,a,button,input,textarea,select,form,img').forEach((element) => {
        const tag = element.tagName.toLowerCase();
        if (/^h[1-6]$/.test(tag)) {
          push(`${tag.toUpperCase()}: ${element.textContent}`);
        } else if (tag === 'a') {
          push(`Link: ${element.textContent || element.getAttribute('aria-label') || element.href}`);
        } else if (tag === 'button') {
          push(`Button: ${element.textContent || element.getAttribute('aria-label')}`);
        } else if (tag === 'input' || tag === 'textarea' || tag === 'select') {
          push(`Input: ${element.getAttribute('name') || element.getAttribute('placeholder') || element.getAttribute('aria-label') || tag}`);
        } else if (tag === 'form') {
          push(`Form: ${element.getAttribute('aria-label') || element.getAttribute('name') || 'form'}`);
        } else if (tag === 'img') {
          push(`Image: ${element.getAttribute('alt') || element.getAttribute('src') || 'image'}`);
        }
      });

      const html = document.documentElement ? document.documentElement.outerHTML : '';
      return JSON.stringify({
        url: location.href,
        title: document.title || '',
        text: limit(compact(document.body ? document.body.innerText : ''), 12000),
        outline: outline,
        html: limit(html, 512000),
        viewport: `${window.innerWidth}x${window.innerHeight} @${window.devicePixelRatio || 1}x`
      });
    })()
    """#
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
