import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func surfaceContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        persistentSurfaceContracts()
            + canonicalTransientSurfaceContracts()
            + commandContracts(from: surface.commands)
            + conditionalPaneContracts(for: surface)
    }
}
