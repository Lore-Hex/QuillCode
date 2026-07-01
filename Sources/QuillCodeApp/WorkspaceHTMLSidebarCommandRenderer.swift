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
        renderCommandButton(
            command,
            hitTargetKind: .row,
            classes: ["sidebar-action"],
            attributes: [("data-primary", "true")]
        )
    }

    private static func renderUtilityActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups(from: commands)
            .map { group in
                """
                <section\(utilitySectionAttributes(for: group))>
                  <h3 data-testid="sidebar-tools-section-title">\(escape(group.title))</h3>
                  \(group.commands.map(renderUtilityAction).joined(separator: "\n"))
                </section>
                """
            }
            .joined(separator: "\n")
    }

    private static func renderUtilityAction(_ command: WorkspaceCommandSurface) -> String {
        let title = displayTitle(for: command)
        return renderCommandButton(
            command,
            hitTargetKind: .row,
            classes: ["sidebar-tool-action"],
            ariaLabel: title,
            title: title,
            role: "menuitem",
            label: title
        )
    }

    private static func renderCommandButton(
        _ command: WorkspaceCommandSurface,
        hitTargetKind: WorkspaceHTMLHitTargetKind,
        classes: [String],
        ariaLabel: String? = nil,
        title: String? = nil,
        role: String? = nil,
        label: String? = nil,
        attributes: [(String, String?)] = []
    ) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            label ?? displayTitle(for: command),
            testID: QuillCodeSidebarCommandPresentation.htmlTestID(for: command.id),
            commandID: command.id,
            hitTargetKind: hitTargetKind,
            classes: classes,
            ariaLabel: ariaLabel,
            title: title,
            role: role,
            disabled: !command.isEnabled,
            attributes: attributes + iconAttributes(for: command)
        )
    }

    private static func displayTitle(for command: WorkspaceCommandSurface) -> String {
        QuillCodeSidebarCommandPresentation.displayTitle(for: command)
    }

    private static func iconAttributes(for command: WorkspaceCommandSurface) -> [(String, String?)] {
        [
            ("data-icon", QuillCodeSidebarCommandPresentation.htmlIconToken(for: command.id))
        ]
    }

    private static func utilitySectionAttributes(for group: QuillCodeSidebarVisibleCommandGroup) -> String {
        let attributes = [
            #"class="sidebar-tools-section""#,
            #"data-testid="sidebar-tools-section""#,
            #"data-command-group="\#(escape(group.id))""#
        ]
        return " " + attributes.joined(separator: " ")
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
