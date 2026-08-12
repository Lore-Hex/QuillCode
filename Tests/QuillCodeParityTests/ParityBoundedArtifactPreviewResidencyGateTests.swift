import XCTest

final class ParityBoundedArtifactPreviewResidencyGateTests: QuillCodeParityTestCase {
    func testTranscriptArtifactPreviewsUseRecentBoundedHydration() throws {
        let projection = try Self.appSourceText(named: "WorkspaceToolCardProjection.swift")
        let retention = try Self.appSourceText(named: "WorkspaceArtifactPreviewRetention.swift")
        let transcript = try Self.appSourceText(named: "WorkspaceTranscriptSurfaceBuilder.swift")
        let textPreview = try Self.appSourceText(named: "ToolArtifactTextPreviewBuilder.swift")

        Self.assertSource(projection, excludes: "ToolArtifactTextPreviewBuilder.textPreview")
        Self.assertSource(retention, containsAll: [
            "recentToolCardLimit = 12",
            "artifactInspectionLimit = 48",
            "textPreviewLimit = 8",
            "textPreviewByteLimit = 64 * 1024",
            "static func hydrate"
        ])
        Self.assertSource(transcript, contains: "WorkspaceArtifactPreviewRetention.hydrate")
        Self.assertSource(textPreview, containsAll: [
            "NSCache<TextPreviewCacheKey, Box>",
            "cacheEntryLimit = 16",
            "cacheByteLimit = 128 * 1024",
            ".contentModificationDateKey",
            ".fileResourceIdentifierKey"
        ])
    }
}
