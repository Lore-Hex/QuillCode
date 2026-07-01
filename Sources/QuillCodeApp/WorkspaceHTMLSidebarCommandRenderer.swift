import Foundation

enum WorkspaceHTMLSidebarCommandRenderer {
    static func renderPrimaryActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.primaryCommandIDs
            .compactMap { commandID in
                commands.first { $0.id == commandID }
            }
            .map(renderPrimaryAction)
            .joined(separator: "\n")
    }

    static func renderFooter(_ commands: [WorkspaceCommandSurface]) -> String {
        """
        <div class="sidebar-footer" aria-label="Workspace tools">
          <details class="sidebar-tools-menu" data-testid="sidebar-tools-menu">
            \(WorkspaceHTMLPrimitives.summary(
                "Tools",
                testID: "sidebar-tools-button",
                hitTargetKind: .row,
                ariaLabel: "Tools",
                title: "Tools"
            ))
            <div class="sidebar-tools-popover" role="menu">
              \(renderUtilityActions(commands))
            </div>
          </details>
          \(WorkspaceHTMLPrimitives.button(
              "Settings",
              testID: "settings-button",
              hitTargetKind: .row,
              classes: ["sidebar-settings-button"],
              ariaLabel: "Settings",
              title: "Settings"
          ))
        </div>
        """
    }

    private static func renderPrimaryAction(_ command: WorkspaceCommandSurface) -> String {
        renderAction(command, style: .primary)
    }

    private static func renderUtilityActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups(from: commands)
            .map { group in
                """
                <section\(sectionAttributes(for: group))>
                  <h3 data-testid="sidebar-tools-section-title">\(escape(group.title))</h3>
                  \(group.commands.map(renderUtilityAction).joined(separator: "\n"))
                </section>
                """
            }
            .joined(separator: "\n")
    }

    private static func sectionAttributes(for group: QuillCodeSidebarVisibleCommandGroup) -> String {
        " " + [
            #"class="sidebar-tools-section""#,
            #"data-testid="sidebar-tools-section""#,
            #"data-command-group="\#(escape(group.id))""#
        ]
        .joined(separator: " ")
    }

    private static func renderUtilityAction(_ command: WorkspaceCommandSurface) -> String {
        renderAction(command, style: .utility)
    }

    private static func renderAction(_ command: WorkspaceCommandSurface, style: ActionStyle) -> String {
        let testID = QuillCodeSidebarCommandPresentation.htmlTestID(for: command.id)
        let icon = QuillCodeSidebarCommandPresentation.htmlIconToken(for: command.id)
        let title = QuillCodeSidebarCommandPresentation.displayTitle(for: command)
        return WorkspaceHTMLPrimitives.commandButton(
            title,
            testID: testID,
            commandID: command.id,
            hitTargetKind: .row,
            classes: style.classes,
            ariaLabel: style.ariaLabel(title),
            title: style.title(title),
            role: style.role,
            disabled: !command.isEnabled,
            attributes: style.attributes(icon: icon)
        )
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }

    private enum ActionStyle {
        case primary
        case utility

        var classes: [String] {
            switch self {
            case .primary:
                return ["sidebar-action"]
            case .utility:
                return ["sidebar-tool-action"]
            }
        }

        var role: String? {
            self == .utility ? "menuitem" : nil
        }

        func ariaLabel(_ title: String) -> String? {
            self == .utility ? title : nil
        }

        func title(_ title: String) -> String? {
            self == .utility ? title : nil
        }

        func attributes(icon: String) -> [(String, String?)] {
            switch self {
            case .primary:
                return [
                    ("data-primary", "true"),
                    ("data-icon", icon)
                ]
            case .utility:
                return [("data-icon", icon)]
            }
        }
    }
}
