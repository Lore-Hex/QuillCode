import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func extensionTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "extensions.family-entry",
                family: .extensions,
                surface: "Extensions",
                label: "Extension action",
                kind: .formAction,
                minWidth: 74,
                testID: "extension-action"
            ),
            contract(
                "extensions.reference-action",
                family: .extensions,
                surface: "Extensions",
                label: "MCP resource or prompt action",
                kind: .capsule,
                minWidth: 96,
                testID: "extension-reference-action"
            )
        ]
    }

    static func memoryTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "memories.family-entry",
                family: .memories,
                surface: "Memories",
                label: "Add memory",
                kind: .formAction,
                minWidth: 56,
                testID: "memory-add"
            ),
            contract(
                "memories.item-action",
                family: .memories,
                surface: "Memories",
                label: "Memory row action",
                kind: .icon,
                minWidth: 44,
                testID: "memory-row-action"
            )
        ]
    }

    static func automationTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "automations.family-entry",
                family: .automations,
                surface: "Automations",
                label: "Create automation",
                kind: .formAction,
                minWidth: 90,
                testID: "automation-create"
            )
        ]
    }

    static func menuBarTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "menu-bar.action",
                family: .menuBar,
                surface: "Menu bar",
                label: "Menu bar action",
                kind: .fullRow,
                minWidth: nil,
                testID: "menu-bar-action"
            )
        ]
    }
}
