import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func contract(
        _ id: String,
        family: QuillCodeInteractionSurfaceFamily,
        surface: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double?,
        minHeight: Double = Double(QuillCodeMetrics.minimumHitTarget),
        focusTarget: QuillCodeNativeFocusTarget? = nil,
        testID: String? = nil,
        commandID: String? = nil,
        source: String = "SwiftUI"
    ) -> QuillCodeNativeHitTargetContract {
        QuillCodeNativeHitTargetContract(
            id: id,
            family: family,
            surface: surface,
            label: label,
            kind: kind,
            minWidth: minWidth,
            minHeight: minHeight,
            focusTarget: focusTarget,
            testID: normalizedNativeTestID(testID),
            commandID: commandID,
            source: source
        )
    }

    static func normalizedNativeTestID(_ testID: String?) -> String? {
        guard let testID else { return nil }
        let trimmed = testID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return testID }
        return trimmed.hasPrefix("quillcode-") ? trimmed : "quillcode-\(trimmed)"
    }
}
