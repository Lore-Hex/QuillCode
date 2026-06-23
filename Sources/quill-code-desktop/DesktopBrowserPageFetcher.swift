import Foundation
import QuillCodeApp

final class URLSessionBrowserPageFetcher: BrowserPageFetching, @unchecked Sendable {
    private let session: URLSession
    private let maxBytes: Int
    private let timeout: TimeInterval

    init(
        session: URLSession = .shared,
        maxBytes: Int = BrowserFetchedPage.defaultMaxHTMLBytes,
        timeout: TimeInterval = 5
    ) {
        self.session = session
        self.maxBytes = maxBytes
        self.timeout = timeout
    }

    func fetchHTML(from url: URL) async throws -> BrowserFetchedPage {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw BrowserPageFetchFailure.unsupportedScheme(url.scheme)
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("QuillCode BrowserPreview", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BrowserPageFetchFailure.invalidResponse
            }
            guard (200..<400).contains(httpResponse.statusCode) else {
                throw BrowserPageFetchFailure.httpStatus(httpResponse.statusCode)
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
            let bodyData: Data
            let wasTruncated: Bool
            if data.count > maxBytes {
                bodyData = Data(data.prefix(maxBytes))
                wasTruncated = true
            } else {
                bodyData = data
                wasTruncated = false
            }

            guard Self.isHTML(contentType: contentType) || Self.looksLikeHTML(bodyData) else {
                throw BrowserPageFetchFailure.nonHTMLContentType(contentType)
            }
            guard let html = String(data: bodyData, encoding: .utf8)
                ?? String(data: bodyData, encoding: .ascii)
            else {
                throw BrowserPageFetchFailure.undecodableText
            }

            return BrowserFetchedPage(
                finalURL: httpResponse.url ?? url,
                statusCode: httpResponse.statusCode,
                contentType: contentType,
                html: html,
                byteCount: data.count,
                wasTruncated: wasTruncated
            )
        } catch let failure as BrowserPageFetchFailure {
            throw failure
        } catch {
            throw BrowserPageFetchFailure.transport(error.localizedDescription)
        }
    }

    private static func isHTML(contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else { return false }
        return contentType.contains("text/html") || contentType.contains("application/xhtml+xml")
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        let prefix = Data(data.prefix(512))
        guard let sample = String(data: prefix, encoding: .utf8)
            ?? String(data: prefix, encoding: .ascii)
        else {
            return false
        }
        let lowercased = sample.lowercased()
        return lowercased.contains("<!doctype html") || lowercased.contains("<html")
    }
}
