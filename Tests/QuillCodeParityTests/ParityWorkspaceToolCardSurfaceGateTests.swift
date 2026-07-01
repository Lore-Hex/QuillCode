import XCTest

final class ParityWorkspaceToolCardSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesToolCardSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let cardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let artifactSurfaceText = try Self.appSourceText(
            named: "QuillCodeToolArtifactSurface.swift"
        )
        let classifierText = try Self.appSourceText(named: "ToolArtifactValueClassifier.swift")
        let imagePreviewText = try Self.appSourceText(
            named: "ToolArtifactImagePreviewBuilder.swift"
        )
        let documentPreviewText = try Self.appSourceText(
            named: "ToolArtifactDocumentPreviewBuilder.swift"
        )
        let textPreviewText = try Self.appSourceText(
            named: "ToolArtifactTextPreviewBuilder.swift"
        )
        let transcriptBuilderText = try Self.appSourceText(
            named: "WorkspaceTranscriptSurfaceBuilder.swift"
        )
        let reducerText = try Self.appSourceText(named: "WorkspaceToolCardEventReducer.swift")
        let projectionText = try Self.appSourceText(named: "WorkspaceToolCardProjection.swift")

        Self.assertSource(cardSurfaceText, contains: "public struct ToolCardState")
        Self.assertSource(artifactSurfaceText, containsAll: [
            "public struct ToolArtifactState",
            "ToolArtifactValueClassifier.kind",
            "ToolArtifactImagePreviewBuilder.imagePreview",
            "ToolArtifactDocumentPreviewBuilder.documentPreview",
            "public struct ToolArtifactDocumentPreview",
            "public struct ToolArtifactImagePreview"
        ])
        Self.assertSource(classifierText, contains: "enum ToolArtifactValueClassifier")
        Self.assertSource(imagePreviewText, contains: "enum ToolArtifactImagePreviewBuilder")
        Self.assertSource(documentPreviewText, contains: "enum ToolArtifactDocumentPreviewBuilder")
        Self.assertSource(textPreviewText, contains: "enum ToolArtifactTextPreviewBuilder")
        Self.assertSource(reducerText, containsAll: [
            "struct WorkspaceToolCardEventReducer",
            "WorkspaceToolCardProjection"
        ])
        Self.assertSource(projectionText, containsAll: [
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
        Self.assertSource(reducerText, excludes: "ToolArtifactTextPreviewBuilder.textPreview")
        Self.assertSource(artifactSurfaceText, excludesAll: [
            "private static func documentPreview",
            "private static func isImagePreview",
            "private static func localArtifactFileURL"
        ])
        Self.assertSource(cardSurfaceText, excludesAll: [
            "ToolArtifactTextPreviewBuilder",
            "public enum ToolArtifactDocumentKind"
        ])
    }
}
