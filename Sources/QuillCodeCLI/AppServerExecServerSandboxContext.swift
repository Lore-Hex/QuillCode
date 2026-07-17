import Foundation

struct AppServerExecServerSandboxContext: Sendable, Equatable {
    private enum NetworkPolicy: String, Sendable {
        case restricted
        case enabled
    }

    private enum Access: String, Sendable {
        case read
        case write
    }

    private enum Path: Sendable, Equatable {
        case absolute(String)
        case special(kind: String, subpath: String? = nil)

        var rpcValue: CLIJSONValue {
            switch self {
            case .absolute(let uri):
                .object([
                    "type": .string("path"),
                    "path": .string(uri)
                ])
            case .special(let kind, let subpath):
                .object([
                    "type": .string("special"),
                    "value": .object([
                        "kind": .string(kind),
                        "subpath": subpath.map(CLIJSONValue.string) ?? .null
                    ].filter { $0.value != .null })
                ])
            }
        }
    }

    private struct Entry: Sendable, Equatable {
        var path: Path
        var access: Access

        var rpcValue: CLIJSONValue {
            .object([
                "path": path.rpcValue,
                "access": .string(access.rawValue)
            ])
        }
    }

    private enum Permissions: Sendable, Equatable {
        case managed(entries: [Entry], network: NetworkPolicy)
        case disabled

        var rpcValue: CLIJSONValue {
            switch self {
            case .managed(let entries, let network):
                .object([
                    "type": .string("managed"),
                    "file_system": .object([
                        "type": .string("restricted"),
                        "entries": .array(entries.map(\.rpcValue))
                    ]),
                    "network": .string(network.rawValue)
                ])
            case .disabled:
                .object(["type": .string("disabled")])
            }
        }
    }

    private var permissions: Permissions
    var cwdURI: String
    var workspaceRootURIs: [String]

    init(
        policy: AppServerSandboxPolicy,
        workspace: AppServerRemoteWorkspacePath
    ) throws {
        let network: NetworkPolicy = policy.networkAccess ? .enabled : .restricted
        switch policy.mode {
        case .readOnly:
            permissions = .managed(
                entries: [.init(path: .special(kind: "root"), access: .read)],
                network: network
            )
        case .workspaceWrite:
            permissions = .managed(
                entries: try Self.workspaceWriteEntries(
                    policy: policy,
                    workspace: workspace
                ),
                network: network
            )
        case .dangerFullAccess:
            permissions = .disabled
        }
        cwdURI = workspace.root.uri
        workspaceRootURIs = [workspace.root.uri]
    }

    var rpcValue: CLIJSONValue {
        .object([
            "permissions": permissions.rpcValue,
            "cwd": .string(cwdURI),
            "workspaceRoots": .array(workspaceRootURIs.map(CLIJSONValue.string)),
            "windowsSandboxLevel": .string("disabled"),
            "windowsSandboxPrivateDesktop": .bool(false),
            "useLegacyLandlock": .bool(false)
        ])
    }

    private static func workspaceWriteEntries(
        policy: AppServerSandboxPolicy,
        workspace: AppServerRemoteWorkspacePath
    ) throws -> [Entry] {
        var entries: [Entry] = [
            .init(path: .special(kind: "root"), access: .read),
            .init(path: .special(kind: "project_roots"), access: .write)
        ]
        if !policy.excludeSlashTemporaryDirectory {
            entries.append(.init(path: .special(kind: "slash_tmp"), access: .write))
        }
        if !policy.excludeTemporaryDirectoryEnvironmentVariable {
            entries.append(.init(path: .special(kind: "tmpdir"), access: .write))
        }
        for root in policy.writableRoots {
            entries.append(.init(
                path: .absolute(try workspace.sandboxPathURI(for: root)),
                access: .write
            ))
        }
        for metadataDirectory in [".git", ".agents", ".codex"] {
            entries.append(.init(
                path: .special(kind: "project_roots", subpath: metadataDirectory),
                access: .read
            ))
        }
        return deduplicated(entries)
    }

    private static func deduplicated(_ entries: [Entry]) -> [Entry] {
        var result: [Entry] = []
        for entry in entries where !result.contains(entry) {
            result.append(entry)
        }
        return result
    }
}
