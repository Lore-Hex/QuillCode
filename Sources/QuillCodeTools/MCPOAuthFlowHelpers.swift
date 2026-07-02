import Foundation

extension MCPOAuthFlow {
    func fetchJSON<T: Decodable>(_ url: URL) -> T? {
        let request = MCPHTTPRequest(
            url: url,
            method: "GET",
            headers: ["Accept": "application/json"],
            timeout: 15,
            maxResponseBytes: 512 * 1024
        )
        guard let response = try? httpClient.perform(request),
              (200..<300).contains(response.statusCode),
              !response.bodyExceededMaxBytes else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: response.body)
    }

    /// The scheme+host+port origin of a URL, validated for http/https and a real host.
    static func origin(of url: URL) throws -> URL {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            throw MCPOAuthError.invalidServerURL(url.absoluteString)
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        guard let origin = components.url else {
            throw MCPOAuthError.invalidServerURL(url.absoluteString)
        }
        return origin
    }

    /// Candidate well-known URLs for protected-resource metadata: the resource-path variant
    /// (well-known segment inserted before the path) and the origin-root variant.
    static func wellKnownCandidates(origin: URL, serverURL: URL, suffix: String) -> [URL] {
        var urls: [URL] = []
        let path = serverURL.path
        if !path.isEmpty, path != "/" {
            if let scoped = URL(string: "/.well-known/\(suffix)\(path)", relativeTo: origin)?.absoluteURL {
                urls.append(scoped)
            }
        }
        if let root = URL(string: "/.well-known/\(suffix)", relativeTo: origin)?.absoluteURL {
            urls.append(root)
        }
        return urls
    }

    static func formURLEncoded(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    /// A bounded, log-safe preview of an error body — never includes token material because
    /// error bodies are OAuth error JSON, and we cap length to avoid dumping huge pages.
    static func previewBody(_ data: Data, limit: Int = 512) -> String {
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
