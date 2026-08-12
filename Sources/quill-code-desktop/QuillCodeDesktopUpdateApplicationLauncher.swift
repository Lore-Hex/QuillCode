import AppKit
import Dispatch
import Foundation

struct QuillCodeDesktopLaunchedApplication {
    let processIdentifier: Int32
    let isRunning: () -> Bool
}

enum QuillCodeDesktopUpdateApplicationLaunchMode: Equatable, Sendable {
    case launchServices
    case directProcess
}

enum QuillCodeDesktopUpdateApplicationLauncher {
    static func launch(
        _ applicationURL: URL,
        handshakeURL: URL?,
        mode: QuillCodeDesktopUpdateApplicationLaunchMode,
        timeout: TimeInterval
    ) throws -> QuillCodeDesktopLaunchedApplication {
        guard let bundle = Bundle(url: applicationURL),
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            throw QuillCodeDesktopUpdateError.installationFailed("the app executable is missing")
        }
        let arguments = handshakeURL.map {
            [QuillCodeDesktopUpdateLaunchHandshake.argument, $0.path]
        } ?? []
        switch mode {
        case .launchServices:
            return try launchWithWorkspace(
                applicationURL,
                arguments: arguments,
                timeout: timeout
            )
        case .directProcess:
            return try launchDirectly(executableURL, arguments: arguments)
        }
    }

    private static func launchWithWorkspace(
        _ applicationURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> QuillCodeDesktopLaunchedApplication {
        guard timeout.isFinite, timeout > 0 else {
            throw QuillCodeDesktopUpdateError.installationFailed(
                "the updated app launch timeout is invalid"
            )
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = arguments
        configuration.environment = ProcessInfo.processInfo.environment

        let completion = QuillCodeDesktopWorkspaceLaunchCompletion()
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { application, _ in
            completion.resolve(application)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success,
              let application = completion.application
        else {
            throw QuillCodeDesktopUpdateError.installationFailed(
                "the updated app could not be opened by Launch Services"
            )
        }
        return QuillCodeDesktopLaunchedApplication(
            processIdentifier: application.processIdentifier,
            isRunning: { !application.isTerminated }
        )
    }

    private static func launchDirectly(
        _ executableURL: URL,
        arguments: [String]
    ) throws -> QuillCodeDesktopLaunchedApplication {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            throw QuillCodeDesktopUpdateError.installationFailed(
                "the updated app could not be launched"
            )
        }
        return QuillCodeDesktopLaunchedApplication(
            processIdentifier: process.processIdentifier,
            isRunning: { process.isRunning }
        )
    }
}

private final class QuillCodeDesktopWorkspaceLaunchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var resolvedApplication: NSRunningApplication?

    var application: NSRunningApplication? {
        lock.lock()
        defer { lock.unlock() }
        return resolvedApplication
    }

    func resolve(_ application: NSRunningApplication?) {
        lock.lock()
        resolvedApplication = application
        lock.unlock()
    }
}
