extension TerminalScreenBuffer {
    mutating func applySGR(_ rawParams: String) {
        let fields = rawParams.isEmpty
            ? [Substring("0")]
            : rawParams.split(separator: ";", omittingEmptySubsequences: false)
        var index = 0
        while index < fields.count {
            let field = fields[index]
            if field.contains(":") {
                applyColonSGR(field)
                index += 1
                continue
            }

            let code = boundedColorComponent(field) ?? 0
            switch code {
            case 0:
                currentStyle = .plain
            case 1:
                currentStyle.isBold = true
            case 2:
                currentStyle.isFaint = true
            case 3:
                currentStyle.isItalic = true
            case 4, 21:
                currentStyle.isUnderlined = true
            case 7:
                currentStyle.isInverse = true
            case 8:
                currentStyle.isConcealed = true
            case 9:
                currentStyle.isStrikethrough = true
            case 22:
                currentStyle.isBold = false
                currentStyle.isFaint = false
            case 23:
                currentStyle.isItalic = false
            case 24:
                currentStyle.isUnderlined = false
            case 27:
                currentStyle.isInverse = false
            case 28:
                currentStyle.isConcealed = false
            case 29:
                currentStyle.isStrikethrough = false
            case 30...37:
                currentStyle.foreground = standardColor(code - 30, bright: false)
            case 38:
                if let parsed = extendedColor(in: fields, after: index) {
                    currentStyle.foreground = parsed.color
                    index += parsed.consumedFields
                }
            case 39:
                currentStyle.foreground = nil
            case 40...47:
                currentStyle.background = standardColor(code - 40, bright: false)
            case 48:
                if let parsed = extendedColor(in: fields, after: index) {
                    currentStyle.background = parsed.color
                    index += parsed.consumedFields
                }
            case 49:
                currentStyle.background = nil
            case 90...97:
                currentStyle.foreground = standardColor(code - 90, bright: true)
            case 100...107:
                currentStyle.background = standardColor(code - 100, bright: true)
            default:
                break
            }
            index += 1
        }
    }

    private mutating func applyColonSGR(_ field: Substring) {
        let components = field.split(separator: ":", omittingEmptySubsequences: false)
        guard let code = components.first.flatMap(boundedColorComponent) else { return }
        if code == 4 {
            currentStyle.isUnderlined = components.dropFirst().first != "0"
            return
        }
        guard code == 38 || code == 48,
              let color = colonExtendedColor(components.dropFirst()) else {
            return
        }
        if code == 38 {
            currentStyle.foreground = color
        } else {
            currentStyle.background = color
        }
    }

    private func extendedColor(
        in fields: [Substring],
        after index: Int
    ) -> (color: TerminalTextColor, consumedFields: Int)? {
        guard index + 1 < fields.count,
              let mode = boundedColorComponent(fields[index + 1]) else {
            return nil
        }
        if mode == 5,
           index + 2 < fields.count,
           let paletteIndex = boundedColorComponent(fields[index + 2]) {
            return (.indexed(UInt8(paletteIndex)), 2)
        }
        if mode == 2,
           index + 4 < fields.count,
           let red = boundedColorComponent(fields[index + 2]),
           let green = boundedColorComponent(fields[index + 3]),
           let blue = boundedColorComponent(fields[index + 4]) {
            return (
                .rgb(TerminalRGBColor(red: UInt8(red), green: UInt8(green), blue: UInt8(blue))),
                4
            )
        }
        return nil
    }

    private func colonExtendedColor(_ fields: ArraySlice<Substring>) -> TerminalTextColor? {
        guard let modeField = fields.first,
              let mode = boundedColorComponent(modeField) else {
            return nil
        }
        let values = fields.dropFirst().compactMap(boundedColorComponent)
        if mode == 5, let paletteIndex = values.first {
            return .indexed(UInt8(paletteIndex))
        }
        if mode == 2, values.count >= 3 {
            let rgb = values.suffix(3)
            return .rgb(TerminalRGBColor(
                red: UInt8(rgb[rgb.startIndex]),
                green: UInt8(rgb[rgb.index(after: rgb.startIndex)]),
                blue: UInt8(rgb[rgb.index(rgb.startIndex, offsetBy: 2)])
            ))
        }
        return nil
    }

    private func boundedColorComponent(_ field: Substring) -> Int? {
        guard let value = Int(field) else { return nil }
        return max(0, min(value, 255))
    }

    private func standardColor(_ offset: Int, bright: Bool) -> TerminalTextColor {
        switch (bright, offset) {
        case (false, 0): return .black
        case (false, 1): return .red
        case (false, 2): return .green
        case (false, 3): return .yellow
        case (false, 4): return .blue
        case (false, 5): return .magenta
        case (false, 6): return .cyan
        case (false, _): return .white
        case (true, 0): return .brightBlack
        case (true, 1): return .brightRed
        case (true, 2): return .brightGreen
        case (true, 3): return .brightYellow
        case (true, 4): return .brightBlue
        case (true, 5): return .brightMagenta
        case (true, 6): return .brightCyan
        case (true, _): return .brightWhite
        }
    }
}
