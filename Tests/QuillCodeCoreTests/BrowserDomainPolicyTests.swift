import Foundation
import XCTest
@testable import QuillCodeCore

final class BrowserDomainPolicyTests: XCTestCase {
    func testNormalizesDomainsAndURLInputs() {
        let policy = BrowserDomainPolicy(
            allowedDomains: [
                " HTTPS://TrustedRouter.COM/docs ",
                "*.example.com",
                ".localhost",
                "trustedrouter.com"
            ],
            blockedDomains: [
                "http://Bad.Example.com:443/path",
                "bad.example.com"
            ]
        )

        XCTAssertEqual(policy.allowedDomains, ["trustedrouter.com", "example.com", "localhost"])
        XCTAssertEqual(policy.blockedDomains, ["bad.example.com"])
    }

    func testBlocklistWinsOverAllowlistAndMatchesSubdomains() throws {
        let policy = BrowserDomainPolicy(
            allowedDomains: ["example.com"],
            blockedDomains: ["private.example.com"]
        )

        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://docs.example.com"))))

        let decision = policy.decision(for: try XCTUnwrap(URL(string: "https://api.private.example.com")))
        guard case .block(let reason) = decision else {
            return XCTFail("Expected private subdomain to be blocked")
        }
        XCTAssertTrue(reason.contains("private.example.com"))
    }

    func testAllowlistBlocksUnlistedNetworkHostsButAllowsFiles() throws {
        let policy = BrowserDomainPolicy(allowedDomains: ["trustedrouter.com"])

        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://app.trustedrouter.com"))))
        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertTrue(policy.allows(URL(fileURLWithPath: "/tmp/preview.html")))
    }
}
