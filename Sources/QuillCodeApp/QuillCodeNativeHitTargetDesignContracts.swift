import Foundation

extension QuillCodeNativeHitTargetAudit {
    public static var designSystemContracts: [QuillCodeNativeHitTargetContract] {
        [
            designContract("design.icon", label: "Icon button", kind: .icon, minWidth: 44),
            designContract("design.text-button", label: "Text button", kind: .textButton, minWidth: 72),
            designContract("design.form-action", label: "Form action", kind: .formAction, minWidth: 56),
            designContract("design.link", label: "Link", kind: .link, minWidth: 72),
            designContract("design.text-entry", label: "Text entry", kind: .textEntry),
            designContract("design.segmented-control", label: "Segmented control", kind: .segmentedControl),
            designContract("design.adjustable-control", label: "Adjustable control", kind: .adjustableControl),
            designContract("design.switch-row", label: "Switch row", kind: .switchRow),
            designContract("design.owned-gesture", label: "Owned gesture target", kind: .ownedGesture),
            designContract("design.full-row", label: "Full row button", kind: .fullRow),
            designContract("design.capsule", label: "Capsule button", kind: .capsule)
        ]
    }

    private static func designContract(
        _ id: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double? = nil
    ) -> QuillCodeNativeHitTargetContract {
        contract(
            id,
            family: .designSystem,
            surface: "Design system",
            label: label,
            kind: kind,
            minWidth: minWidth
        )
    }
}
