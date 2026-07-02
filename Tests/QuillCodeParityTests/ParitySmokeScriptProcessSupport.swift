import Foundation

extension QuillCodeParityTestCase {
    struct ScriptResult {
        let exitCode: Int32
        let output: String
    }

    static func runPython(_ script: URL, arguments: [String]) throws -> ScriptResult {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path] + arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ScriptResult(exitCode: process.terminationStatus, output: output)
    }

    static func scriptText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func workflowText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent(".github/workflows")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }
}
