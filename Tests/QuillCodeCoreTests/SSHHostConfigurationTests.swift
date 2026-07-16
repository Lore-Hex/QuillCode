import QuillCodeCore
import XCTest

final class SSHHostConfigurationTests: XCTestCase {
    func testResolvedAddressOmitsDefaultPortAndKeepsAliasForExecution() {
        let host = SSHHostConfiguration(
            alias: "production",
            hostName: "prod.example.com",
            user: "deploy",
            port: 22
        )

        XCTAssertEqual(host.id, "production")
        XCTAssertEqual(host.resolvedAddress, "deploy@prod.example.com")
        XCTAssertEqual(
            host.projectConnection(path: "~/app"),
            .ssh(path: "~/app", host: "production")
        )
    }

    func testResolvedAddressShowsNonDefaultPort() {
        let host = SSHHostConfiguration(
            alias: "staging",
            hostName: "192.0.2.10",
            user: "quill",
            port: 2222
        )

        XCTAssertEqual(host.resolvedAddress, "quill@192.0.2.10:2222")
    }
}
