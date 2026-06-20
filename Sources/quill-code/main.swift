import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence

@main
struct QuillCodeCLI {
    static func main() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let cwd: URL
        if let index = args.firstIndex(of: "--cwd"), args.indices.contains(args.index(after: index)) {
            cwd = URL(fileURLWithPath: args[args.index(after: index)])
            args.remove(at: args.index(after: index))
            args.remove(at: index)
        } else {
            cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        let prompt = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            print("Usage: quill-code [--cwd PATH] \"run whoami\"")
            return
        }

        let paths = QuillCodePaths()
        try paths.ensure()
        let config = try ConfigStore(fileURL: paths.configFile).load()
        var thread = ChatThread(mode: config.mode, model: config.defaultModel)
        let runner = AgentRunner()
        let result = try await runner.send(prompt, in: thread, workspaceRoot: cwd)
        thread = result.thread
        try JSONThreadStore(directory: paths.threadsDirectory).save(thread)

        if let last = thread.messages.last {
            print(last.content)
        }
    }
}
