import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety

@main
struct QuillCodeCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            writeError("quill-code: \(error)")
            exit(1)
        }
    }

    private static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        var live = false
        var apiKey: String?
        var modelOverride: String?
        var baseURLOverride: String?
        var homeOverride: URL?
        let cwd: URL
        if let index = args.firstIndex(of: "--cwd"), args.indices.contains(args.index(after: index)) {
            cwd = URL(fileURLWithPath: args[args.index(after: index)])
            args.remove(at: args.index(after: index))
            args.remove(at: index)
        } else {
            cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        if let index = args.firstIndex(of: "--home"), args.indices.contains(args.index(after: index)) {
            homeOverride = URL(fileURLWithPath: args[args.index(after: index)])
            args.remove(at: args.index(after: index))
            args.remove(at: index)
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

        let paths = QuillCodePaths(home: homeOverride ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".quillcode"))
        try paths.ensure()

        if args.first == "auth" {
            try handleAuth(Array(args.dropFirst()), paths: paths)
            return
        }

        let prompt = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            print(usage)
            return
        }

        let config = try ConfigStore(fileURL: paths.configFile).load()
        var thread = ChatThread(mode: config.mode, model: config.defaultModel)
        let runner: AgentRunner
        if live {
            let sessionStore = SecretTrustedRouterSessionStore(
                secretStore: FileSecretStore(directory: paths.secretsDirectory),
                key: QuillSecretKeys.trustedRouterAPIKey
            )
            let key = apiKey
                ?? ProcessInfo.processInfo.environment["QUILLCODE_API_KEY"]
                ?? ProcessInfo.processInfo.environment["TRUSTEDROUTER_API_KEY"]
            let baseURL = baseURLOverride ?? config.apiBaseURL
            let model = modelOverride ?? config.defaultModel
            let llm = TrustedRouterLLMClient(
                sessionStore: sessionStore,
                apiKeyOverride: key,
                model: model,
                baseURL: baseURL
            )
            let safetyClient = TrustedRouterSafetyModelClient(
                sessionStore: sessionStore,
                apiKeyOverride: key,
                baseURL: baseURL
            )
            // host.web.search routes through the same TrustedRouter credentials (gateway-side
            // provider selection, issue #861).
            let webSearch = TrustedRouterWebSearchClient(
                sessionStore: sessionStore,
                apiKeyOverride: key,
                model: model,
                baseURL: baseURL
            )
            runner = AgentRunner(
                llm: llm,
                safety: AutoSafetyReviewer(client: safetyClient),
                webSearch: webSearch,
                enablesImmediateActionPreflight: true
            )
            thread.model = model
        } else {
            runner = AgentRunner(enablesImmediateActionPreflight: true)
        }
        // The CLI honors the same per-project permission rules the desktop saves ("always
        // allow/deny"), composing them with — never replacing — the mode + intent safety review.
        var gatedRunner = runner
        gatedRunner.safety = PermissionRuleGatedSafetyReviewer(
            base: runner.safety,
            rules: PermissionRuleFileStore(directory: paths.permissionsDirectory)
        )
        let result = try await gatedRunner.send(prompt, in: thread, workspaceRoot: cwd)
        thread = result.thread
        try JSONThreadStore(directory: paths.threadsDirectory).save(thread)

        if let last = thread.messages.last {
            print(last.content)
        }
    }

    private static var usage: String {
        """
        Usage:
          quill-code [--live] [--api-key KEY] [--model MODEL] [--base-url URL] [--cwd PATH] [--home PATH] "run whoami"
          quill-code [--home PATH] auth status
          quill-code [--home PATH] auth set-key KEY
          quill-code [--home PATH] auth clear
        """
    }

    private static func handleAuth(_ args: [String], paths: QuillCodePaths) throws {
        let store = FileSecretStore(directory: paths.secretsDirectory)
        switch args.first {
        case "status":
            let key = try store.read(QuillSecretKeys.trustedRouterAPIKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print(key?.isEmpty == false ? "TrustedRouter key configured." : "TrustedRouter key not configured.")
        case "set-key":
            guard args.count >= 2 else {
                print("Usage: quill-code auth set-key KEY")
                return
            }
            let key = args[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                print("TrustedRouter key cannot be empty.")
                return
            }
            try store.write(key, for: QuillSecretKeys.trustedRouterAPIKey)
            print("TrustedRouter key saved.")
        case "clear":
            try store.delete(QuillSecretKeys.trustedRouterAPIKey)
            print("TrustedRouter key cleared.")
        default:
            print(usage)
        }
    }

    private static func writeError(_ message: String) {
        guard let data = "\(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
