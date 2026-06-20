import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety

@main
struct QuillCodeCLI {
    static func main() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        var live = false
        var apiKey: String?
        var modelOverride: String?
        var baseURLOverride: String?
        let cwd: URL
        if let index = args.firstIndex(of: "--cwd"), args.indices.contains(args.index(after: index)) {
            cwd = URL(fileURLWithPath: args[args.index(after: index)])
            args.remove(at: args.index(after: index))
            args.remove(at: index)
        } else {
            cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        if let index = args.firstIndex(of: "--live") {
            live = true
            args.remove(at: index)
        }
        if let index = args.firstIndex(of: "--api-key"), args.indices.contains(args.index(after: index)) {
            apiKey = args[args.index(after: index)]
            args.remove(at: args.index(after: index))
            args.remove(at: index)
        }
        if let index = args.firstIndex(of: "--model"), args.indices.contains(args.index(after: index)) {
            modelOverride = args[args.index(after: index)]
            args.remove(at: args.index(after: index))
            args.remove(at: index)
        }
        if let index = args.firstIndex(of: "--base-url"), args.indices.contains(args.index(after: index)) {
            baseURLOverride = args[args.index(after: index)]
            args.remove(at: args.index(after: index))
            args.remove(at: index)
        }

        let prompt = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            print("Usage: quill-code [--live] [--api-key KEY] [--model MODEL] [--base-url URL] [--cwd PATH] \"run whoami\"")
            return
        }

        let paths = QuillCodePaths()
        try paths.ensure()
        let config = try ConfigStore(fileURL: paths.configFile).load()
        var thread = ChatThread(mode: config.mode, model: config.defaultModel)
        let runner: AgentRunner
        if live {
            let key = apiKey
                ?? ProcessInfo.processInfo.environment["QUILLCODE_API_KEY"]
                ?? ProcessInfo.processInfo.environment["TRUSTEDROUTER_API_KEY"]
            let baseURL = baseURLOverride ?? config.apiBaseURL
            let model = modelOverride ?? config.defaultModel
            let llm = TrustedRouterLLMClient(
                apiKeyOverride: key,
                model: model,
                baseURL: baseURL
            )
            let safetyClient = TrustedRouterSafetyModelClient(
                apiKeyOverride: key,
                baseURL: baseURL
            )
            runner = AgentRunner(
                llm: llm,
                safety: AutoSafetyReviewer(client: safetyClient)
            )
            thread.model = model
        } else {
            runner = AgentRunner()
        }
        let result = try await runner.send(prompt, in: thread, workspaceRoot: cwd)
        thread = result.thread
        try JSONThreadStore(directory: paths.threadsDirectory).save(thread)

        if let last = thread.messages.last {
            print(last.content)
        }
    }
}
