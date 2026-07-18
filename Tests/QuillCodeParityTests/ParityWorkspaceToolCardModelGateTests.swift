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
        let artifactAppshotPreviewText = try Self.appSourceText(named: "ToolArtifactAppshotPreviewBuilder.swift")
        let artifactPDFPreviewText = try Self.appSourceText(named: "ToolArtifactPDFPreviewBuilder.swift")
        let artifactPDFPagePreviewText = try Self.appSourceText(named: "QuillCodeArtifactPDFPagePreviewView.swift")
        let artifactOfficePreviewText = try Self.appSourceText(named: "ToolArtifactOfficePreviewBuilder.swift")
        let artifactArchivePreviewText = try Self.appSourceText(named: "ToolArtifactArchivePreviewBuilder.swift")
        let artifactMediaPreviewText = try Self.appSourceText(named: "ToolArtifactMediaPreviewBuilder.swift")
        let artifactMediaPlaybackText = try Self.appSourceText(named: "QuillCodeArtifactMediaPlaybackView.swift")
        let artifactDocumentPreviewViewText = try Self.appSourceText(named: "QuillCodeArtifactDocumentPreview.swift")
        let artifactZipCentralDirectoryText = try Self.appSourceText(named: "ToolArtifactZipCentralDirectoryReader.swift")
        let artifactTablePreviewText = try Self.appSourceText(named: "ToolArtifactTablePreviewBuilder.swift")
        let artifactByteSizeText = try Self.appSourceText(named: "ToolArtifactByteSizeFormatter.swift")
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
            "ToolArtifactAppshotPreviewBuilder.appshotPreview",
            "ToolArtifactPDFPreviewBuilder.pdfPreview",
            "ToolArtifactOfficePreviewBuilder.officePreview",
            "ToolArtifactTablePreviewBuilder.tablePreview",
            "public struct ToolArtifactDocumentPreview",
            "public struct ToolArtifactAppshotPreview",
            "public struct ToolArtifactPDFPreview",
            "public struct ToolArtifactOfficePreview",
            "public struct ToolArtifactArchivePreview",
            "public struct ToolArtifactMediaPreview",
            "public struct ToolArtifactTablePreview",
            "public struct ToolArtifactImagePreview",
            "ToolArtifactMediaPreviewBuilder.mediaPreview"
        ])
        Self.assertSource(artifactValueClassifierText, contains: "enum ToolArtifactValueClassifier")
        Self.assertSource(artifactImagePreviewText, contains: "enum ToolArtifactImagePreviewBuilder")
        Self.assertSource(artifactImagePreviewText, contains: "ToolArtifactImageMetadataReader.dimensionsLabel")
        Self.assertSource(artifactImageMetadataText, containsAll: [
            "enum ToolArtifactImageMetadataReader",
            "maximumHeaderBytes",
            "pngDimensions",
            "gifDimensions",
            "jpegDimensions",
            "icoDimensions",
            "tiffDimensions",
            "bmpDimensions",
            "webpDimensions"
        ])
        Self.assertSource(artifactDocumentPreviewText, containsAll: [
            "enum ToolArtifactDocumentPreviewBuilder",
            "compoundPreviewExtensions",
            ".audio",
            ".video",
            ".archive"
        ])
        Self.assertSource(artifactAppshotPreviewText, containsAll: [
            "enum ToolArtifactAppshotPreviewBuilder",
            "byteLimit",
            "appshotRoot",
            "screenshotURL",
            "replayLabels",
            "ReplayLabelKind",
            "replayLabelLimit"
        ])
        Self.assertSource(toolArtifactSurfaceText, containsAll: [
            "actionLabels: [String]",
            "frameLabels: [String]",
            "eventLabels: [String]"
        ])
        Self.assertSource(artifactDocumentPreviewViewText, containsAll: [
            "appshotReplayTimeline(appshotPreview)",
            "appshotPreview.actionLabels",
            "appshotPreview.frameLabels",
            "appshotPreview.eventLabels"
        ])
        Self.assertSource(artifactPDFPreviewText, containsAll: [
            "enum ToolArtifactPDFPreviewBuilder",
            "byteLimit",
            "parsedPageCount",
            "parsedTitle"
        ])
        Self.assertSource(artifactPDFPagePreviewText, containsAll: [
            "struct QuillCodeArtifactPDFPagePreviewView",
            "PDFPagePreviewRepresentable",
            "PDFView",
            "PDFDocument(url:",
            "displayMode = .singlePage"
        ])
        Self.assertSource(artifactDocumentPreviewViewText, containsAll: [
            "pdfContent(pdfPreview, previewURL:",
            "QuillCodeArtifactPDFPagePreviewView(url: previewURL)",
            "Open \\(artifact.label)"
        ])
        Self.assertSource(artifactOfficePreviewText, containsAll: [
            "enum ToolArtifactOfficePreviewBuilder",
            "ToolArtifactZipCentralDirectoryReader.centralDirectory",
            "worksheetCount",
            "slideCount"
        ])
        Self.assertSource(artifactArchivePreviewText, containsAll: [
            "enum ToolArtifactArchivePreviewBuilder",
            "ToolArtifactZipCentralDirectoryReader.centralDirectory",
            "tarPreview",
            "gzipPreview",
            "tarFileName",
            "tarFileSize",
            "gzipOriginalFileName",
            "includesSingleMemberCounts",
            "uncompressedByteSizeLabel",
            "entryPreviewLabel",
            "topLevelCount"
        ])
        Self.assertSource(artifactMediaPreviewText, containsAll: [
            "enum ToolArtifactMediaPreviewBuilder",
            "id3Metadata",
            "id3TextFrame",
            "fileSizeLimit",
            "id3ReadLimit",
            "id3SyncSafeInteger"
        ])
        Self.assertSource(artifactMediaPlaybackText, containsAll: [
            "struct QuillCodeArtifactMediaPlaybackView",
            "VideoPlayer(player:",
            "AVPlayer(url:",
            "togglePlayback",
            "Pause audio",
            "Play audio"
        ])
        Self.assertSource(artifactDocumentPreviewViewText, containsAll: [
            "mediaContent(mediaPreview, playbackURL:",
            "QuillCodeArtifactMediaPlaybackView(preview: mediaPreview, url: playbackURL)",
            "Open \\(artifact.label)"
        ])
        Self.assertSource(artifactZipCentralDirectoryText, containsAll: [
            "enum ToolArtifactZipCentralDirectoryReader",
            "centralDirectoryHeaderSignature",
            "endOfCentralDirectorySearchLimit",
            "centralDirectoryByteLimit"
        ])
        Self.assertSource(artifactTablePreviewText, containsAll: [
            "enum ToolArtifactTablePreviewBuilder",
            "byteLimit",
            "rowLimit",
            "columnLimit",
            "parseRows"
        ])
        Self.assertSource(artifactByteSizeText, contains: "enum ToolArtifactByteSizeFormatter")
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
