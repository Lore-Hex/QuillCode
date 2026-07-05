import XCTest

final class ParityWorkspaceToolCardModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesToolCardSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let toolArtifactSurfaceText = try Self.appSourceText(named: "QuillCodeToolArtifactSurface.swift")
        let artifactValueClassifierText = try Self.appSourceText(named: "ToolArtifactValueClassifier.swift")
        let artifactImagePreviewText = try Self.appSourceText(named: "ToolArtifactImagePreviewBuilder.swift")
        let artifactImageMetadataText = try Self.appSourceText(named: "ToolArtifactImageMetadataReader.swift")
        let artifactDocumentPreviewText = try Self.appSourceText(named: "ToolArtifactDocumentPreviewBuilder.swift")
        let artifactTextPreviewText = try Self.appSourceText(named: "ToolArtifactTextPreviewBuilder.swift")
        let transcriptBuilderText = try Self.appSourceText(named: "WorkspaceTranscriptSurfaceBuilder.swift")
        let toolCardReducerText = try Self.appSourceText(named: "WorkspaceToolCardEventReducer.swift")
        let toolCardProjectionText = try Self.appSourceText(named: "WorkspaceToolCardProjection.swift")

        Self.assertSource(toolCardSurfaceText, contains: "public struct ToolCardState")
        Self.assertSource(toolArtifactSurfaceText, containsAll: [
            "public struct ToolArtifactState",
            "ToolArtifactValueClassifier.kind",
            "ToolArtifactImagePreviewBuilder.imagePreview",
            "ToolArtifactDocumentPreviewBuilder.documentPreview",
            "public struct ToolArtifactDocumentPreview",
            "public struct ToolArtifactImagePreview"
        ])
        Self.assertSource(artifactValueClassifierText, contains: "enum ToolArtifactValueClassifier")
        Self.assertSource(artifactImagePreviewText, contains: "enum ToolArtifactImagePreviewBuilder")
        Self.assertSource(artifactImagePreviewText, contains: "ToolArtifactImageMetadataReader.dimensionsLabel")
        Self.assertSource(artifactImageMetadataText, containsAll: [
            "enum ToolArtifactImageMetadataReader",
            "maximumHeaderBytes",
            "pngDimensions",
            "gifDimensions",
            "jpegDimensions"
        ])
        Self.assertSource(artifactDocumentPreviewText, contains: "enum ToolArtifactDocumentPreviewBuilder")
        Self.assertSource(artifactTextPreviewText, contains: "enum ToolArtifactTextPreviewBuilder")
        Self.assertSource(toolCardReducerText, containsAll: [
            "struct WorkspaceToolCardEventReducer",
            "WorkspaceToolCardProjection"
        ])
        Self.assertSource(toolCardProjectionText, containsAll: [
            "enum WorkspaceToolCardProjection",
            "ToolArtifactTextPreviewBuilder.textPreview"
        ])
        Self.assertSource(transcriptBuilderText, contains: "WorkspaceToolCardEventReducer")
        Self.assertSource(modelText, excludesAll: [
            "public struct ToolCardState",
            "public enum ToolCardStatus",
            "public struct ToolArtifactState",
            "ToolArtifactTextPreviewBuilder.textPreview"
        ])
        Self.assertSource(transcriptBuilderText, excludesAll: [
            "ToolArtifactTextPreviewBuilder.textPreview",
            "private static func approvalReviewCard"
        ])
        Self.assertSource(toolCardReducerText, excludes: "ToolArtifactTextPreviewBuilder.textPreview")
        Self.assertSource(toolArtifactSurfaceText, excludesAll: [
            "private static func documentPreview",
            "private static func isImagePreview",
            "private static func localArtifactFileURL"
        ])
        Self.assertSource(toolCardSurfaceText, excludesAll: [
            "ToolArtifactTextPreviewBuilder",
            "public enum ToolArtifactDocumentKind"
        ])
    }
}
