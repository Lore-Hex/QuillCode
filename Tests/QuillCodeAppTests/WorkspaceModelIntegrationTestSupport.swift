import Foundation
import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuillCodeAppTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeFakeSSH(in root: URL, argumentsFile: URL) throws -> URL {
    let script = root.appendingPathComponent("fake-ssh")
    let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
    try """
    #!/bin/sh
    printf '%s\\n' "$@" > '\(argumentsPath)'
    echo 'remote-terminal'
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

func makeExecutingFakeSSH(in root: URL, argumentsFile: URL, pathPrefix: URL? = nil) throws -> URL {
    let script = root.appendingPathComponent("fake-executing-ssh")
    let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
    let pathExport = pathPrefix.map { "export PATH='\($0.path.replacingOccurrences(of: "'", with: "'\\''"))':$PATH" } ?? ":"
    try """
    #!/bin/sh
    : > '\(argumentsPath)'
    last=''
    for arg in "$@"; do
      printf '%s\\n' "$arg" >> '\(argumentsPath)'
      last="$arg"
    done
    \(pathExport)
    /bin/sh -c "$last"
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

func makeFakeGitHubCLI(in root: URL, argumentsFile: URL) throws -> URL {
    let script = root.appendingPathComponent("gh")
    let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
    try """
    #!/bin/sh
    printf '%s\\n' "$@" > '\(argumentsPath)'
    echo 'https://github.com/example/repo/pull/456'
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

func initializeGitRepository(at root: URL) throws {
    _ = try runGit(["init"], cwd: root)
    _ = try runGit(["config", "user.email", "quillcode-tests@example.com"], cwd: root)
    _ = try runGit(["config", "user.name", "QuillCode Tests"], cwd: root)
}

func makeTempGitRepoWithInitialCommit() throws -> URL {
    let parent = try makeTempDirectory()
    let root = parent.appendingPathComponent("repo")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try initializeGitRepository(at: root)
    try "# Test repo\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    _ = try runGit(["add", "README.md"], cwd: root)
    _ = try runGit(["commit", "-m", "initial"], cwd: root)
    return root
}

func runGit(_ arguments: [String], cwd: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = cwd

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "QuillCodeAppTests.Git",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? out : err]
        )
    }
    return out
}

func currentBranchName(in root: URL) throws -> String {
    let branch = try runGit(["branch", "--show-current"], cwd: root)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    XCTAssertFalse(branch.isEmpty)
    return branch
}

struct FixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

final class ToolDefinitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTools: [ToolDefinition] = []

    var tools: [ToolDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTools
    }

    func record(_ tools: [ToolDefinition]) {
        lock.lock()
        recordedTools = tools
        lock.unlock()
    }
}

struct RecordingLLMClient: LLMClient {
    var recorder: ToolDefinitionRecorder

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        recorder.record(tools)
        return .say("Recorded tool definitions.")
    }
}
