import Foundation

/// SSRF gate for `host.web.fetch`: decides whether a URL points at the public web or at
/// something internal that an agent-driven GET must never reach (cloud metadata endpoints,
/// loopback services, RFC 1918/4193 ranges, intranet hostnames).
///
/// This is the fetch-side counterpart of `StaticSafetyDownloadPolicy`'s host gate for shell
/// downloads and follows the same normalization rules (lowercasing, stripping the FQDN-root
/// trailing dot, fail-closed when a host cannot be classified). It must be applied to the
/// INITIAL URL and to EVERY redirect target — a public page that 302s to
/// `http://169.254.169.254/…` is the classic SSRF laundering move.
///
/// The gate classifies textually (IP literals and hostname shape). It does not resolve DNS,
/// so a public hostname that resolves to an internal address (DNS rebinding) is out of scope
/// here; the gate's job is to stop direct and redirect-laundered internal targets.
public enum WebFetchHostGate {
    /// Returns a human-readable reason the URL must not be fetched, or nil when it is allowed.
    public static func blockReason(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return "only http and https URLs are supported"
        }
        // Userinfo is rejected outright: `http://allowed@evil/` style URLs are a classic
        // parser-differential vector (our gate and the transport disagreeing about where the
        // host starts), and no legitimate doc/RFC fetch needs inline credentials.
        if hasNonEmptyUser(url) || url.password != nil {
            return "URLs with embedded credentials are not allowed"
        }
        guard let rawHost = url.host, !rawHost.isEmpty else {
            return "the URL has no host"
        }
        // Same trailing-dot normalization as StaticSafetyRequest.normalizedHost: `localhost.`
        // and `localhost` must classify identically (FQDN-root parser differential).
        var host = rawHost.lowercased()
        if host.hasSuffix(".") {
            host = String(host.dropLast())
        }
        guard !host.isEmpty else {
            return "the URL has no host"
        }

        if let ipv4 = parseIPv4(host) {
            return blockReasonForIPv4(ipv4)
        }
        if host.contains(":") {
            // Bracketed IPv6 literal (URL.host strips the brackets). Anything colon-y that
            // inet_pton cannot parse is fail-closed: we cannot classify it, so we refuse it.
            guard let ipv6 = parseIPv6(host) else {
                return "the IPv6 host could not be parsed"
            }
            return blockReasonForIPv6(ipv6)
        }
        return blockReasonForHostname(host)
    }

    // MARK: - Hostname classification

    private static func blockReasonForHostname(_ host: String) -> String? {
        if host == "localhost" || host.hasSuffix(".localhost") {
            return "\(host) is a loopback host"
        }
        for suffix in blockedInternalSuffixes where host == suffix || host.hasSuffix(".\(suffix)") {
            return "\(host) is an internal-network host"
        }
        guard host.contains(".") else {
            // Single-label names (`intranet`, `router`, `metadata`) only resolve on internal
            // networks; the public web is always multi-label.
            return "single-label hostnames are not routable on the public web"
        }
        // A host whose every label is purely numeric (or 0x-hex) is an IP literal in a form
        // `inet_pton` rejects but many resolvers accept (`0177.0.0.1`, `127.1`). We cannot
        // range-check it, so fail closed — mirroring StaticSafetyDownloadPolicy's rule that an
        // unparseable URL drops the command rather than slipping through.
        if hostLabelsAreAllNumeric(host) {
            return "numeric hosts must be written as a full dotted-quad IP address"
        }
        return nil
    }

    /// Reserved / internal-only DNS suffixes. `.local` is mDNS, `.internal` is the cloud
    /// metadata convention (`metadata.google.internal`), `.home.arpa` is RFC 8375.
    private static let blockedInternalSuffixes: [String] = [
        "local", "internal", "intranet", "lan", "home", "corp", "home.arpa"
    ]

    private static func hostLabelsAreAllNumeric(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return true }
        return labels.allSatisfy { label in
            if label.isEmpty { return true }
            if label.allSatisfy({ $0.isASCII && $0.isWholeNumber }) { return true }
            if label.hasPrefix("0x") || label.hasPrefix("0X") {
                return label.dropFirst(2).allSatisfy(\.isHexDigit)
            }
            return false
        }
    }

    private static func hasNonEmptyUser(_ url: URL) -> Bool {
        guard let user = url.user else { return false }
        return !user.isEmpty
    }

    // MARK: - IPv4

    /// STRICT dotted-quad parser — deliberately hand-rolled instead of `inet_pton`, whose
    /// platform-dependent leniency is itself a parser differential: a label with a leading
    /// zero ("0177.0.0.1") is octal 127.0.0.1 to `inet_aton`-style resolvers but decimal 177
    /// to some `inet_pton`s. Anything non-canonical returns nil here and then fails closed via
    /// the all-numeric-labels hostname rule.
    private static func parseIPv4(_ host: String) -> UInt32? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else {
            return nil
        }
        var value: UInt32 = 0
        for label in labels {
            guard !label.isEmpty,
                  label.count <= 3,
                  label.allSatisfy({ $0.isASCII && $0.isWholeNumber }),
                  label == "0" || !label.hasPrefix("0"),
                  let octet = UInt32(label),
                  octet <= 255
            else {
                return nil
            }
            value = (value << 8) | octet
        }
        return value
    }

    private static func blockReasonForIPv4(_ value: UInt32) -> String? {
        let ranges: [(mask: UInt32, prefix: UInt32, label: String)] = [
            (0xFF00_0000, 0x0000_0000, "the 0.0.0.0/8 range"),
            (0xFF00_0000, 0x0A00_0000, "the private 10.0.0.0/8 range"),
            (0xFFC0_0000, 0x6440_0000, "the carrier-grade NAT 100.64.0.0/10 range"),
            (0xFF00_0000, 0x7F00_0000, "the loopback 127.0.0.0/8 range"),
            (0xFFFF_0000, 0xA9FE_0000, "the link-local 169.254.0.0/16 range (cloud metadata)"),
            (0xFFF0_0000, 0xAC10_0000, "the private 172.16.0.0/12 range"),
            (0xFFFF_FF00, 0xC000_0000, "the IETF protocol 192.0.0.0/24 range"),
            (0xFFFF_0000, 0xC0A8_0000, "the private 192.168.0.0/16 range"),
            (0xFFFE_0000, 0xC612_0000, "the benchmarking 198.18.0.0/15 range"),
            (0xF000_0000, 0xE000_0000, "the multicast 224.0.0.0/4 range"),
            (0xF000_0000, 0xF000_0000, "the reserved 240.0.0.0/4 range")
        ]
        for range in ranges where (value & range.mask) == range.prefix {
            return "the IP address is in \(range.label)"
        }
        return nil
    }

    // MARK: - IPv6

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else {
            return nil
        }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func blockReasonForIPv6(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 16 else {
            return "the IPv6 host could not be parsed"
        }
        if bytes.allSatisfy({ $0 == 0 }) {
            return "the IPv6 unspecified address is not routable"
        }
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 {
            return "::1 is the IPv6 loopback address"
        }
        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 {
            return "the IP address is in the link-local fe80::/10 range"
        }
        if (bytes[0] & 0xFE) == 0xFC {
            return "the IP address is in the unique-local fc00::/7 range"
        }
        if bytes[0] == 0xFF {
            return "the IP address is in the multicast ff00::/8 range"
        }
        // IPv4-mapped (::ffff:a.b.c.d) and IPv4-compatible (::a.b.c.d) forms smuggle an IPv4
        // target through the IPv6 parser — classify the embedded IPv4 address instead.
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return blockReasonForEmbeddedIPv4(bytes) ?? nil
        }
        if bytes[0..<12].allSatisfy({ $0 == 0 }) {
            return blockReasonForEmbeddedIPv4(bytes) ?? "IPv4-compatible IPv6 addresses are not allowed"
        }
        // NAT64 (64:ff9b::/96) and 6to4 (2002::/16) both embed an IPv4 address that a gateway
        // may route internally; neither is a legitimate way to reach a public docs page.
        if bytes[0] == 0x00, bytes[1] == 0x64, bytes[2] == 0xFF, bytes[3] == 0x9B {
            return "NAT64 (64:ff9b::/96) addresses are not allowed"
        }
        if bytes[0] == 0x20, bytes[1] == 0x02 {
            return "6to4 (2002::/16) addresses are not allowed"
        }
        return nil
    }

    private static func blockReasonForEmbeddedIPv4(_ bytes: [UInt8]) -> String? {
        let value = (UInt32(bytes[12]) << 24)
            | (UInt32(bytes[13]) << 16)
            | (UInt32(bytes[14]) << 8)
            | UInt32(bytes[15])
        return blockReasonForIPv4(value)
    }
}
