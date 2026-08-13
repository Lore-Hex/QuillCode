import Foundation

enum ShellProcessSupervisor {
    static let executableName = "quill-code-process-supervisor"
    static let environmentKey = "QUILLCODE_PROCESS_SUPERVISOR_EXECUTABLE"
    private static let defaultExecutableURL = resolveExecutable()

    static func wrapping(
        _ launch: ShellProcessLaunch,
        supervisorURL: URL? = defaultExecutableURL
    ) -> ShellProcessLaunch {
        guard let supervisorURL else { return launch }
        return ShellProcessLaunch(
            executable: supervisorURL,
            arguments: [launch.executable.path] + launch.arguments,
            isSandboxed: launch.isSandboxed
        )
    }

    static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        currentExecutableURL: URL? = Bundle.main.executableURL
    ) -> URL? {
        if let override = environment[environmentKey], !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            return isExecutable(url) ? url : nil
        }

        var candidates: [URL] = []
        if bundle.bundleURL.pathExtension == "app" {
            candidates.append(
                bundle.bundleURL
                    .appendingPathComponent("Contents/Helpers", isDirectory: true)
                    .appendingPathComponent(executableName)
            )
        }
        if let currentExecutableURL {
            candidates.append(
                currentExecutableURL.deletingLastPathComponent().appendingPathComponent(executableName)
            )
        }
        return candidates.first(where: isExecutable)
    }

    private static func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
