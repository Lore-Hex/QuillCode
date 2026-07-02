import Foundation

public enum BrowserDomainDecision: Sendable, Hashable {
    case allow
    case block(String)

    public var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }
}

public struct BrowserDomainPolicy: Codable, Sendable, Hashable {
    public var allowedDomains: [String]
    public var blockedDomains: [String]

    public static let unrestricted = BrowserDomainPolicy()

    public init(
        allowedDomains: [String] = [],
        blockedDomains: [String] = []
    ) {
        self.allowedDomains = Self.normalizedDomains(allowedDomains)
        self.blockedDomains = Self.normalizedDomains(blockedDomains)
    }

    public var isUnrestricted: Bool {
        allowedDomains.isEmpty && blockedDomains.isEmpty
    }

    public var statusLabel: String {
        if isUnrestricted { return "Unrestricted" }
        if !allowedDomains.isEmpty && !blockedDomains.isEmpty { return "Allowlist + blocklist" }
        if !allowedDomains.isEmpty { return "Allowlist" }
        return "Blocklist"
    }

    public var summary: String {
        if isUnrestricted {
            return "Browser can open any http or https domain. Local files still stay workspace-scoped by the browser resolver."
        }

        var parts: [String] = []
        if !allowedDomains.isEmpty {
            parts.append("Allowed: \(allowedDomains.joined(separator: ", "))")
        }
        if !blockedDomains.isEmpty {
            parts.append("Blocked: \(blockedDomains.joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }

    public func decision(for url: URL) -> BrowserDomainDecision {
        guard Self.isNetworkURL(url) else { return .allow }
        guard let host = Self.normalizedHost(url.host) else {
            return .block("Blocked by browser policy: network URL has no host.")
        }

        if let blockedDomain = blockedDomains.first(where: { Self.host(host, matches: $0) }) {
            return .block("Blocked by browser policy: \(host) matches blocked domain \(blockedDomain).")
        }

        guard allowedDomains.isEmpty || allowedDomains.contains(where: { Self.host(host, matches: $0) }) else {
            return .block("Blocked by browser policy: \(host) is not in allowed domains.")
        }

        return .allow
    }

    public func allows(_ url: URL) -> Bool {
        decision(for: url).isAllowed
    }

    public static func normalizedDomains(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var domains: [String] = []
        for value in values {
            guard let domain = normalizedDomain(value),
                  seen.insert(domain).inserted
            else { continue }
            domains.append(domain)
        }
        return domains
    }

    private static func isNetworkURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func normalizedDomain(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !value.contains("\\")
        else {
            return nil
        }

        if value.hasPrefix("*.") {
            value.removeFirst(2)
        }
        while value.hasPrefix(".") {
            value.removeFirst()
        }

        guard let host = normalizedHost(parsedHost(from: value)) else { return nil }
        return host
    }

    private static func parsedHost(from value: String) -> String? {
        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           let host = url.host {
            return host
        }

        if let url = URL(string: "https://\(value)"),
           let host = url.host {
            return host
        }

        return nil
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty
        else {
            return nil
        }

        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host.isEmpty ? nil : host
    }

    private static func host(_ host: String, matches domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }
}
