import Foundation

enum WorkspaceHTMLTerminalRenderer {
    static func render(_ terminal: TerminalSurface) -> String {
        guard terminal.isVisible else { return "" }
        let entries = terminal.entries.isEmpty
            ? #"<p data-testid="terminal-empty">\#(escape(terminal.emptyTitle))</p>"#
            : terminal.entries.map(renderEntry).joined(separator: "\n")
        return """
        <section class="terminal-pane" data-testid="terminal-pane">
          <header>
            <strong>Terminal</strong>
            <code data-testid="terminal-cwd">\(escape(terminal.cwdLabel))</code>
            \(WorkspaceHTMLPrimitives.button(
                "Clear",
                testID: "terminal-clear",
                disabled: !terminal.canClear
            ))
            \(jobControlButton(terminal))
          </header>
          <div data-testid="terminal-history">
            \(entries)
          </div>
          <form data-testid="terminal-form">
            <input\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) aria-label="Terminal command" placeholder="\(escape(terminal.commandPlaceholder))" value="\(escape(terminal.draft))">
            \(WorkspaceHTMLPrimitives.button(
                terminal.commandActionTitle,
                testID: "terminal-run",
                type: "submit",
                disabled: !terminal.canSubmitDraft
            ))
          </form>
        </section>
        """
    }

    /// A running command shows a Suspend control; a suspended one shows Resume (job control, mutually
    /// exclusive). Nothing renders when no command is running.
    private static func jobControlButton(_ terminal: TerminalSurface) -> String {
        if terminal.canResume {
            return WorkspaceHTMLPrimitives.button("Resume", testID: "terminal-resume")
        }
        if terminal.canSuspend {
            return WorkspaceHTMLPrimitives.button("Suspend", testID: "terminal-suspend")
        }
        return ""
    }

    private static func renderEntry(_ entry: TerminalCommandSurface) -> String {
        """
        <article class="terminal-entry" data-testid="terminal-entry"\(entry.executionContext.map { #" data-execution-context="\#(escape($0.kind.rawValue))""# } ?? "")>
          <header>
            <span class="terminal-command-row">
              <code>$ \(escape(entry.command))</code>
              \(WorkspaceHTMLPrimitives.executionContextChip(entry.executionContext, testID: "terminal-execution-context"))
            </span>
            <span class="terminal-status \(statusClass(entry))" data-testid="terminal-status">\(escape(entry.statusLabel)) · \(escape(entry.exitCodeLabel))</span>
          </header>
          \(entry.stdout.isEmpty ? "" : #"<pre data-testid="terminal-stdout">\#(escape(entry.stdout))</pre>"#)
          \(entry.stderr.isEmpty ? "" : #"<pre data-testid="terminal-stderr">\#(escape(entry.stderr))</pre>"#)
        </article>
        """
    }

    private static func statusClass(_ entry: TerminalCommandSurface) -> String {
        if entry.isSuccess {
            return "ok"
        }
        if entry.isRunning {
            return "running"
        }
        if entry.isStopped {
            return "stopped"
        }
        return "failed"
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
