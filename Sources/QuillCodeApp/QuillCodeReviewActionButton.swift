import SwiftUI

struct QuillCodeReviewActionButton: View {
    var action: WorkspaceReviewActionSurface
    var path: String
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void

    var body: some View {
        Button {
            onReviewAction(action)
        } label: {
            Label(action.kind.title, systemImage: action.kind.systemImage)
                .labelStyle(.iconOnly)
                .quillCodeIconButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("\(action.kind.title) \(path)")
        .foregroundStyle(isDestructiveRestore ? QuillCodePalette.yellow : QuillCodePalette.blue)
    }

    private var isDestructiveRestore: Bool {
        action.kind == .restore || action.kind == .restoreHunk
    }
}
