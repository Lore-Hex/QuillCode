import XCTest

final class ParityAppServerClientConfigurationGateTests: QuillCodeParityTestCase {
    func testClientConfigurationDiscoveryStaysWiredThroughPolicyTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let discovery = try text(
            root,
            "Sources/QuillCodeCLI/AppServerClientConfigurationDiscovery.swift"
        )
        let requirements = try text(
            root,
            "Sources/QuillCodePersistence/ManagedRequirements.swift"
        )
        let requirementsDecoder = try text(
            root,
            "Sources/QuillCodePersistence/ManagedRequirementsDecoder.swift"
        )
        let networkDecoder = try text(
            root,
            "Sources/QuillCodePersistence/ManagedRequirementsNetworkDecoder.swift"
        )
        let threadSettings = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionThreadSettings.swift"
        )
        let commandExec = try text(
            root,
            "Sources/QuillCodeCLI/AppServerCommandExecManagement.swift"
        )
        let persistenceTests = try text(
            root,
            "Tests/QuillCodePersistenceTests/ManagedRequirementsTests.swift"
        )
        let protocolTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerClientConfigurationDiscoveryTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, containsAll: [
            "case \"configRequirements/read\"",
            "case \"permissionProfile/list\"",
            "case \"collaborationMode/list\""
        ])
        Self.assertSource(discovery, containsAll: [
            "func listPermissionProfiles",
            "func listCollaborationModes",
            "func readConfigRequirements",
            "func validateManagedPermissionProfile",
            "func validateManagedApprovalPolicy"
        ])
        Self.assertSource(requirements, containsAll: [
            "public enum ManagedRequirementsLoader",
            "merge(overridingWith:"
        ])
        Self.assertSource(requirementsDecoder, containsAll: [
            "allowed_permission_profiles",
            "allowed_sandbox_modes"
        ])
        Self.assertSource(networkDecoder, contains: "experimental_network")
        Self.assertSource(threadSettings, containsAll: [
            "permissionsValue",
            "validateManagedPermissionProfile",
            "validateManagedApprovalPolicy"
        ])
        Self.assertSource(commandExec, containsAll: [
            "validateManagedSandboxMode",
            "validateManagedPermissionProfile",
            "effectiveDefaultPermissions"
        ])
        Self.assertSource(persistenceTests, containsAll: [
            "testLoaderMergesLayersAndDecodesManagedRequirements",
            "testLoaderRejectsUnsafeOrAmbiguousPermissionDefaults"
        ])
        Self.assertSource(protocolTests, containsAll: [
            "testDefaultDiscoveryMatchesCodexWireContractAndPagination",
            "testManagedRequirementsProjectionFiltersExperimentalFields",
            "testManagedPermissionRequirementsAreEnforcedAcrossThreadsAndCommands",
            "testManagedDefaultPermissionProfileAppliesToNewThreads"
        ])
        Self.assertSource(smoke, containsAll: [
            "permissionProfile/list",
            "collaborationMode/list",
            "configRequirements/read"
        ])
        Self.assertSource(parity, contains: "App-server client configuration discovery")
        Self.assertSource(research, contains: "client configuration discovery")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
