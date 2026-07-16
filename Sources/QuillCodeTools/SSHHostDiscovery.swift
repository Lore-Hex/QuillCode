import Foundation
import QuillCodeCore

public struct SSHHostDiscoveryLimits: Sendable, Hashable {
    public var maximumFiles: Int
    public var maximumTotalBytes: Int
    public var maximumDepth: Int
    public var maximumAliases: Int
    public var maximumIncludePatternsPerFile: Int

    public init(
        maximumFiles: Int = 32,
        maximumTotalBytes: Int = 1_048_576,
        maximumDepth: Int = 8,
        maximumAliases: Int = 128,
        maximumIncludePatternsPerFile: Int = 64
    ) {
        self.maximumFiles = max(1, maximumFiles)
        self.maximumTotalBytes = max(1, maximumTotalBytes)
        self.maximumDepth = max(0, maximumDepth)
        self.maximumAliases = max(1, maximumAliases)
        self.maximumIncludePatternsPerFile = max(1, maximumIncludePatternsPerFile)
    }

    public static let `default` = SSHHostDiscoveryLimits()
}

public struct SSHHostDiscoveryResult: Sendable, Hashable {
    public var hosts: [SSHHostConfiguration]
    public var configPath: String
    public var warnings: [String]

    public init(hosts: [SSHHostConfiguration], configPath: String, warnings: [String] = []) {
        self.hosts = hosts
        self.configPath = configPath
        self.warnings = warnings
    }
}

public struct SSHHostDiscovery: Sendable {
    public var configURL: URL
    public var homeDirectory: URL
    public var sshExecutable: String
    public var limits: SSHHostDiscoveryLimits

    public init(
        configURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        sshExecutable: String = "ssh",
        limits: SSHHostDiscoveryLimits = .default
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.configURL = (configURL ?? homeDirectory.appendingPathComponent(".ssh/config")).standardizedFileURL
        self.sshExecutable = sshExecutable
        self.limits = limits
    }

    public func discover() async -> SSHHostDiscoveryResult {
        let task = Task.detached(priority: .utility) {
            discoverSynchronously()
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func discoverSynchronously() -> SSHHostDiscoveryResult {
        var scanner = SSHConfigSourceScanner(
            rootConfigURL: configURL,
            homeDirectory: homeDirectory,
            limits: limits
        )
        let scan = scanner.scan()
        let resolver = SSHConfigHostResolver(
            executable: sshExecutable,
            configURL: configURL
        )
        var warnings = scan.warnings
        var hosts: [SSHHostConfiguration] = []
        for alias in scan.aliases {
            guard !Task.isCancelled else { break }
            if let resolved = resolver.resolve(alias: alias) {
                hosts.append(resolved)
            } else {
                warnings.append("Could not resolve SSH host alias '\(alias)'.")
                hosts.append(SSHHostConfiguration(alias: alias))
            }
        }
        return SSHHostDiscoveryResult(
            hosts: hosts.sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending },
            configPath: configURL.path,
            warnings: Array(warnings.prefix(8))
        )
    }
}
