import Foundation

extension TestCommandLexicon {
    /// Classifies one lowercased segment by reading argv[0] after stripping
    /// env-assignments and passthrough wrappers.
    static func classifySegment(_ segment: String) -> Match? {
        let rawTokens = strippingLeadingEnv(tokenize(segment))
        if isPresenceProbe(rawTokens) { return nil }

        let tokens = strippingLeadingWrappers(rawTokens)
        guard let head = tokens.first else { return nil }
        let program = basename(head)

        if let match = pythonModuleMatch(tokens) {
            return match
        }

        if runnerBasenames.contains(program) {
            return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
        }

        if testScriptBasenames.contains(program) {
            return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
        }

        if let subcommands = driverSubcommands[program] {
            let argTokens = Array(tokens.dropFirst())
            let subcommandMatches: Bool
            if flagsBeforeSubcommandDrivers.contains(program) {
                subcommandMatches = argTokens.contains(where: { subcommands.contains($0) })
            } else {
                subcommandMatches = firstNonFlagArgument(argTokens).map { subcommands.contains($0) } ?? false
            }
            if subcommandMatches {
                return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
            }
            if scriptRunnerBasenames.contains(program), isTestScriptRun(argTokens) {
                return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
            }
        }

        if scriptRunnerBasenames.contains(program), isTestScriptRun(tokens.dropFirst()) {
            return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
        }

        return nil
    }

    /// Recognizes `python[3] -m <testmodule> ...`.
    static func pythonModuleMatch(_ tokens: [String]) -> Match? {
        guard let head = tokens.first, pythonInterpreters.contains(basename(head)) else { return nil }
        var index = 1
        while index < tokens.count {
            if tokens[index] == "-m", index + 1 < tokens.count {
                let module = tokens[index + 1]
                guard pythonTestModules.contains(module) else { return nil }
                let moduleAndTargets = [module] + tokens[(index + 2)...]
                return Match(runner: "python -m \(module)", scope: scopeKey(runner: module, tokens: moduleAndTargets))
            }
            index += 1
        }
        return nil
    }

    /// Whether the tokens are a presence probe rather than an execution.
    static func isPresenceProbe(_ tokens: [String]) -> Bool {
        guard let head = tokens.first else { return false }
        let program = basename(head)
        if presenceProbePrograms.contains(program) { return true }
        if program == "command", tokens.count >= 2 {
            let flag = tokens[1]
            if flag == "-v" || flag == "-V" { return true }
        }
        return false
    }

    /// Strips leading `NAME=value` env-assignments.
    static func strippingLeadingEnv(_ tokens: [String]) -> [String] {
        var remaining = tokens
        while let head = remaining.first, isEnvAssignment(head) {
            remaining.removeFirst()
        }
        return remaining
    }

    /// A `run <script>` invocation where the script name is test-shaped.
    static func isTestScriptRun<S: Sequence>(_ argTokens: S) -> Bool where S.Element == String {
        var previous: String?
        for token in argTokens {
            if previous == "run", isTestScriptName(token) { return true }
            previous = token
        }
        return false
    }

    /// Reads a driver's first non-flag argument.
    static func firstNonFlagArgument(_ argTokens: [String]) -> String? {
        argTokens.first { !$0.hasPrefix("-") }
    }

    static func isTestScriptName(_ name: String) -> Bool {
        let separators = CharacterSet(charactersIn: ":-_./")
        let parts = name.components(separatedBy: separators)
        return parts.contains("test") || parts.contains("tests") || parts.contains("spec")
    }

    /// Strips leading env-assignments and passthrough wrappers so argv[0] is the real program.
    static func strippingLeadingWrappers(_ tokens: [String]) -> [String] {
        var remaining = tokens
        var progressed = true
        while progressed, let head = remaining.first {
            progressed = false
            if isEnvAssignment(head) {
                remaining.removeFirst()
                progressed = true
                continue
            }
            let program = basename(head)
            if let verbs = runVerbWrappers[program], remaining.count >= 2, verbs.contains(remaining[1]) {
                remaining.removeFirst(2)
                progressed = true
                continue
            }
            if passthroughWrappers.contains(program) {
                remaining.removeFirst()
                remaining = droppingWrapperFlags(remaining)
                progressed = true
                continue
            }
        }
        return remaining
    }

    /// Drops leading flags belonging to a stripped wrapper.
    static func droppingWrapperFlags(_ tokens: [String]) -> [String] {
        var remaining = tokens
        while let head = remaining.first, head.hasPrefix("-") {
            remaining.removeFirst()
            if head.count == 2, let next = remaining.first, !next.hasPrefix("-"), isFlagValue(next) {
                remaining.removeFirst()
            }
        }
        return remaining
    }

    /// Conservative flag-value detection used while stripping wrapper flags.
    static func isFlagValue(_ token: String) -> Bool {
        guard !isKnownProgram(basename(token)) else { return false }
        return token.allSatisfy { $0.isNumber }
    }

    static func isKnownProgram(_ program: String) -> Bool {
        runnerBasenames.contains(program)
            || driverSubcommands.keys.contains(program)
            || passthroughWrappers.contains(program)
            || runVerbWrappers.keys.contains(program)
            || scriptRunnerBasenames.contains(program)
            || testScriptBasenames.contains(program)
    }

    static func isEnvAssignment(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "="), eq != token.startIndex else { return false }
        let name = token[token.startIndex..<eq]
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Whitespace tokenizer for reading argv[0]/subcommands.
    static func tokenize(_ segment: String) -> [String] {
        segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    /// The trailing path component of a token.
    static func basename(_ token: String) -> String {
        let stripped = token.hasPrefix("./") ? String(token.dropFirst(2)) : token
        return stripped.split(separator: "/").last.map(String.init) ?? stripped
    }
}
