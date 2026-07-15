import Foundation
import QuillCodeCore

public struct CLIArgumentParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String], currentDirectory: URL) throws -> CLICommand {
        var arguments = arguments
        let home = try removeGlobalValue("--home", from: &arguments).map {
            cliPathURL($0, relativeTo: currentDirectory)
        }

        guard let first = arguments.first else { return .help }
        if first == "--help" || first == "-h" || first == "help" { return .help }
        if first == "--version" || first == "version" { return .version }
        if first == "auth" {
            return try parseAuth(Array(arguments.dropFirst()), home: home)
        }
        if first == "doctor" {
            return .doctor(try parseDoctor(Array(arguments.dropFirst()), home: home))
        }
        if first == "review" {
            return .review(try CLIReviewArgumentParser().parse(
                Array(arguments.dropFirst()),
                currentDirectory: currentDirectory,
                home: home
            ))
        }
        if first == "app-server" {
            return .appServer(try parseAppServer(
                Array(arguments.dropFirst()),
                home: home
            ))
        }
        if first == "mcp-server" {
            return .mcpServer(try parseMCPServer(
                Array(arguments.dropFirst()),
                home: home
            ))
        }
        if first == "exec" {
            return .run(try parseRun(
                Array(arguments.dropFirst()),
                style: .exec,
                currentDirectory: currentDirectory,
                home: home
            ))
        }
        return .run(try parseRun(
            arguments,
            style: .legacy,
            currentDirectory: currentDirectory,
            home: home
        ))
    }

    private func parseAppServer(
        _ arguments: [String],
        home: URL?
    ) throws -> CLIAppServerRequest {
        var request = CLIAppServerRequest(home: home)
        var index = 0
        while index < arguments.count {
            let option = cliSplitOption(arguments[index])
            switch option.name {
            case "--listen":
                let value = try cliValue(for: option, tokens: arguments, index: &index)
                guard let transport = CLIAppServerTransport(rawValue: value) else {
                    throw CLIError.unsupportedAppServerTransport(value)
                }
                request.transport = transport
            default:
                guard try parseServerRuntimeOption(
                    option,
                    tokens: arguments,
                    index: &index,
                    request: &request
                ) else {
                    throw CLIError.unknownOption(option.name)
                }
            }
            index += 1
        }
        return request
    }

    private func parseMCPServer(
        _ arguments: [String],
        home: URL?
    ) throws -> CLIMCPServerRequest {
        var request = CLIMCPServerRequest(home: home)
        var index = 0
        while index < arguments.count {
            let option = cliSplitOption(arguments[index])
            guard try parseServerRuntimeOption(
                option,
                tokens: arguments,
                index: &index,
                request: &request
            ) else {
                throw CLIError.unknownOption(option.name)
            }
            index += 1
        }
        return request
    }

    private func parseServerRuntimeOption<Request: CLIServerRuntimeRequest>(
        _ option: CLIParsedOption,
        tokens: [String],
        index: inout Int,
        request: inout Request
    ) throws -> Bool {
        switch option.name {
        case "--live":
            request.live = true
        case "--mock":
            request.live = false
        case "--api-key":
            request.apiKey = try cliValue(for: option, tokens: tokens, index: &index)
        case "--model", "-m":
            request.model = try cliValue(for: option, tokens: tokens, index: &index)
        case "--base-url":
            request.baseURL = try cliValue(for: option, tokens: tokens, index: &index)
        default:
            return false
        }
        return true
    }

    private func parseAuth(_ arguments: [String], home: URL?) throws -> CLICommand {
        guard let command = arguments.first else { return .help }
        switch command {
        case "status":
            guard arguments.count == 1 else { throw CLIError.unknownOption(arguments[1]) }
            return .auth(.status, home: home)
        case "set-key":
            guard arguments.count >= 2 else { throw CLIError.missingOptionValue("auth set-key") }
            guard arguments.count == 2 else { throw CLIError.unknownOption(arguments[2]) }
            let key = arguments[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw CLIError.missingOptionValue("auth set-key") }
            return .auth(.setKey(key), home: home)
        case "clear":
            guard arguments.count == 1 else { throw CLIError.unknownOption(arguments[1]) }
            return .auth(.clear, home: home)
        default:
            throw CLIError.unknownOption(command)
        }
    }

    private func parseDoctor(_ arguments: [String], home: URL?) throws -> CLIDoctorRequest {
        var request = CLIDoctorRequest(home: home)
        for argument in arguments {
            switch argument {
            case "--json":
                request.emitsJSON = true
            case "--summary":
                request.summaryOnly = true
            case "--all":
                request.expandsLongLists = true
            case "--no-color":
                request.disablesColor = true
            case "--ascii":
                request.usesASCII = true
            case "--help", "-h":
                request.showsHelp = true
            default:
                throw CLIError.unknownOption(cliSplitOption(argument).name)
            }
        }
        return request
    }

    private func parseRun(
        _ arguments: [String],
        style: CLIInvocationStyle,
        currentDirectory: URL,
        home: URL?
    ) throws -> CLIRunRequest {
        var tokens = arguments
        var resumeTarget: CLIResumeTarget?
        if style == .exec, tokens.first == "resume" {
            tokens.removeFirst()
            guard let target = tokens.first else { throw CLIError.missingOptionValue("exec resume") }
            tokens.removeFirst()
            if target == "--last" {
                resumeTarget = .last
            } else if let id = UUID(uuidString: target) {
                resumeTarget = .id(id)
            } else {
                throw CLIError.invalidResumeTarget(target)
            }
        }

        var request = CLIRunRequest(
            style: style,
            prompt: "",
            resumeTarget: resumeTarget,
            live: style == .exec,
            cwd: currentDirectory,
            home: home,
            sandbox: style == .exec ? .readOnly : nil
        )
        var promptParts: [String] = []
        var index = 0
        var optionsEnded = false
        while index < tokens.count {
            let token = tokens[index]
            if optionsEnded {
                promptParts.append(token)
                index += 1
                continue
            }
            if token == "--" {
                optionsEnded = true
                index += 1
                continue
            }
            if token == "-" {
                promptParts.append(token)
                index += 1
                continue
            }

            let option = cliSplitOption(token)
            switch option.name {
            case "--live":
                request.live = true
            case "--mock":
                request.live = false
            case "--ephemeral":
                request.ephemeral = true
            case "--json":
                request.emitsJSONLines = true
            case "--ignore-user-config":
                request.ignoresUserConfig = true
            case "--ignore-rules":
                request.ignoresPermissionRules = true
            case "--skip-git-repo-check":
                request.skipsGitRepositoryCheck = true
            case "--full-auto":
                request.sandbox = .workspaceWrite
                request.usedDeprecatedFullAuto = true
            case "--api-key":
                request.apiKey = try cliValue(for: option, tokens: tokens, index: &index)
            case "--model", "-m":
                request.model = try cliValue(for: option, tokens: tokens, index: &index)
            case "--base-url":
                request.baseURL = try cliValue(for: option, tokens: tokens, index: &index)
            case "--cwd", "-C":
                request.cwd = cliPathURL(
                    try cliValue(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                )
            case "--image":
                request.imageURLs.append(cliPathURL(
                    try cliValue(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                ))
            case "--output-last-message", "-o":
                request.outputLastMessageURL = cliPathURL(
                    try cliValue(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                )
            case "--output-schema":
                request.outputSchemaURL = cliPathURL(
                    try cliValue(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                )
            case "--sandbox":
                let raw = try cliValue(for: option, tokens: tokens, index: &index)
                guard let sandbox = CLISandboxMode(rawValue: raw) else {
                    throw CLIError.invalidOptionValue(option: option.name, value: raw)
                }
                request.sandbox = sandbox
            case "--mode":
                let raw = try cliValue(for: option, tokens: tokens, index: &index)
                guard let mode = AgentMode(rawValue: raw) else {
                    throw CLIError.invalidOptionValue(option: option.name, value: raw)
                }
                request.explicitMode = mode
            case "--help", "-h":
                throw CLIError.unknownOption("Use `quill-code help` for command help.")
            default:
                if token.hasPrefix("-") {
                    throw CLIError.unknownOption(option.name)
                }
                promptParts.append(token)
            }
            index += 1
        }

        if promptParts.contains("-"), promptParts.count != 1 {
            throw CLIError.invalidOptionValue(option: "prompt", value: promptParts.joined(separator: " "))
        }
        request.prompt = promptParts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return request
    }

    private func removeGlobalValue(_ name: String, from arguments: inout [String]) throws -> String? {
        var found: String?
        var index = 0
        while index < arguments.count {
            let option = cliSplitOption(arguments[index])
            guard option.name == name else {
                index += 1
                continue
            }
            guard found == nil else { throw CLIError.invalidOptionValue(option: name, value: "duplicate") }
            if let inlineValue = option.inlineValue {
                found = inlineValue
                arguments.remove(at: index)
            } else {
                let valueIndex = index + 1
                guard arguments.indices.contains(valueIndex) else { throw CLIError.missingOptionValue(name) }
                found = arguments[valueIndex]
                arguments.removeSubrange(index...valueIndex)
            }
        }
        return found
    }

}

private protocol CLIServerRuntimeRequest {
    var live: Bool { get set }
    var apiKey: String? { get set }
    var model: String? { get set }
    var baseURL: String? { get set }
}

extension CLIAppServerRequest: CLIServerRuntimeRequest {}
extension CLIMCPServerRequest: CLIServerRuntimeRequest {}
