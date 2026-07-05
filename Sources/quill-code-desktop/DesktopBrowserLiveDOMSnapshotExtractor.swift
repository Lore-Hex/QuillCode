import Foundation
import QuillCodeApp

#if canImport(WebKit)
import WebKit

@MainActor
enum DesktopBrowserLiveDOMSnapshotExtractor {
    private struct RenderedDOMPayload: Decodable {
        var url: String
        var title: String?
        var text: String?
        var outline: [String]
        var html: String?
        var viewport: String?
    }

    static func snapshot(from webView: WKWebView, fallbackURL: URL?) async throws -> BrowserLiveDOMSnapshot {
        let payload = try await evaluatePayload(in: webView)
        let finalURL = URL(string: payload.url) ?? webView.url ?? fallbackURL
        guard let finalURL else {
            throw BrowserLiveDOMCaptureFailure.pageNotReady
        }
        return BrowserLiveDOMSnapshot(
            finalURL: finalURL,
            title: payload.title,
            visibleText: payload.text,
            outline: payload.outline,
            html: payload.html,
            viewportDescription: payload.viewport
        )
    }

    private static func evaluatePayload(in webView: WKWebView) async throws -> RenderedDOMPayload {
        let result = try await webView.evaluateJavaScript(liveDOMJavaScript)
        guard let json = result as? String,
              let data = json.data(using: .utf8)
        else {
            throw BrowserLiveDOMCaptureFailure.pageNotReady
        }
        return try JSONDecoder().decode(RenderedDOMPayload.self, from: data)
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
#endif
