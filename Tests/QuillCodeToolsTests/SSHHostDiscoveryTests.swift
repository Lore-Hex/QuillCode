import Foundation
import QuillCodeCore
@testable import QuillCodeTools
import XCTest

final class SSHHostDiscoveryTests: XCTestCase {
    func testParserFindsOnlyConcreteDeduplicatedAliases() {
        let config = #"""
        # Global settings
        Host production PRODuction staging
          HostName prod.example.com
        Host *.internal !blocked wildcard?
        Host=-option
        Host "quoted-host" # comment
        Match host production
          User deploy
        """#

        XCTAssertEqual(
            SSHConfigParser.concreteHostAliases(in: config, limit: 20),
            ["production", "staging", "quoted-host"]
        )
    }

    func testParserHandlesQuotedAndEqualsIncludeDirectives() {
        let config = #"""
        Include="config.d/work hosts.conf" config.d/*.conf
        Include = config.spaced
        Include =config.prefixed
        include config.extra
        """#

        XCTAssertEqual(
            SSHConfigParser.includePatterns(in: config, limit: 10),
            [
                "config.d/work hosts.conf",
                "config.d/*.conf",
                "config.spaced",
                "config.prefixed",
                "config.extra"
            ]
        )
    }

    func testParserNormalizesWhitespaceAroundHostAssignment() {
        let config = #"""
        Host = production
        Host =staging
        """#

        XCTAssertEqual(
            SSHConfigParser.concreteHostAliases(in: config, limit: 10),
            ["production", "staging"]
        )
    }

    func testDiscoveryReadsBoundedIncludesAndUsesOpenSSHEffectiveConfiguration() throws {
        let home = try makeTempDirectory()
        let sshDirectory = home.appendingPathComponent(".ssh", isDirectory: true)
        let includeDirectory = sshDirectory.appendingPathComponent("config.d", isDirectory: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)
        let includedConfig = includeDirectory.appendingPathComponent("staging.conf")
        try #"""
        Host staging
          HostName 192.0.2.20
          User qa
        """#.write(to: includedConfig, atomically: true, encoding: .utf8)

        let rootConfig = sshDirectory.appendingPathComponent("config")
        try #"""
        Include \#(includeDirectory.path)/*.conf
        Host production
          HostName prod.example.com
          User deploy
          Port 2222
        Host *.example.com
          User ignored
        """#.write(to: rootConfig, atomically: true, encoding: .utf8)

        let result = SSHHostDiscovery(
            configURL: rootConfig,
            homeDirectory: home
        ).discoverSynchronously()

        XCTAssertEqual(result.configPath, rootConfig.path)
        XCTAssertEqual(result.hosts.map(\.alias), ["production", "staging"])
        XCTAssertEqual(result.hosts[0].resolvedAddress, "deploy@prod.example.com:2222")
        XCTAssertEqual(result.hosts[1].resolvedAddress, "qa@192.0.2.20")
        XCTAssertTrue(result.warnings.isEmpty, result.warnings.joined(separator: "\n"))
    }

    func testDiscoveryStopsAtAliasLimitAndReportsIt() throws {
        let home = try makeTempDirectory()
        let sshDirectory = home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let rootConfig = sshDirectory.appendingPathComponent("config")
        try "Host alpha beta gamma\n".write(to: rootConfig, atomically: true, encoding: .utf8)

        let result = SSHHostDiscovery(
            configURL: rootConfig,
            homeDirectory: home,
            limits: SSHHostDiscoveryLimits(maximumAliases: 2)
        ).discoverSynchronously()

        XCTAssertEqual(result.hosts.map(\.alias), ["alpha", "beta"])
        XCTAssertTrue(result.warnings.contains { $0.contains("2 aliases") })
    }

    func testDiscoveryIgnoresIncludeCycles() throws {
        let home = try makeTempDirectory()
        let sshDirectory = home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let rootConfig = sshDirectory.appendingPathComponent("config")
        let secondConfig = sshDirectory.appendingPathComponent("second.conf")
        try "Include \(secondConfig.path)\nHost alpha\n".write(
            to: rootConfig,
            atomically: true,
            encoding: .utf8
        )
        try "Include \(rootConfig.path)\nHost beta\n".write(
            to: secondConfig,
            atomically: true,
            encoding: .utf8
        )

        let result = SSHHostDiscovery(configURL: rootConfig, homeDirectory: home).discoverSynchronously()

        XCTAssertEqual(Set(result.hosts.map(\.alias)), ["alpha", "beta"])
    }

    func testDiscoveryExpandsBracketIncludesWithoutImplicitHiddenMatches() throws {
        let home = try makeTempDirectory()
        let sshDirectory = home.appendingPathComponent(".ssh", isDirectory: true)
        let includeDirectory = sshDirectory.appendingPathComponent("config.d", isDirectory: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)
        try "Host alpha\n".write(
            to: includeDirectory.appendingPathComponent("host-a.conf"),
            atomically: true,
            encoding: .utf8
        )
        try "Host beta\n".write(
            to: includeDirectory.appendingPathComponent("host-b.conf"),
            atomically: true,
            encoding: .utf8
        )
        try "Host hidden\n".write(
            to: includeDirectory.appendingPathComponent(".host-a.conf"),
            atomically: true,
            encoding: .utf8
        )
        let rootConfig = sshDirectory.appendingPathComponent("config")
        try "Include \(includeDirectory.path)/host-[ab].conf \(includeDirectory.path)/[.]host-a.conf\n".write(
            to: rootConfig,
            atomically: true,
            encoding: .utf8
        )

        let result = SSHHostDiscovery(configURL: rootConfig, homeDirectory: home).discoverSynchronously()

        XCTAssertEqual(result.hosts.map(\.alias), ["alpha", "beta", "hidden"])
    }

    func testCancelledDiscoveryStopsBeforeReadingHosts() async throws {
        let home = try makeTempDirectory()
        let sshDirectory = home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let rootConfig = sshDirectory.appendingPathComponent("config")
        try "Host should-not-load\n".write(to: rootConfig, atomically: true, encoding: .utf8)
        let discovery = SSHHostDiscovery(configURL: rootConfig, homeDirectory: home)

        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return discovery.discoverSynchronously()
        }.value

        XCTAssertTrue(result.hosts.isEmpty)
    }

    func testMissingIncludesDoNotConsumeReadableFileLimit() throws {
        let home = try makeTempDirectory()
        let sshDirectory = home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let includedConfig = sshDirectory.appendingPathComponent("included.conf")
        try "Host reachable\n".write(to: includedConfig, atomically: true, encoding: .utf8)
        let rootConfig = sshDirectory.appendingPathComponent("config")
        try "Include missing-one missing-two \(includedConfig.path)\n".write(
            to: rootConfig,
            atomically: true,
            encoding: .utf8
        )

        let result = SSHHostDiscovery(
            configURL: rootConfig,
            homeDirectory: home,
            limits: SSHHostDiscoveryLimits(maximumFiles: 2)
        ).discoverSynchronously()

        XCTAssertEqual(result.hosts.map(\.alias), ["reachable"])
        XCTAssertTrue(result.warnings.isEmpty, result.warnings.joined(separator: "\n"))
    }

    func testOversizedConfigIsRejectedBeforeParsing() throws {
        let home = try makeTempDirectory()
        let sshDirectory = home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let rootConfig = sshDirectory.appendingPathComponent("config")
        try "Host should-not-load\n".write(to: rootConfig, atomically: true, encoding: .utf8)

        let result = SSHHostDiscovery(
            configURL: rootConfig,
            homeDirectory: home,
            limits: SSHHostDiscoveryLimits(maximumTotalBytes: 8)
        ).discoverSynchronously()

        XCTAssertTrue(result.hosts.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("8 bytes") })
    }
}
