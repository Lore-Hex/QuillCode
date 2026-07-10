import Foundation
import QuillCodeTools

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
                hitTargetKind: .text,
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
                hitTargetKind: .text,
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
            return WorkspaceHTMLPrimitives.button("Resume", testID: "terminal-resume", hitTargetKind: .text)
        }
        if terminal.canSuspend {
            return WorkspaceHTMLPrimitives.button("Suspend", testID: "terminal-suspend", hitTargetKind: .text)
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
            \(entry.mouseInputLabel.map { #"<span data-testid="terminal-mouse-mode">\#(escape($0))</span>"# } ?? "")
            <span class="terminal-status \(statusClass(entry))" data-testid="terminal-status">\(escape(entry.statusLabel)) · \(escape(entry.exitCodeLabel))</span>
          </header>
          \(renderOutput(
              entry.stdoutRuns,
              fallback: entry.stdout,
              testID: "terminal-stdout",
              defaultColor: nil,
              mouseReporting: entry.acceptsMouseInput ? entry.mouseReporting : nil
          ))
          \(renderOutput(entry.stderrRuns, fallback: entry.stderr, testID: "terminal-stderr", defaultColor: "#F0574C"))
        </article>
        """
    }

    private static func renderOutput(
        _ runs: [TerminalTextRun]?,
        fallback: String,
        testID: String,
        defaultColor: String?,
        mouseReporting: TerminalMouseReporting? = nil
    ) -> String {
        guard !fallback.isEmpty else { return "" }
        let source = runs ?? [TerminalTextRun(text: fallback)]
        let contents = source.map {
            renderRun($0, defaultColor: defaultColor)
        }.joined()
        let mouseAttributes = mouseReporting.map {
            #" data-terminal-mouse-input="true" data-terminal-mouse-encoding="\#(escape($0.encoding.rawValue))""#
        } ?? ""
        return #"<pre data-testid="\#(testID)"\#(mouseAttributes)>\#(contents)</pre>"#
    }

    private static func renderRun(_ run: TerminalTextRun, defaultColor: String?) -> String {
        let style = run.style
        var classes = ["terminal-ansi-run"]
        if style.isBold { classes.append("ansi-bold") }
        if style.isFaint { classes.append("ansi-faint") }
        if style.isItalic { classes.append("ansi-italic") }
        if style.isUnderlined { classes.append("ansi-underline") }
        if style.isInverse { classes.append("ansi-inverse") }
        if style.isConcealed { classes.append("ansi-concealed") }
        if style.isStrikethrough { classes.append("ansi-strikethrough") }

        var foreground = style.foreground.map { $0.resolvedRGB.cssHex } ?? defaultColor
        var background = style.background.map { $0.resolvedRGB.cssHex }
        if style.isInverse {
            let inverseBackground = foreground ?? "#ECECEC"
            foreground = background ?? "#171717"
            background = inverseBackground
        }

        var declarations: [String] = []
        if style.isConcealed {
            declarations.append("color:transparent")
        } else if let foreground {
            declarations.append("color:\(foreground)")
        }
        if let background { declarations.append("background-color:\(background)") }
        if style.isBold { declarations.append("font-weight:700") }
        if style.isFaint { declarations.append("opacity:.65") }
        if style.isItalic { declarations.append("font-style:italic") }
        let decorations = [
            style.isUnderlined ? "underline" : nil,
            style.isStrikethrough ? "line-through" : nil
        ].compactMap { $0 }
        if !decorations.isEmpty {
            declarations.append("text-decoration-line:\(decorations.joined(separator: " "))")
        }

        let styleAttribute = declarations.isEmpty
            ? ""
            : #" style="\#(declarations.joined(separator: ";"))""#
        return #"<span class="\#(classes.joined(separator: " "))"\#(styleAttribute)>\#(escape(run.text))</span>"#
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
