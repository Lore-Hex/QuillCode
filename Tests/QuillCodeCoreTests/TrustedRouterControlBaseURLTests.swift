import QuillCodeCore
import XCTest

/// The OAuth pages live on the control plane, not the inference enclave. Pointing a browser at
/// api.trustedrouter.com/v1/auth shows the user a raw JSON error ("Invalid API key") instead of the
/// sign-in form, and the enclave has no /auth/userinfo route at all -- which is exactly what a
/// first tester hit. These pin the mapping that keeps the browser flow on the control plane.
final class TrustedRouterControlBaseURLTests: XCTestCase {
    func testHostedEnclaveMapsToControlPlane() {
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: TrustedRouterDefaults.defaultAPIBaseURL),
            TrustedRouterDefaults.defaultControlBaseURL
        )
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://api.trustedrouter.com/v1/"),
            TrustedRouterDefaults.defaultControlBaseURL
        )
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://API.TRUSTEDROUTER.COM/v1"),
            TrustedRouterDefaults.defaultControlBaseURL
        )
    }

    func testRegionalEnclaveHostsMapToControlPlane() {
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://api-us-east.quillrouter.com/v1"),
            TrustedRouterDefaults.defaultControlBaseURL
        )
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://api-eu.quillrouter.com/v1"),
            TrustedRouterDefaults.defaultControlBaseURL
        )
    }

    func testCustomGatewaysPassThroughUnchanged() {
        // A custom or development gateway serves both the API and the interactive pages itself.
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "http://localhost:8080/v1"),
            "http://localhost:8080/v1"
        )
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://gateway.example.com/v1"),
            "https://gateway.example.com/v1"
        )
        // The control plane itself is already the right place.
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://trustedrouter.com/v1"),
            "https://trustedrouter.com/v1"
        )
    }

    func testLookalikeHostsAreNotTreatedAsTheEnclave() {
        // Suffix matching must not capture unrelated domains.
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://api.trustedrouter.com.evil.example/v1"),
            "https://api.trustedrouter.com.evil.example/v1"
        )
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "https://api-x.notquillrouter.com/v1"),
            "https://api-x.notquillrouter.com/v1"
        )
    }

    func testUnparseableValuesFallBackToControlPlane() {
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "   "),
            TrustedRouterDefaults.defaultControlBaseURL
        )
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "not a url"),
            TrustedRouterDefaults.defaultControlBaseURL
        )
    }

    func testWhitespaceIsTrimmedBeforeMapping() {
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "  https://api.trustedrouter.com/v1  "),
            TrustedRouterDefaults.defaultControlBaseURL
        )
        XCTAssertEqual(
            TrustedRouterDefaults.controlBaseURL(forAPIBaseURL: "  https://gateway.example.com/v1  "),
            "https://gateway.example.com/v1"
        )
    }
}
