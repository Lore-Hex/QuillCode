import XCTest
@testable import QuillCodePersistence

final class ManagedRequirementsTests: PersistenceTestCase {
    func testReviewerAliasesAreEquivalentWithoutChangingTheRequestedWireValue() {
        let legacy = ManagedRequirements(allowedApprovalsReviewers: ["guardian_subagent"])
        XCTAssertTrue(legacy.allowsApprovalsReviewer("auto_review"))

        let current = ManagedRequirements(allowedApprovalsReviewers: ["auto_review"])
        XCTAssertTrue(current.allowsApprovalsReviewer("guardian_subagent"))
        XCTAssertFalse(current.allowsApprovalsReviewer("user"))
    }

    func testLoaderMergesLayersAndDecodesManagedRequirements() throws {
        let directory = try makeTempDirectory()
        let low = directory.appendingPathComponent("low.toml")
        let high = directory.appendingPathComponent("high.toml")
        try """
        allowed_approval_policies = ["on-request", { granular = { sandbox_approval = true, rules = true, mcp_elicitations = false } }]
        allowed_approvals_reviewers = ["user", "guardian_subagent"]
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        allowed_web_search_modes = ["live"]
        allow_appshots = true

        [allowed_permission_profiles]
        ":read-only" = true
        ":workspace" = true
        ":danger-full-access" = false

        [features]
        memory = true

        [experimental_network]
        enabled = true
        allowed_domains = ["low.example"]
        allow_unix_sockets = ["/tmp/quillcode.sock"]

        [hooks]
        managed_dir = "/managed/low"

        [[hooks.PreToolUse]]
        matcher = "shell"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "check-shell"
        timeout = 12
        async = true
        """.write(to: low, atomically: true, encoding: .utf8)
        try """
        default_permissions = ":workspace"
        allow_appshots = false

        [features]
        memory = false
        browser = true

        [experimental_network]
        allowed_domains = ["high.example"]

        [hooks]
        managed_dir = "/managed/high"
        """.write(to: high, atomically: true, encoding: .utf8)

        let requirements = try XCTUnwrap(ManagedRequirementsLoader.load(from:
            HookConfigurationPaths(managedRequirementFiles: [low, high])
        ))

        XCTAssertEqual(requirements.defaultPermissions, ":workspace")
        XCTAssertEqual(requirements.effectiveDefaultPermissions, ":workspace")
        XCTAssertEqual(requirements.allowedSandboxModes, ["read-only", "workspace-write"])
        XCTAssertEqual(requirements.allowedWebSearchModes, ["live", "disabled"])
        XCTAssertEqual(requirements.allowAppshots, false)
        XCTAssertEqual(requirements.featureRequirements, ["memory": false, "browser": true])
        XCTAssertTrue(requirements.allowsPermissionProfile(
            ":workspace",
            sandboxMode: "workspace-write"
        ))
        XCTAssertFalse(requirements.allowsPermissionProfile(
            ":danger-full-access",
            sandboxMode: "danger-full-access"
        ))
        XCTAssertTrue(requirements.allowsApprovalsReviewer("auto_review"))

        let network = try XCTUnwrap(requirements.network)
        XCTAssertEqual(network.enabled, true)
        XCTAssertEqual(network.allowedDomains, ["high.example"])
        XCTAssertEqual(network.allowedUnixSockets, ["/tmp/quillcode.sock"])

        let hooks = try XCTUnwrap(requirements.hooks)
        XCTAssertEqual(hooks.managedDirectory, "/managed/high")
        let group = try XCTUnwrap(hooks.events["PreToolUse"]?.first)
        XCTAssertEqual(group.matcher, "shell")
        XCTAssertEqual(
            group.hooks,
            [.command(ManagedCommandHook(
                command: "check-shell",
                timeoutSeconds: 12,
                isAsync: true
            ))]
        )
        XCTAssertEqual(hooks.events["Stop"], [])
    }

    func testLoaderReturnsNilForMissingOrEmptyDocuments() throws {
        let directory = try makeTempDirectory()
        let missing = directory.appendingPathComponent("missing.toml")
        let empty = directory.appendingPathComponent("empty.toml")
        try "".write(to: empty, atomically: true, encoding: .utf8)

        XCTAssertNil(try ManagedRequirementsLoader.load(from:
            HookConfigurationPaths(managedRequirementFiles: [missing])
        ))
        XCTAssertNil(try ManagedRequirementsLoader.load(from:
            HookConfigurationPaths(managedRequirementFiles: [missing, empty])
        ))
    }

    func testLoaderRejectsUnsafeOrAmbiguousPermissionDefaults() throws {
        XCTAssertThrowsError(try load("""
        allowed_sandbox_modes = ["workspace-write"]
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("must include `read-only`"))
        }

        XCTAssertThrowsError(try load("""
        [allowed_permission_profiles]
        ":read-only" = true
        ":workspace" = false
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("default_permissions"))
        }

        XCTAssertThrowsError(try load("""
        default_permissions = ":workspace"

        [allowed_permission_profiles]
        ":read-only" = true
        ":workspace" = false
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("must be allowed"))
        }

        XCTAssertThrowsError(try load("""
        allowed_sandbox_modes = ["read-only"]
        default_permissions = ":workspace"

        [allowed_permission_profiles]
        ":read-only" = true
        ":workspace" = true
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("allowed_sandbox_modes"))
        }
    }

    func testLoaderRejectsConflictingCanonicalAndLegacyNetworkPolicy() throws {
        XCTAssertThrowsError(try load("""
        [experimental_network]
        allowed_domains = ["legacy.example"]

        [experimental_network.domains]
        "canonical.example" = "allow"
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("cannot be combined"))
        }
    }

    private func load(_ contents: String) throws -> ManagedRequirements? {
        let file = try makeTempDirectory().appendingPathComponent("requirements.toml")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return try ManagedRequirementsLoader.load(from:
            HookConfigurationPaths(managedRequirementFiles: [file])
        )
    }
}
