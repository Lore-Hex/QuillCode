import CQuillPTY
import Foundation
import QuillCodeTools

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CLIDoctorRuntimeSnapshot: Sendable, Equatable {
    var executablePath: String
    var operatingSystem: String
    var inputIsTerminal: Bool
    var outputIsTerminal: Bool
    var errorIsTerminal: Bool

    static func live(inputIsTerminal: Bool) -> Self {
        Self(
            executablePath: URL(fileURLWithPath: CommandLine.arguments.first ?? "quill-code")
                .standardizedFileURL.path,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            inputIsTerminal: inputIsTerminal,
            outputIsTerminal: cquill_fd_isatty(Int32(FileHandle.standardOutput.fileDescriptor)) == 1,
            errorIsTerminal: cquill_fd_isatty(Int32(FileHandle.standardError.fileDescriptor)) == 1
        )
    }
}

struct CLIDoctorGitSnapshot: Sendable, Equatable {
    var version: String?
    var repositoryRoot: String?
    var branch: String?
    var error: String?
}

protocol CLIDoctorGitProbing: Sendable {
    func inspect(currentDirectory: URL) -> CLIDoctorGitSnapshot
}

struct LiveCLIDoctorGitProbe: CLIDoctorGitProbing {
    private let runner: GitProcessRunner

    init(runner: GitProcessRunner = GitProcessRunner()) {
        self.runner = runner
    }

    func inspect(currentDirectory: URL) -> CLIDoctorGitSnapshot {
        let version = runner.runGit(["--version"], cwd: currentDirectory, timeoutSeconds: 2)
        guard version.ok else {
            return CLIDoctorGitSnapshot(
                version: nil,
                repositoryRoot: nil,
                branch: nil,
                error: version.error ?? version.stderr
            )
        }

        let root = runner.runGit(
            ["rev-parse", "--show-toplevel"],
            cwd: currentDirectory,
            timeoutSeconds: 2
        )
        guard root.ok else {
            return CLIDoctorGitSnapshot(
                version: Self.cleaned(version.stdout),
                repositoryRoot: nil,
                branch: nil,
                error: nil
            )
        }
        let branch = runner.runGit(
            ["branch", "--show-current"],
            cwd: currentDirectory,
            timeoutSeconds: 2
        )
        return CLIDoctorGitSnapshot(
            version: Self.cleaned(version.stdout),
            repositoryRoot: Self.cleaned(root.stdout),
            branch: branch.ok ? Self.cleaned(branch.stdout) : nil,
            error: branch.ok ? nil : branch.error ?? branch.stderr
        )
    }

    private static func cleaned(_ value: String) -> String? {
        let value = CLIDoctorSanitizer.singleLine(value)
        return value.isEmpty ? nil : value
    }
}

struct CLIDoctorNetworkResult: Sendable, Equatable {
    var endpoint: String
    var statusCode: Int?
    var error: String?
}

protocol CLIDoctorNetworkProbing: Sendable {
    func probe(apiBaseURL: String, apiKey: String?) async -> CLIDoctorNetworkResult
}

struct LiveCLIDoctorNetworkProbe: CLIDoctorNetworkProbing {
    private static let requestTimeout: TimeInterval = 5

    private let session: URLSession

    init(session: URLSession = LiveCLIDoctorNetworkProbe.makeSession()) {
        self.session = session
    }

    func probe(apiBaseURL: String, apiKey: String?) async -> CLIDoctorNetworkResult {
        let reportedBaseURL = CLIDoctorSanitizer.safeURL(apiBaseURL)
        guard reportedBaseURL != "invalid URL",
              var endpoint = URL(string: apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return CLIDoctorNetworkResult(
                endpoint: reportedBaseURL,
                statusCode: nil,
                error: "The configured TrustedRouter base URL is invalid."
            )
        }
        if endpoint.lastPathComponent != "models" {
            endpoint.appendPathComponent("models")
        }

        var request = URLRequest(url: endpoint, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("QuillCode/\(QuillCodeCommandRunner.version) doctor", forHTTPHeaderField: "User-Agent")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return CLIDoctorNetworkResult(
                    endpoint: CLIDoctorSanitizer.safeURL(endpoint.absoluteString),
                    statusCode: nil,
                    error: "TrustedRouter returned a non-HTTP response."
                )
            }
            return CLIDoctorNetworkResult(
                endpoint: CLIDoctorSanitizer.safeURL(endpoint.absoluteString),
                statusCode: response.statusCode,
                error: nil
            )
        } catch {
            return CLIDoctorNetworkResult(
                endpoint: CLIDoctorSanitizer.safeURL(endpoint.absoluteString),
                statusCode: nil,
                error: Self.safeErrorDescription(error)
            )
        }
    }

    private static func safeErrorDescription(_ error: any Error) -> String {
        if let urlError = error as? URLError {
            return "URL request failed (code \(urlError.errorCode))."
        }
        return "Request failed with \(String(reflecting: type(of: error)))."
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: configuration)
    }
}

enum CLIDoctorExecutableLocator {
    static func matches(named name: String, environment: [String: String]) -> [String] {
        let path = environment["PATH"] ?? ""
        var seen = Set<String>()
        return path.split(separator: ":").compactMap { component in
            let directory = component.isEmpty ? "." : String(component)
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
                .standardizedFileURL.path
            guard FileManager.default.isExecutableFile(atPath: candidate),
                  seen.insert(candidate).inserted else {
                return nil
            }
            return candidate
        }
    }
}
