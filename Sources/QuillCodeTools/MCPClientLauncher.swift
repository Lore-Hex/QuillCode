import Foundation

public protocol MCPProcessControlling: AnyObject, Sendable {
    var isRunning: Bool { get }
    func terminate()
    func clearReadabilityHandlers()
    func startDrainingStandardError()
}

public struct MCPClientLaunchRequest: Sendable {
    public enum Transport: Sendable {
        case stdio
        case remote(
            url: URL,
            headers: [String: String],
            mode: MCPHTTPProber.Mode,
            authorization: any MCPRemoteAuthorizing
        )
    }

    public var transport: Transport
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL

    public init(
        transport: Transport,
        command: String = "",
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL
    ) {
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public struct MCPLaunchedClient: Sendable {
    public var process: any MCPProcessControlling
    public var session: any MCPClientSession

    public init(process: any MCPProcessControlling, session: any MCPClientSession) {
        self.process = process
        self.session = session
    }
}

public protocol MCPClientLaunching: Sendable {
    func launch(
        request: MCPClientLaunchRequest,
        onTermination: @escaping @Sendable (_ terminationStatus: Int32) -> Void
    ) throws -> MCPLaunchedClient
}

public struct MCPProcessLaunchConfiguration: Sendable, Hashable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]

    public static func resolve(
        command: String,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: URL
    ) -> MCPProcessLaunchConfiguration {
        if command.contains("/") {
            let commandURL = command.hasPrefix("/")
                ? URL(fileURLWithPath: command)
                : workingDirectory.appendingPathComponent(command)
            return MCPProcessLaunchConfiguration(
                executableURL: commandURL,
                arguments: arguments,
                environment: environment
            )
        }
        return MCPProcessLaunchConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [command] + arguments,
            environment: environment
        )
    }
}

public struct DefaultMCPClientLauncher: MCPClientLaunching {
    private let httpClient: any MCPHTTPClient

    public init(httpClient: any MCPHTTPClient = URLSessionMCPHTTPClient()) {
        self.httpClient = httpClient
    }

    public func launch(
        request: MCPClientLaunchRequest,
        onTermination: @escaping @Sendable (_ terminationStatus: Int32) -> Void = { _ in }
    ) throws -> MCPLaunchedClient {
        switch request.transport {
        case .stdio:
            return try launchStdio(request: request, onTermination: onTermination)
        case let .remote(url, headers, mode, authorization):
            let session = MCPHTTPProber(
                endpoint: url,
                httpClient: httpClient,
                authorization: authorization,
                extraHeaders: headers,
                mode: mode
            )
            return MCPLaunchedClient(
                process: MCPRemoteConnectionController(),
                session: session
            )
        }
    }

    private func launchStdio(
        request: MCPClientLaunchRequest,
        onTermination: @escaping @Sendable (_ terminationStatus: Int32) -> Void
    ) throws -> MCPLaunchedClient {
        let process = Process()
        process.currentDirectoryURL = request.workingDirectory
        let launch = MCPProcessLaunchConfiguration.resolve(
            command: request.command,
            arguments: request.arguments,
            environment: request.environment,
            workingDirectory: request.workingDirectory
        )
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        if !launch.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(
                launch.environment,
                uniquingKeysWith: { _, configuredValue in configuredValue }
            )
        }

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let controller = MCPFoundationProcessController(
            process: process,
            standardInput: standardInput,
            standardOutput: standardOutput,
            standardError: standardError
        )
        process.terminationHandler = { process in
            controller.clearReadabilityHandlers()
            onTermination(process.terminationStatus)
        }
        try process.run()

        return MCPLaunchedClient(
            process: controller,
            session: MCPStdioProber(
                standardInput: standardInput.fileHandleForWriting,
                standardOutput: standardOutput.fileHandleForReading
            )
        )
    }
}

private final class MCPFoundationProcessController: MCPProcessControlling, @unchecked Sendable {
    private let process: Process
    private let standardInput: Pipe
    private let standardOutput: Pipe
    private let standardError: Pipe

    init(process: Process, standardInput: Pipe, standardOutput: Pipe, standardError: Pipe) {
        self.process = process
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        process.terminate()
    }

    func clearReadabilityHandlers() {
        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
    }

    func startDrainingStandardError() {
        standardError.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
    }
}

private final class MCPRemoteConnectionController: MCPProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var running = true

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func terminate() {
        lock.lock()
        running = false
        lock.unlock()
    }

    func clearReadabilityHandlers() {}
    func startDrainingStandardError() {}
}
