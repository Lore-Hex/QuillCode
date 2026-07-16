import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class QuillCodeSSHConnectionDraftTests: XCTestCase {
    func testConfiguredHostRequestPreservesAliasAndUsesEnteredPath() throws {
        var draft = QuillCodeSSHConnectionDraft()
        draft.apply(SSHHostDiscoveryResult(
            hosts: [
                SSHHostConfiguration(
                    alias: "production",
                    hostName: "prod.example.com",
                    user: "deploy",
                    port: 2222
                )
            ],
            configPath: "/home/quill/.ssh/config"
        ))
        draft.remotePath = " ~/service "
        draft.projectName = " Production API "

        let request = try XCTUnwrap(draft.request)

        XCTAssertEqual(request.connection.host, "production")
        XCTAssertNil(request.connection.user)
        XCTAssertNil(request.connection.port)
        XCTAssertEqual(request.connection.path, "~/service")
        XCTAssertEqual(request.name, "Production API")
        XCTAssertTrue(draft.canConnect)
    }

    func testHostSearchMatchesAliasAndResolvedAddress() {
        var draft = QuillCodeSSHConnectionDraft()
        draft.apply(SSHHostDiscoveryResult(
            hosts: [
                SSHHostConfiguration(alias: "production", hostName: "prod.example.com", user: "deploy"),
                SSHHostConfiguration(alias: "staging", hostName: "192.0.2.20", user: "qa")
            ],
            configPath: "/tmp/config"
        ))

        draft.query = "192.0.2"
        XCTAssertEqual(draft.filteredHosts.map(\.alias), ["staging"])

        draft.query = "PROD"
        XCTAssertEqual(draft.filteredHosts.map(\.alias), ["production"])
    }

    func testManualAddressBuildsTypedConnectionFromURLWithoutEmbeddedPath() throws {
        var draft = QuillCodeSSHConnectionDraft(mode: .manual)
        draft.manualAddress = "ssh://quill@feather.example:2202"
        draft.remotePath = "/srv/quillcode"

        let request = try XCTUnwrap(draft.request)

        XCTAssertEqual(request.connection.kind, .ssh)
        XCTAssertEqual(request.connection.host, "feather.example")
        XCTAssertEqual(request.connection.user, "quill")
        XCTAssertEqual(request.connection.port, 2202)
        XCTAssertEqual(request.connection.path, "/srv/quillcode")
    }

    func testManualAddressRejectsURLWithEmbeddedPath() {
        var draft = QuillCodeSSHConnectionDraft(mode: .manual)
        draft.manualAddress = "ssh://quill@feather.example:2202/ignored"
        draft.remotePath = "/srv/quillcode"

        XCTAssertNil(draft.request)
        XCTAssertFalse(draft.canConnect)
    }

    func testManualCompactAddressSupportsUserAndPort() throws {
        var draft = QuillCodeSSHConnectionDraft(mode: .manual)
        draft.manualAddress = "deploy@build.example:2202"
        draft.remotePath = "~/service"

        let request = try XCTUnwrap(draft.request)

        XCTAssertEqual(request.connection.host, "build.example")
        XCTAssertEqual(request.connection.user, "deploy")
        XCTAssertEqual(request.connection.port, 2202)
        XCTAssertEqual(request.connection.path, "~/service")
    }

    func testInvalidManualInputsNeverEnableConnect() {
        var draft = QuillCodeSSHConnectionDraft(mode: .manual)
        draft.manualAddress = "quill@feather"
        draft.remotePath = "relative/path"
        XCTAssertNil(draft.request)
        XCTAssertFalse(draft.canConnect)

        draft.remotePath = "~/repo"
        XCTAssertNotNil(draft.request)
        draft.isConnecting = true
        XCTAssertFalse(draft.canConnect)
    }

    func testEmptyDiscoverySwitchesToManualEntry() {
        var draft = QuillCodeSSHConnectionDraft()

        draft.apply(SSHHostDiscoveryResult(hosts: [], configPath: "/tmp/missing"))

        XCTAssertEqual(draft.mode, .manual)
        XCTAssertTrue(draft.hostLoad.hasLoaded)
        XCTAssertFalse(draft.hostLoad.isLoading)
        XCTAssertNil(draft.selectedHostID)
    }

    func testSSHProjectRequestRejectsNonSSHConnection() {
        XCTAssertNil(WorkspaceSSHProjectRequest(
            connection: .local(path: "/tmp/project"),
            name: "Local"
        ))
    }
}
