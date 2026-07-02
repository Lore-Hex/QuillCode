import Foundation

/// How to launch a language server for a family of file extensions, plus the LSP `languageId` to
/// tag documents with. `command` is resolved on PATH (via `/usr/bin/env`) or, for the special value
/// handled by discovery, located with `xcrun`.
public struct LSPServerConfig: Sendable, Equatable {
    /// Lowercased file extensions (no dot) this server handles.
    public var fileExtensions: [String]
    /// The LSP `languageId` for `didOpen` (e.g. "swift").
    public var languageID: String
    /// The executable name or absolute path. A bare name is resolved via `xcrun` (for the Swift
    /// toolchain) or `env` on PATH.
    public var command: String
    /// Extra arguments to pass the server.
    public var arguments: [String]

    public init(fileExtensions: [String], languageID: String, command: String, arguments: [String] = []) {
        self.fileExtensions = fileExtensions.map { $0.lowercased() }
        self.languageID = languageID
        self.command = command
        self.arguments = arguments
    }
}

/// The generic language → server table. sourcekit-lsp ships as the built-in default for Swift; other
/// languages are added by extending `defaults` (or, in a follow-up, a workspace config file). The
/// registry is pure data + discovery — it launches nothing itself.
public struct LSPServerRegistry: Sendable {
    public private(set) var configs: [LSPServerConfig]
    private let commandLocator: LSPCommandLocating

    public init(configs: [LSPServerConfig] = LSPServerRegistry.defaults, commandLocator: LSPCommandLocating = LSPCommandLocator()) {
        self.configs = configs
        self.commandLocator = commandLocator
    }

    /// The shipped default: sourcekit-lsp for Swift. Kept as a single-element table on purpose — the
    /// mapping is the extension point, and QuillOS is a Swift project, so Swift is what we validate
    /// end to end. Adding, say, `typescript-language-server` is one more entry here.
    public static let defaults: [LSPServerConfig] = [
        LSPServerConfig(fileExtensions: ["swift"], languageID: "swift", command: "sourcekit-lsp")
    ]

    /// The server config whose extensions include this path's extension, or `nil` if none.
    public func config(forPath path: String) -> LSPServerConfig? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return configs.first { $0.fileExtensions.contains(ext) }
    }

    /// Resolves a config's `command` to an absolute executable path, or `nil` if the server is not
    /// installed. This is the single point where a *missing* language server is detected — every
    /// caller degrades gracefully on `nil`.
    public func resolveExecutable(for config: LSPServerConfig) -> String? {
        commandLocator.locate(command: config.command)
    }
}

/// Locates an executable by name. Behind a protocol so tests can inject a locator that reports a
/// server present/absent without touching the real filesystem or spawning `xcrun`.
public protocol LSPCommandLocating: Sendable {
    func locate(command: String) -> String?
}

/// Default locator: an absolute path is used as-is if executable; otherwise the command is looked up
/// first in the active Swift toolchain via `xcrun --find` (so sourcekit-lsp is found even when not on
/// PATH), then on `PATH` via `/usr/bin/env`. All lookups are bounded with a short timeout so a
/// hanging `xcrun` never stalls a write.
public struct LSPCommandLocator: LSPCommandLocating {
    public init() {}

    public func locate(command: String) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        #if os(macOS)
        if let found = run(executable: "/usr/bin/xcrun", arguments: ["--find", command]) {
            return found
        }
        #endif
        // `command -v` respects PATH and resolves shell builtins/aliases the way a launch would.
        if let found = run(executable: "/usr/bin/env", arguments: ["sh", "-c", "command -v \(shellQuote(command))"]) {
            return found
        }
        return nil
    }

    /// Runs a short discovery command, returning its trimmed first line of stdout on a clean exit, or
    /// `nil` on failure/timeout/non-executable-result. stdout and stderr are drained on background
    /// queues *concurrently* with the wait, so a command that emits more than a pipe buffer (~64KB)
    /// cannot deadlock (it never blocks on a write to a pipe no one is reading).
    private func run(executable: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return nil
        }

        // Drain both pipes concurrently so the child never blocks writing to a full, unread pipe.
        let collected = NSMutableData()
        let readerGroup = DispatchGroup()
        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { readerGroup.leave() }
            collected.append(output.fileHandleForReading.readDataToEndOfFile())
        }
        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { readerGroup.leave() }
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            _ = readerGroup.wait(timeout: .now() + 1)
            return nil
        }
        // The readers finish at EOF, which the child produces on exit.
        _ = readerGroup.wait(timeout: .now() + 1)
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: collected as Data, as: UTF8.self)
            .split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
