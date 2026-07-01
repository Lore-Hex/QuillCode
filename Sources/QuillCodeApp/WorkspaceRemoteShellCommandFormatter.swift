enum WorkspaceRemoteShellCommandFormatter {
    static func command(_ arguments: [String]) -> String {
        arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(value)
    }
}
