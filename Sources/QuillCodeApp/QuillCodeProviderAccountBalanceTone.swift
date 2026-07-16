import SwiftUI

extension ProviderAccountBalanceTone {
    var quillCodeTint: Color {
        switch self {
        case .normal: QuillCodePalette.green
        case .updating: QuillCodePalette.blue
        case .warning: QuillCodePalette.yellow
        }
    }
}
