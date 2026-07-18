import PDFKit
import SwiftUI

struct QuillCodeArtifactPDFPagePreviewView: View {
    let url: URL

    var body: some View {
        PDFPagePreviewRepresentable(url: url)
            .frame(maxWidth: .infinity, minHeight: 142, maxHeight: 176)
            .background(Color.black.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .accessibilityLabel("PDF page preview")
    }
}

private struct PDFPagePreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        if let firstPage = view.document?.page(at: 0) {
            view.go(to: firstPage)
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
        if let firstPage = view.document?.page(at: 0) {
            view.go(to: firstPage)
        }
    }
}
