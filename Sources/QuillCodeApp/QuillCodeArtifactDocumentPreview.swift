import SwiftUI

struct QuillCodeArtifactDocumentPreview: View {
    var artifact: ToolArtifactState

    @ViewBuilder
    var body: some View {
        if let pdfPreview = artifact.pdfPreview,
           let previewURL = artifactURL {
            pdfContent(pdfPreview, previewURL: previewURL)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel)
        } else if let mediaPreview = artifact.mediaPreview,
           let playbackURL = mediaPreview.playbackURL.flatMap(URL.init(string:)) {
            mediaContent(mediaPreview, playbackURL: playbackURL)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel)
        } else if let url = artifactURL {
            Link(destination: url) {
                content
                    .quillCodeLinkTarget(minWidth: 160, alignment: .leading, radius: 18)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        } else {
            content
                .quillCodeTextButtonTarget(minWidth: 160, alignment: .leading, radius: 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let appshotPreview = artifact.appshotPreview,
           preview?.kind == .appshot {
            appshotContent(appshotPreview)
        } else if let pdfPreview = artifact.pdfPreview,
                  preview?.kind == .pdf {
            metadataContent(
                title: pdfPreview.title ?? artifact.label,
                metadataLines: pdfPreview.metadataLines
            )
        } else if let markdownPreview = artifact.markdownPreview {
            metadataContent(
                title: markdownPreview.title ?? artifact.label,
                metadataLines: markdownPreview.metadataLines
            )
        } else if let officePreview = artifact.officePreview {
            officeContent(officePreview)
        } else if let rtfPreview = artifact.rtfPreview {
            metadataContent(
                title: rtfPreview.title ?? artifact.label,
                metadataLines: rtfPreview.metadataLines
            )
        } else if let htmlPreview = artifact.htmlPreview {
            metadataContent(
                title: htmlPreview.title ?? htmlPreview.heading ?? artifact.label,
                metadataLines: htmlPreview.metadataLines
            )
        } else if let diffPreview = artifact.diffPreview {
            diffContent(diffPreview)
        } else if let tablePreview = artifact.tablePreview {
            tableContent(tablePreview)
        } else if let istanbulPreview = artifact.istanbulPreview {
            istanbulContent(istanbulPreview)
        } else if let harPreview = artifact.harPreview {
            harContent(harPreview)
        } else if let lcovPreview = artifact.lcovPreview {
            lcovContent(lcovPreview)
        } else if let goCoveragePreview = artifact.goCoveragePreview {
            goCoverageContent(goCoveragePreview)
        } else if let sarifPreview = artifact.sarifPreview {
            sarifContent(sarifPreview)
        } else if let jsonLinesPreview = artifact.jsonLinesPreview {
            jsonLinesContent(jsonLinesPreview)
        } else if let tomlPreview = artifact.tomlPreview {
            tomlContent(tomlPreview)
        } else if let iniPreview = artifact.iniPreview {
            iniContent(iniPreview)
        } else if let dotenvPreview = artifact.dotenvPreview {
            dotenvContent(dotenvPreview)
        } else if let yamlPreview = artifact.yamlPreview {
            yamlContent(yamlPreview)
        } else if let junitPreview = artifact.junitPreview {
            junitContent(junitPreview)
        } else if let coberturaPreview = artifact.coberturaPreview {
            coberturaContent(coberturaPreview)
        } else if let cloverPreview = artifact.cloverPreview {
            cloverContent(cloverPreview)
        } else if let jaCoCoPreview = artifact.jaCoCoPreview {
            jaCoCoContent(jaCoCoPreview)
        } else if let xmlPreview = artifact.xmlPreview {
            xmlContent(xmlPreview)
        } else if let propertyListPreview = artifact.propertyListPreview {
            propertyListContent(propertyListPreview)
        } else if let sqlitePreview = artifact.sqlitePreview {
            metadataContent(
                title: artifact.label,
                metadataLines: sqlitePreview.metadataLines
            )
        } else if let webAssemblyPreview = artifact.webAssemblyPreview {
            metadataContent(
                title: artifact.label,
                metadataLines: webAssemblyPreview.metadataLines
            )
        } else if let fontPreview = artifact.fontPreview {
            metadataContent(
                title: artifact.label,
                metadataLines: fontPreview.metadataLines
            )
        } else if let executablePreview = artifact.executablePreview {
            metadataContent(
                title: artifact.label,
                metadataLines: executablePreview.metadataLines
            )
        } else if let notebookPreview = artifact.notebookPreview {
            metadataContent(
                title: artifact.label,
                metadataLines: notebookPreview.metadataLines
            )
        } else if let jsonPreview = artifact.jsonPreview {
            jsonContent(jsonPreview)
        } else if let archivePreview = artifact.archivePreview {
            archiveContent(archivePreview)
        } else if let mediaPreview = artifact.mediaPreview {
            metadataContent(
                title: mediaPreview.title ?? artifact.label,
                metadataLines: mediaPreview.metadataLines
            )
        } else {
            genericContent
        }
    }

    private var genericContent: some View {
        previewSurface(minHeight: 74) {
            header(
                thumbnail: { iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "doc") },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
        }
    }

    private func metadataContent(title: String, metadataLines: [String]) -> some View {
        previewSurface(minHeight: 92) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "doc.richtext")
                },
                title: title,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(metadataLines)
        }
    }

    private func appshotContent(_ appshotPreview: ToolArtifactAppshotPreview) -> some View {
        previewSurface(minHeight: 96) {
            header(
                thumbnail: { appshotThumbnail(appshotPreview) },
                title: appshotPreview.title ?? artifact.label,
                subtitle: appshotPreview.summary ?? preview?.detail ?? artifact.detail,
                subtitleLineLimit: 2
            )
            appshotMetadata(appshotPreview.metadataLines)
            appshotReplayTimeline(appshotPreview)
        }
    }

    private func tableContent(_ tablePreview: ToolArtifactTablePreview) -> some View {
        previewSurface(minHeight: 116) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "tablecells")
                },
                title: artifact.label,
                subtitle: tablePreview.metadataLines.joined(separator: " · "),
                subtitleLineLimit: 2
            )
            tableGrid(tablePreview)
        }
    }

    private func jsonContent(_ jsonPreview: ToolArtifactJSONPreview) -> some View {
        previewSurface(minHeight: jsonPreview.keyPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "curlybraces")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(jsonPreview.metadataLines)
            artifactContentList(title: "Top keys", labels: jsonPreview.keyPreviewLabels)
        }
    }

    private func harContent(_ harPreview: ToolArtifactHARPreview) -> some View {
        previewSurface(minHeight: harPreview.hostPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "network")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(harPreview.metadataLines)
            artifactContentList(title: "Hosts", labels: harPreview.hostPreviewLabels)
        }
    }

    private func istanbulContent(_ istanbulPreview: ToolArtifactIstanbulPreview) -> some View {
        previewSurface(minHeight: istanbulPreview.filePreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "chart.bar.xaxis")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(istanbulPreview.metadataLines)
            artifactContentList(title: "Source files", labels: istanbulPreview.filePreviewLabels)
        }
    }

    private func lcovContent(_ lcovPreview: ToolArtifactLCOVPreview) -> some View {
        previewSurface(minHeight: lcovPreview.sourcePreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "chart.bar.doc.horizontal")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(lcovPreview.metadataLines)
            artifactContentList(title: "Source files", labels: lcovPreview.sourcePreviewLabels)
        }
    }

    private func goCoverageContent(_ goCoveragePreview: ToolArtifactGoCoveragePreview) -> some View {
        previewSurface(minHeight: goCoveragePreview.sourcePreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "chart.bar.doc.horizontal")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(goCoveragePreview.metadataLines)
            artifactContentList(title: "Source files", labels: goCoveragePreview.sourcePreviewLabels)
        }
    }

    private func sarifContent(_ sarifPreview: ToolArtifactSARIFPreview) -> some View {
        previewSurface(minHeight: sarifPreview.rulePreviewLabels.isEmpty ? 92 : 142) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "checklist.checked")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(sarifPreview.metadataLines)
            artifactContentList(title: "Tools", labels: sarifPreview.toolPreviewLabels)
            artifactContentList(title: "Rules", labels: sarifPreview.rulePreviewLabels)
        }
    }

    private func diffContent(_ diffPreview: ToolArtifactDiffPreview) -> some View {
        previewSurface(minHeight: diffPreview.changedFileLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "plus.forwardslash.minus")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(diffPreview.metadataLines)
            artifactContentList(title: "Changed files", labels: diffPreview.changedFileLabels)
        }
    }

    private func jsonLinesContent(_ jsonLinesPreview: ToolArtifactJSONLinesPreview) -> some View {
        previewSurface(minHeight: jsonLinesPreview.keyPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "curlybraces")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(jsonLinesPreview.metadataLines)
            artifactContentList(title: "Observed keys", labels: jsonLinesPreview.keyPreviewLabels)
        }
    }

    private func tomlContent(_ tomlPreview: ToolArtifactTOMLPreview) -> some View {
        previewSurface(minHeight: tomlPreview.keyPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "curlybraces")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(tomlPreview.metadataLines)
            artifactContentList(title: "Top-level keys", labels: tomlPreview.keyPreviewLabels)
        }
    }

    private func iniContent(_ iniPreview: ToolArtifactINIPreview) -> some View {
        previewSurface(minHeight: iniPreview.sectionPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "gearshape")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(iniPreview.metadataLines)
            artifactContentList(title: "Sections", labels: iniPreview.sectionPreviewLabels)
        }
    }

    private func dotenvContent(_ dotenvPreview: ToolArtifactDotenvPreview) -> some View {
        previewSurface(minHeight: dotenvPreview.keyPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "key")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(dotenvPreview.metadataLines)
            artifactContentList(title: "Variable names", labels: dotenvPreview.keyPreviewLabels)
        }
    }

    private func yamlContent(_ yamlPreview: ToolArtifactYAMLPreview) -> some View {
        previewSurface(minHeight: yamlPreview.keyPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "curlybraces")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(yamlPreview.metadataLines)
            artifactContentList(title: "Top-level keys", labels: yamlPreview.keyPreviewLabels)
        }
    }

    private func xmlContent(_ xmlPreview: ToolArtifactXMLPreview) -> some View {
        previewSurface(minHeight: xmlPreview.childPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "chevron.left.forwardslash.chevron.right")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(xmlPreview.metadataLines)
            artifactContentList(title: "Root children", labels: xmlPreview.childPreviewLabels)
        }
    }

    private func junitContent(_ junitPreview: ToolArtifactJUnitPreview) -> some View {
        previewSurface(minHeight: junitPreview.failurePreviewLabels.isEmpty ? 92 : 142) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "checkmark.seal")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(junitPreview.metadataLines)
            artifactContentList(title: "Suites", labels: junitPreview.suitePreviewLabels)
            artifactContentList(title: "Failing tests", labels: junitPreview.failurePreviewLabels)
        }
    }

    private func coberturaContent(_ coberturaPreview: ToolArtifactCoberturaPreview) -> some View {
        previewSurface(minHeight: coberturaPreview.classPreviewLabels.isEmpty ? 92 : 154) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "chart.bar.doc.horizontal")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(coberturaPreview.metadataLines)
            artifactContentList(title: "Packages", labels: coberturaPreview.packagePreviewLabels)
            artifactContentList(title: "Classes", labels: coberturaPreview.classPreviewLabels)
        }
    }

    private func cloverContent(_ cloverPreview: ToolArtifactCloverPreview) -> some View {
        previewSurface(minHeight: cloverPreview.filePreviewLabels.isEmpty ? 92 : 154) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "chart.line.uptrend.xyaxis")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(cloverPreview.metadataLines)
            artifactContentList(title: "Projects", labels: cloverPreview.projectPreviewLabels)
            artifactContentList(title: "Files", labels: cloverPreview.filePreviewLabels)
        }
    }

    private func jaCoCoContent(_ jaCoCoPreview: ToolArtifactJaCoCoPreview) -> some View {
        previewSurface(minHeight: jaCoCoPreview.sourceFilePreviewLabels.isEmpty ? 92 : 154) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "chart.bar.xaxis")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(jaCoCoPreview.metadataLines)
            artifactContentList(title: "Packages", labels: jaCoCoPreview.packagePreviewLabels)
            artifactContentList(title: "Source files", labels: jaCoCoPreview.sourceFilePreviewLabels)
        }
    }

    private func propertyListContent(_ propertyListPreview: ToolArtifactPropertyListPreview) -> some View {
        previewSurface(minHeight: propertyListPreview.keyPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "curlybraces")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(propertyListPreview.metadataLines)
            artifactContentList(title: "Top-level keys", labels: propertyListPreview.keyPreviewLabels)
        }
    }

    private func officeContent(_ officePreview: ToolArtifactOfficePreview) -> some View {
        previewSurface(minHeight: officePreview.contentPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "doc.text")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(officePreview.metadataLines)
            officeContentList(officePreview.contentPreviewLabels)
        }
    }

    private func archiveContent(_ archivePreview: ToolArtifactArchivePreview) -> some View {
        previewSurface(minHeight: archivePreview.entryPreviewLabels.isEmpty ? 92 : 126) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "archivebox")
                },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(archivePreview.metadataLines)
            artifactContentList(title: "Contents", labels: archivePreview.entryPreviewLabels)
        }
    }

    private func pdfContent(_ pdfPreview: ToolArtifactPDFPreview, previewURL: URL) -> some View {
        previewSurface(minHeight: 252) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "doc.richtext")
                },
                title: pdfPreview.title ?? artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            QuillCodeArtifactPDFPagePreviewView(url: previewURL)
            HStack(alignment: .center, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                metadataPills(pdfPreview.metadataLines)
                Spacer(minLength: 4)
                Link(destination: previewURL) {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeLinkTarget(minWidth: 74, alignment: .center, radius: 12)
                .accessibilityLabel("Open \(artifact.label)")
            }
        }
    }

    private func mediaContent(_ mediaPreview: ToolArtifactMediaPreview, playbackURL: URL) -> some View {
        previewSurface(minHeight: mediaPreview.kind == .video ? 230 : 146) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "play.rectangle")
                },
                title: mediaPreview.title ?? artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            QuillCodeArtifactMediaPlaybackView(preview: mediaPreview, url: playbackURL)
            HStack(alignment: .center, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                metadataPills(mediaPreview.metadataLines)
                Spacer(minLength: 4)
                Link(destination: playbackURL) {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeLinkTarget(minWidth: 74, alignment: .center, radius: 12)
                .accessibilityLabel("Open \(artifact.label)")
            }
        }
    }

    private func previewSurface<Content: View>(
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .quillCodeSurface(
            fill: Color.white.opacity(0.05),
            radius: 18,
            stroke: Color.white.opacity(0.08),
            shadow: false
        )
    }

    private func header<Thumbnail: View>(
        @ViewBuilder thumbnail: () -> Thumbnail,
        title: String,
        subtitle: String,
        subtitleLineLimit: Int = 1
    ) -> some View {
        HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
            thumbnail()
            VStack(alignment: .leading, spacing: 4) {
                Text(typeLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .lineLimit(1)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(subtitleLineLimit)
            }
            Spacer(minLength: 4)
            externalLinkIcon
        }
    }

    @ViewBuilder
    private var externalLinkIcon: some View {
        if artifactURL != nil {
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .accessibilityHidden(true)
        }
    }

    private func iconThumbnail(width: CGFloat, height: CGFloat, systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(QuillCodePalette.blue.opacity(0.14))
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.blue)
                .accessibilityHidden(true)
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func appshotThumbnail(_ appshotPreview: ToolArtifactAppshotPreview) -> some View {
        if let screenshotURL = appshotPreview.screenshotURL.flatMap(URL.init(string:)) {
            AsyncImage(url: screenshotURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    appshotFallbackThumbnail
                @unknown default:
                    appshotFallbackThumbnail
                }
            }
            .frame(width: 92, height: 58)
            .clipped()
            .background(Color.black.opacity(0.22))
            .quillCodeImageOutline(radius: 10)
        } else {
            appshotFallbackThumbnail
        }
    }

    private var appshotFallbackThumbnail: some View {
        iconThumbnail(width: 92, height: 58, systemImage: preview?.systemImage ?? "camera.viewfinder")
    }

    @ViewBuilder
    private func metadataPills(_ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func appshotMetadata(_ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func appshotReplayTimeline(_ appshotPreview: ToolArtifactAppshotPreview) -> some View {
        let groups = [
            ("Actions", appshotPreview.actionLabels),
            ("Frames", appshotPreview.frameLabels),
            ("Events", appshotPreview.eventLabels)
        ].filter { !$0.1.isEmpty }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.0) { title, labels in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.muted)
                        ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(QuillCodePalette.blue)
                                    .frame(width: 18, alignment: .trailing)
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(QuillCodePalette.text)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func officeContentList(_ labels: [String]) -> some View {
        artifactContentList(title: "Contents", labels: labels)
    }

    @ViewBuilder
    private func artifactContentList(title: String, labels: [String]) -> some View {
        if !labels.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                ForEach(labels, id: \.self) { label in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(QuillCodePalette.blue)
                            .frame(width: 5, height: 5)
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.text)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func tableGrid(_ tablePreview: ToolArtifactTablePreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableRow(tablePreview.headers, isHeader: true)
            ForEach(Array(tablePreview.rows.enumerated()), id: \.offset) { _, row in
                tableRow(row, isHeader: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func tableRow(_ row: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                Text(cell.isEmpty ? " " : cell)
                    .font(.caption2.weight(isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? QuillCodePalette.text : QuillCodePalette.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 1)
                    }
            }
        }
        .background(isHeader ? Color.white.opacity(0.06) : Color.white.opacity(0.025))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    private var preview: ToolArtifactDocumentPreview? {
        artifact.documentPreview
    }

    private var typeLine: String {
        guard let preview else { return "Document" }
        return "\(preview.typeLabel) · \(preview.extensionLabel)"
    }

    private var artifactURL: URL? {
        artifact.href.flatMap(URL.init(string:))
    }

    private var accessibilityLabel: String {
        "\(typeLine) preview \(artifact.label)"
    }
}
