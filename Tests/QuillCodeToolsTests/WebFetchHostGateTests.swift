import XCTest
@testable import QuillCodeTools

final class WebFetchHostGateTests: XCTestCase {
    private func blockReason(_ urlString: String, file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard let url = URL(string: urlString) else {
            XCTFail("could not build URL from \(urlString)", file: file, line: line)
            return "unparseable"
        }
        return WebFetchHostGate.blockReason(for: url)
    }

    private func assertAllowed(_ urlString: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(blockReason(urlString, file: file, line: line), "expected \(urlString) to be allowed", file: file, line: line)
    }

    private func assertBlocked(_ urlString: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(blockReason(urlString, file: file, line: line), "expected \(urlString) to be blocked", file: file, line: line)
    }

    // MARK: - Allowed public hosts

    func testPublicHostsAreAllowed() {
        assertAllowed("https://example.com")
        assertAllowed("http://example.com/path?q=1")
        assertAllowed("https://docs.swift.org/swift-book/")
        assertAllowed("https://api.github.com:8443/repos")
        assertAllowed("https://example.com./trailing-dot-is-public")
        assertAllowed("http://93.184.216.34/")
        assertAllowed("https://[2606:4700:4700::1111]/")
        assertAllowed("https://[::ffff:8.8.8.8]/")
    }

    // MARK: - Schemes and URL shape

    func testNonHTTPSchemesAreBlocked() {
        assertBlocked("ftp://example.com/file")
        assertBlocked("file:///etc/passwd")
        assertBlocked("gopher://example.com")
    }

    func testEmbeddedCredentialsAreBlocked() {
        assertBlocked("https://user:secret@example.com/")
        assertBlocked("https://127.0.0.1@example.com/") // confusion bait, still credentials
    }

    func testMissingHostIsBlocked() {
        assertBlocked("https:///path-without-host")
    }

    // MARK: - Loopback and internal hostnames

    func testLoopbackHostnamesAreBlocked() {
        assertBlocked("http://localhost/")
        assertBlocked("http://localhost:3000/")
        assertBlocked("http://LOCALHOST/")
        assertBlocked("http://localhost./") // FQDN-root trailing dot
        assertBlocked("http://sub.localhost/")
    }

    func testInternalSuffixesAreBlocked() {
        assertBlocked("http://metadata.google.internal/computeMetadata/v1/")
        assertBlocked("http://printer.local/")
        assertBlocked("http://gateway.lan/")
        assertBlocked("http://files.intranet/")
        assertBlocked("http://nas.home.arpa/")
        assertBlocked("http://server.corp/")
    }

    func testSingleLabelHostnamesAreBlocked() {
        assertBlocked("http://intranet/")
        assertBlocked("http://router/")
        assertBlocked("http://metadata/")
    }

    // MARK: - IPv4 ranges

    func testInternalIPv4RangesAreBlocked() {
        assertBlocked("http://127.0.0.1/")
        assertBlocked("http://127.8.8.8/")
        assertBlocked("http://0.0.0.0/")
        assertBlocked("http://10.0.0.1/")
        assertBlocked("http://10.255.255.255/")
        assertBlocked("http://172.16.0.1/")
        assertBlocked("http://172.31.255.254/")
        assertBlocked("http://192.168.1.1/")
        assertBlocked("http://169.254.169.254/latest/meta-data/") // cloud metadata endpoint
        assertBlocked("http://169.254.169.254./") // trailing-dot differential
        assertBlocked("http://100.64.0.1/")
        assertBlocked("http://198.18.0.1/")
        assertBlocked("http://192.0.0.192/")
        assertBlocked("http://224.0.0.1/")
        assertBlocked("http://255.255.255.255/")
    }

    func testAdjacentPublicIPv4RangesAreAllowed() {
        assertAllowed("http://172.32.0.1/")   // just past 172.16/12
        assertAllowed("http://11.0.0.1/")     // just past 10/8
        assertAllowed("http://100.128.0.1/")  // just past 100.64/10
        assertAllowed("http://169.253.1.1/")  // just below 169.254/16
    }

    func testObfuscatedNumericIPv4FormsFailClosed() {
        assertBlocked("http://2130706433/")     // decimal 127.0.0.1, single label
        assertBlocked("http://127.1/")          // BSD shorthand
        assertBlocked("http://0177.0.0.1/")     // octal-style labels
        assertBlocked("http://0x7f.0x0.0x0.0x1/") // hex labels
        assertBlocked("http://0x7f000001/")     // hex single label
    }

    // MARK: - IPv6 ranges

    func testInternalIPv6RangesAreBlocked() {
        assertBlocked("http://[::1]/")
        assertBlocked("http://[::]/")
        assertBlocked("http://[fe80::1]/")
        assertBlocked("http://[fc00::1]/")
        assertBlocked("http://[fd12:3456:789a::1]/")
        assertBlocked("http://[ff02::1]/")
        assertBlocked("http://[::ffff:127.0.0.1]/")  // mapped loopback
        assertBlocked("http://[::ffff:169.254.169.254]/") // mapped metadata
        assertBlocked("http://[::ffff:10.0.0.1]/")
        assertBlocked("http://[64:ff9b::808:808]/") // NAT64
        assertBlocked("http://[2002:7f00:1::]/")    // 6to4
        assertBlocked("http://[::7f00:1]/")         // IPv4-compatible form
    }

    // MARK: - Reason quality

    func testBlockReasonsAreDescriptive() {
        XCTAssertTrue(blockReason("http://169.254.169.254/")?.contains("link-local") == true)
        XCTAssertTrue(blockReason("http://localhost/")?.contains("loopback") == true)
        XCTAssertTrue(blockReason("ftp://example.com/")?.contains("http") == true)
    }
}
