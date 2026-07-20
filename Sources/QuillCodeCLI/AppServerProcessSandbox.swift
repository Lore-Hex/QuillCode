import Foundation
import QuillCodeTools

struct AppServerProcessLaunch: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
}

enum AppServerProcessSandbox {
    static func launch(for request: AppServerProcessSpawnRequest) throws -> AppServerProcessLaunch {
        let target = try AppServerProcessSupport.resolveExecutable(
            request.command[0],
            cwd: request.cwd,
            environment: request.environment
        )
        let targetArguments = Array(request.command.dropFirst())
        let sharedPolicy = request.sandboxPolicy.map { policy in
            let mode: ShellProcessSandboxMode = switch policy.mode {
            case .readOnly: .readOnly
            case .workspaceWrite: .workspaceWrite
            case .dangerFullAccess: .unrestricted
            }
            return ShellProcessSandboxPolicy(
                mode: mode,
                networkAccess: policy.networkAccess,
                writableRoots: policy.writableRoots.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                },
                includesSlashTemporaryDirectory: policy.mode == .readOnly
                    || !policy.excludeSlashTemporaryDirectory,
                includesEnvironmentTemporaryDirectory:
                    policy.mode == .readOnly
                    || !policy.excludeTemporaryDirectoryEnvironmentVariable
            )
        }
        do {
            let launch = try ShellProcessSandbox.launch(
                executable: target,
                arguments: targetArguments,
                cwd: request.cwd,
                environment: request.environment,
                policy: sharedPolicy
            )
            return AppServerProcessLaunch(
                executable: launch.executable,
                arguments: launch.arguments
            )
        } catch {
            throw AppServerRPCError.internalError(
                "failed to configure command sandbox: \(error.localizedDescription)"
            )
        }
    }

    static func filesystemAliases(for path: String) -> [String] {
        ShellProcessSandbox.filesystemAliases(for: path)
    }
}
