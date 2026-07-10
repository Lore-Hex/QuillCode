import SwiftUI
import QuillCodeTools

enum QuillCodeTerminalAttributedText {
    static func render(
        runs: [TerminalTextRun]?,
        fallback: String,
        defaultForeground: Color
    ) -> AttributedString {
        let source = runs ?? (fallback.isEmpty ? [] : [TerminalTextRun(text: fallback)])
        var output = AttributedString()
        for run in source {
            var segment = AttributedString(run.text)
            let colors = resolvedColors(for: run.style, defaultForeground: defaultForeground)
            segment.font = font(for: run.style)
            segment.foregroundColor = run.style.isConcealed ? .clear : colors.foreground
            if let background = colors.background {
                segment.backgroundColor = background
            }
            if run.style.isUnderlined {
                segment.underlineStyle = .single
            }
            if run.style.isStrikethrough {
                segment.strikethroughStyle = .single
            }
            output.append(segment)
        }
        return output
    }

    private static func font(for style: TerminalTextStyle) -> Font {
        var font = Font.system(
            .caption,
            design: .monospaced,
            weight: style.isBold ? .bold : .regular
        )
        if style.isItalic {
            font = font.italic()
        }
        return font
    }

    private static func resolvedColors(
        for style: TerminalTextStyle,
        defaultForeground: Color
    ) -> (foreground: Color, background: Color?) {
        var foreground = style.foreground.map(color) ?? defaultForeground
        var background = style.background.map(color)
        if style.isInverse {
            let inverseBackground = foreground
            foreground = background ?? QuillCodePalette.background
            background = inverseBackground
        }
        if style.isFaint {
            foreground = foreground.opacity(0.65)
        }
        return (foreground, background)
    }

    private static func color(_ terminalColor: TerminalTextColor) -> Color {
        let rgb = terminalColor.resolvedRGB
        return Color(
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }
}
