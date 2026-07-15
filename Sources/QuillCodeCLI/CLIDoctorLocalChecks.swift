import Foundation
import QuillCodePersistence

enum CLIDoctorLocalChecks {
    static func system(
        runtime: CLIDoctorRuntimeSnapshot,
        environment: [String: String]
    ) -> CLIDoctorCheck {
        let locale = firstValue(in: environment, keys: ["LC_ALL", "LC_CTYPE", "LANG"]) ?? "not set"
        return CLIDoctorCheck(
            id: "system.environment",
            category: "system",
            status: .ok,
            summary: "local environment is readable",
            details: .doctorDetails([
                "os": runtime.operatingSystem,
                "locale": locale,
                "EDITOR": presence(environment["EDITOR"]),
                "VISUAL": presence(environment["VISUAL"]),
                "PAGER": presence(environment["PAGER"]),
                "GIT_PAGER": presence(environment["GIT_PAGER"])
            ])
        )
    }

    static func runtime(_ runtime: CLIDoctorRuntimeSnapshot) -> CLIDoctorCheck {
        let executableExists = FileManager.default.isExecutableFile(atPath: runtime.executablePath)
        return CLIDoctorCheck(
            id: "runtime.provenance",
            category: "runtime",
            status: executableExists ? .ok : .fail,
            summary: executableExists ? "runtime executable is available" : "runtime executable is missing",
            details: .doctorDetails([
                "version": QuillCodeCommandRunner.version,
                "current executable": runtime.executablePath,
                "platform": runtime.operatingSystem
            ]),
            remediation: executableExists ? nil : "Reinstall QuillCode from a verified release."
        )
    }

    static func installation(
        runtime: CLIDoctorRuntimeSnapshot,
        environment: [String: String]
    ) -> CLIDoctorCheck {
        let matches = CLIDoctorExecutableLocator.matches(named: "quill-code", environment: environment)
        let executableExists = FileManager.default.isExecutableFile(atPath: runtime.executablePath)
        let status: CLIDoctorStatus = executableExists ? (matches.isEmpty ? .warning : .ok) : .fail
        let summary: String
        if !executableExists {
            summary = "the running QuillCode executable is unavailable"
        } else if matches.isEmpty {
            summary = "QuillCode is running but quill-code is not on PATH"
        } else if matches.count == 1 {
            summary = "installation looks consistent"
        } else {
            summary = "multiple quill-code executables are on PATH"
        }
        var details: [String: CLIDoctorDetail] = [
            "current executable": .text(CLIDoctorSanitizer.singleLine(runtime.executablePath)),
            "PATH quill-code entries": .text(String(matches.count))
        ]
        if !matches.isEmpty { details["PATH matches"] = .list(matches) }
        return CLIDoctorCheck(
            id: "installation",
            category: "install",
            status: status,
            summary: summary,
            details: details,
            remediation: status == .ok ? nil : "Put the intended quill-code executable first on PATH."
        )
    }

    static func search(environment: [String: String]) -> CLIDoctorCheck {
        let matches = CLIDoctorExecutableLocator.matches(named: "rg", environment: environment)
        return CLIDoctorCheck(
            id: "runtime.search",
            category: "search",
            status: matches.isEmpty ? .warning : .ok,
            summary: matches.isEmpty ? "ripgrep is unavailable" : "ripgrep is available",
            details: matches.isEmpty ? [:] : ["PATH matches": .list(matches)],
            remediation: matches.isEmpty
                ? "Install ripgrep for the fastest repository search experience."
                : nil
        )
    }

    static func git(_ snapshot: CLIDoctorGitSnapshot) -> CLIDoctorCheck {
        guard let version = snapshot.version else {
            return CLIDoctorCheck(
                id: "git.environment",
                category: "git",
                status: .fail,
                summary: "Git is unavailable",
                details: snapshot.error.map { ["error": .text(CLIDoctorSanitizer.singleLine($0))] } ?? [:],
                remediation: "Install Git and ensure it is available on PATH."
            )
        }
        var details: [String: CLIDoctorDetail] = ["git version": .text(version)]
        if let root = snapshot.repositoryRoot { details["repo root"] = .text(root) }
        if let branch = snapshot.branch, !branch.isEmpty { details["git branch"] = .text(branch) }
        if let error = snapshot.error { details["branch probe"] = .text(CLIDoctorSanitizer.singleLine(error)) }
        return CLIDoctorCheck(
            id: "git.environment",
            category: "git",
            status: snapshot.error == nil ? .ok : .warning,
            summary: snapshot.repositoryRoot == nil ? "Git is available; no repository detected" : version,
            details: details,
            remediation: snapshot.error == nil ? nil : "Check repository permissions and Git configuration."
        )
    }

    static func terminal(
        runtime: CLIDoctorRuntimeSnapshot,
        environment: [String: String]
    ) -> CLIDoctorCheck {
        let term = normalized(environment["TERM"]) ?? "not set"
        let unusableTerm = term == "not set" || term.caseInsensitiveCompare("dumb") == .orderedSame
        let attached = runtime.inputIsTerminal || runtime.outputIsTerminal || runtime.errorIsTerminal
        var issues: [CLIDoctorIssue] = []
        if unusableTerm {
            issues.append(CLIDoctorIssue(
                severity: .fail,
                cause: "TERM=\(term) disables full terminal interaction",
                measured: term,
                expected: "xterm-256color or another real terminal type",
                remedy: "Set TERM to a real terminal value.",
                fields: ["TERM"]
            ))
        }
        if !attached {
            issues.append(CLIDoctorIssue(
                severity: .warning,
                cause: "standard streams are not attached to a terminal",
                expected: "at least one terminal-attached standard stream"
            ))
        }
        let status = issues.map(\.severity).max { $0.rank < $1.rank } ?? .ok
        return CLIDoctorCheck(
            id: "terminal.env",
            category: "terminal",
            status: status,
            summary: unusableTerm ? "TERM=\(term) disables colors and cursor control" : "terminal environment is usable",
            details: .doctorDetails([
                "TERM": term,
                "COLORTERM": presence(environment["COLORTERM"]),
                "NO_COLOR": presence(environment["NO_COLOR"]),
                "stdin is terminal": String(runtime.inputIsTerminal),
                "stdout is terminal": String(runtime.outputIsTerminal),
                "stderr is terminal": String(runtime.errorIsTerminal)
            ]),
            remediation: unusableTerm ? "Set TERM to a real value, for example xterm-256color." : nil,
            issues: issues
        )
    }

    static func sandbox() -> CLIDoctorCheck {
        CLIDoctorCheck(
            id: "sandbox.helpers",
            category: "sandbox",
            status: .ok,
            summary: "enforceable CLI access modes are available",
            details: [
                "supported modes": .list(["read-only", "workspace-write"]),
                "danger-full-access": .text("rejected because this build cannot enforce it honestly")
            ]
        )
    }

    static func networkEnvironment(_ environment: [String: String]) -> CLIDoctorCheck {
        let proxyKeys = [
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy"
        ].filter { normalized(environment[$0]) != nil }
        return CLIDoctorCheck(
            id: "network.env",
            category: "network",
            status: .ok,
            summary: proxyKeys.isEmpty ? "no proxy environment variables are set" : "proxy environment is configured",
            details: ["proxy env vars": .list(proxyKeys.isEmpty ? ["none"] : proxyKeys)]
        )
    }

    static func appServer(paths: QuillCodePaths) -> CLIDoctorCheck {
        let metadataExists = FileManager.default.fileExists(atPath: paths.appServerMetadataDirectory.path)
        return CLIDoctorCheck(
            id: "app_server.status",
            category: "app-server",
            status: .ok,
            summary: "stdio app-server is available; no background daemon is configured",
            details: .doctorDetails([
                "transport": "stdio://",
                "background mode": "not configured",
                "thread metadata": metadataExists ? "available" : "not created yet"
            ])
        )
    }

    private static func presence(_ value: String?) -> String {
        normalized(value) == nil ? "not set" : "set"
    }

    private static func firstValue(in environment: [String: String], keys: [String]) -> String? {
        keys.compactMap { normalized(environment[$0]) }.first
    }

    private static func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : CLIDoctorSanitizer.singleLine(value)
    }
}
