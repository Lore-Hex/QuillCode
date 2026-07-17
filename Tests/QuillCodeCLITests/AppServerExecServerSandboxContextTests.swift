@testable import QuillCodeCLI
import XCTest

final class AppServerExecServerSandboxContextTests: XCTestCase {
    func testReadOnlyProfileMatchesExecServerProtocol() throws {
        let context = try makeContext(.init(
            mode: .readOnly,
            networkAccess: true
        ))

        XCTAssertEqual(context.rpcValue, contextValue(
            permissions: .object([
                "type": .string("managed"),
                "file_system": restrictedFileSystem([
                    entry(special: "root", access: "read")
                ]),
                "network": .string("enabled")
            ])
        ))
    }

    func testWorkspaceWriteProfileProjectsRootsAndExclusionsExactly() throws {
        let context = try makeContext(.init(
            mode: .workspaceWrite,
            writableRoots: ["/shared", "cache", "/shared"],
            excludeTemporaryDirectoryEnvironmentVariable: false,
            excludeSlashTemporaryDirectory: true
        ))

        XCTAssertEqual(context.rpcValue, contextValue(
            permissions: .object([
                "type": .string("managed"),
                "file_system": restrictedFileSystem([
                    entry(special: "root", access: "read"),
                    entry(special: "project_roots", access: "write"),
                    entry(special: "tmpdir", access: "write"),
                    entry(pathURI: "file:///shared", access: "write"),
                    entry(pathURI: "file:///workspace/cache", access: "write"),
                    entry(special: "project_roots", subpath: ".git", access: "read"),
                    entry(special: "project_roots", subpath: ".agents", access: "read"),
                    entry(special: "project_roots", subpath: ".codex", access: "read")
                ]),
                "network": .string("restricted")
            ])
        ))
    }

    func testDangerFullAccessUsesDisabledProfileWithoutClaimingManagedEnforcement() throws {
        let context = try makeContext(.init(
            mode: .dangerFullAccess,
            networkAccess: true,
            writableRoots: ["/ignored"]
        ))

        XCTAssertEqual(context.rpcValue, contextValue(
            permissions: .object(["type": .string("disabled")])
        ))
    }

    func testWritableRootForAnotherTargetDriveFailsClosed() throws {
        let workspace = try AppServerRemoteWorkspacePath(
            cwd: #"C:\work\project"#,
            fallbackCWDURI: nil
        )

        XCTAssertThrowsError(try AppServerExecServerSandboxContext(
            policy: .init(mode: .workspaceWrite, writableRoots: [#"D:\shared"#]),
            workspace: workspace
        )) { error in
            XCTAssertEqual(
                error as? AppServerRemotePathError,
                .outsideWorkspace(#"D:\shared"#)
            )
        }
    }

    private func makeContext(
        _ policy: AppServerSandboxPolicy
    ) throws -> AppServerExecServerSandboxContext {
        try AppServerExecServerSandboxContext(
            policy: policy,
            workspace: .init(cwd: "/workspace", fallbackCWDURI: nil)
        )
    }

    private func contextValue(permissions: CLIJSONValue) -> CLIJSONValue {
        .object([
            "permissions": permissions,
            "cwd": .string("file:///workspace"),
            "workspaceRoots": .array([.string("file:///workspace")]),
            "windowsSandboxLevel": .string("disabled"),
            "windowsSandboxPrivateDesktop": .bool(false),
            "useLegacyLandlock": .bool(false)
        ])
    }

    private func restrictedFileSystem(
        _ entries: [CLIJSONValue]
    ) -> CLIJSONValue {
        .object([
            "type": .string("restricted"),
            "entries": .array(entries)
        ])
    }

    private func entry(
        special kind: String,
        subpath: String? = nil,
        access: String
    ) -> CLIJSONValue {
        var value: [String: CLIJSONValue] = ["kind": .string(kind)]
        if let subpath { value["subpath"] = .string(subpath) }
        return .object([
            "path": .object([
                "type": .string("special"),
                "value": .object(value)
            ]),
            "access": .string(access)
        ])
    }

    private func entry(pathURI: String, access: String) -> CLIJSONValue {
        .object([
            "path": .object([
                "type": .string("path"),
                "path": .string(pathURI)
            ]),
            "access": .string(access)
        ])
    }
}
