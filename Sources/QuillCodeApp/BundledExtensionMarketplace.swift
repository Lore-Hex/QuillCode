import Foundation
import QuillCodeCore

enum BundledExtensionMarketplace {
    static let manifests: [ProjectExtensionManifest] = [
        ProjectExtensionManifest(
            id: "skill:burstyrouter",
            kind: .skill,
            name: "BurstyRouter",
            summary: "Route LLM calls local-first to a local server, then burst overflow to TrustedRouter Cloud.",
            sourceURL: "https://github.com/Lore-Hex/BurstyRouter",
            relativePath: ".quillcode/marketplace/burstyrouter.json"
        )
    ]

    static func availableManifests(
        excluding claimedManifests: [ProjectExtensionManifest]
    ) -> [ProjectExtensionManifest] {
        let claimedIDs = Set(claimedManifests.map(\.id))
        return Self.manifests.filter { !claimedIDs.contains($0.id) }
    }
}
