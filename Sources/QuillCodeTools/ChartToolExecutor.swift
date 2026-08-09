import CoreGraphics
import CoreText
import Foundation
import ImageIO
import QuillCodeCore
import UniformTypeIdentifiers

public struct ChartToolExecutor: @unchecked Sendable {
    public var workspaceRoot: URL
    public let accessScope: HostToolAccessScope
    public var editGuard: FileEditSessionGuard?

    private var pathResolver: FileWorkspacePathResolver {
        FileWorkspacePathResolver(workspaceRoot: workspaceRoot, accessScope: accessScope)
    }

    public init(
        workspaceRoot: URL,
        accessScope: HostToolAccessScope = .workspaceOnly,
        editGuard: FileEditSessionGuard? = nil
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.accessScope = accessScope
        self.editGuard = editGuard
    }

    public func render(
        path: String,
        title: String? = nil,
        categories: [String],
        series: [String: String],
        seriesOrder: [String]? = nil,
        stacked: Bool = true,
        colors: [String: String]? = nil,
        xAxisLabel: String? = nil,
        yAxisLabel: String? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) -> ToolResult {
        do {
            let specification = try ChartSpecification(
                title: title,
                categories: categories,
                serializedSeries: series,
                seriesOrder: seriesOrder,
                stacked: stacked,
                serializedColors: colors,
                xAxisLabel: xAxisLabel,
                yAxisLabel: yAxisLabel,
                width: width ?? 1200,
                height: height ?? 675
            )
            let outputURL = try pathResolver.resolve(path)
            guard outputURL.pathExtension.caseInsensitiveCompare("png") == .orderedSame else {
                throw ChartToolError.invalidOutput("Chart output must use a .png extension.")
            }
            let png = try ChartPNGRenderer.render(specification)
            let operation = {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: outputURL, options: .atomic)
            }
            if let editGuard {
                try editGuard.withExclusiveAccess(to: [outputURL]) {
                    if FileManager.default.fileExists(atPath: outputURL.path), !editGuard.hasRead(outputURL) {
                        throw FileEditGuardError.writeWithoutRead(path)
                    }
                    try operation()
                    editGuard.markWritten(outputURL)
                }
            } else {
                try operation()
            }
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  properties[kCGImagePropertyPixelWidth] as? Int == specification.width,
                  properties[kCGImagePropertyPixelHeight] as? Int == specification.height
            else {
                try? FileManager.default.removeItem(at: outputURL)
                throw ChartToolError.encodingFailed
            }
            return ToolResult(
                ok: true,
                stdout: "Rendered \(specification.width)x\(specification.height) PNG chart to "
                    + "\(pathResolver.relativePath(for: outputURL)) with "
                    + "\(specification.series.count) series and \(specification.categories.count) categories.\n",
                artifacts: [outputURL.path]
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }
}

private struct ChartSpecification {
    struct Series {
        var name: String
        var values: [Double]
        var color: CGColor
    }

    var title: String?
    var categories: [String]
    var series: [Series]
    var stacked: Bool
    var xAxisLabel: String?
    var yAxisLabel: String?
    var width: Int
    var height: Int

    init(
        title: String?,
        categories: [String],
        serializedSeries: [String: String],
        seriesOrder: [String]?,
        stacked: Bool,
        serializedColors: [String: String]?,
        xAxisLabel: String?,
        yAxisLabel: String?,
        width: Int,
        height: Int
    ) throws {
        guard (800...2400).contains(width), (450...1600).contains(height) else {
            throw ChartToolError.invalidData("Chart dimensions must be 800-2400 by 450-1600 pixels.")
        }
        let normalizedCategories = categories.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard (1...24).contains(normalizedCategories.count),
              normalizedCategories.allSatisfy({ !$0.isEmpty }) else {
            throw ChartToolError.invalidData("Provide 1-24 non-empty category labels.")
        }
        guard !serializedSeries.isEmpty, serializedSeries.count <= 12 else {
            throw ChartToolError.invalidData("Provide 1-12 chart series.")
        }
        let order = try Self.resolvedOrder(seriesOrder, available: Set(serializedSeries.keys))
        let palette = Self.palette
        var parsed: [Series] = []
        for (index, name) in order.enumerated() {
            guard let serialized = serializedSeries[name] else { continue }
            let values = try Self.parseValues(serialized, seriesName: name)
            guard values.count == normalizedCategories.count else {
                throw ChartToolError.invalidData(
                    "Series \(name) has \(values.count) values; expected \(normalizedCategories.count)."
                )
            }
            guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                throw ChartToolError.invalidData("Series \(name) contains a negative or non-finite value.")
            }
            let color = serializedColors?[name].flatMap(Self.color(hex:))
                ?? palette[index % palette.count]
            parsed.append(Series(name: name, values: values, color: color))
        }
        guard parsed.contains(where: { $0.values.contains(where: { $0 > 0 }) }) else {
            throw ChartToolError.invalidData("At least one chart value must be greater than zero.")
        }
        self.title = Self.nonEmpty(title)
        self.categories = normalizedCategories
        self.series = parsed
        self.stacked = stacked
        self.xAxisLabel = Self.nonEmpty(xAxisLabel)
        self.yAxisLabel = Self.nonEmpty(yAxisLabel)
        self.width = width
        self.height = height
    }

    private static func resolvedOrder(_ requested: [String]?, available: Set<String>) throws -> [String] {
        guard let requested, !requested.isEmpty else { return available.sorted() }
        guard Set(requested) == available, requested.count == available.count else {
            throw ChartToolError.invalidData("seriesOrder must contain every series label exactly once.")
        }
        return requested
    }

    private static func parseValues(_ serialized: String, seriesName: String) throws -> [Double] {
        let pieces = serialized.split(separator: ",", omittingEmptySubsequences: false)
        let values = pieces.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == pieces.count else {
            throw ChartToolError.invalidData("Series \(seriesName) must contain comma-separated numbers.")
        }
        return values
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func color(hex: String) -> CGColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        return CGColor(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }

    private static let palette: [CGColor] = [
        CGColor(red: 0.10, green: 0.42, blue: 0.62, alpha: 1),
        CGColor(red: 0.18, green: 0.61, blue: 0.43, alpha: 1),
        CGColor(red: 0.91, green: 0.55, blue: 0.17, alpha: 1),
        CGColor(red: 0.71, green: 0.29, blue: 0.33, alpha: 1),
        CGColor(red: 0.38, green: 0.32, blue: 0.66, alpha: 1),
        CGColor(red: 0.15, green: 0.62, blue: 0.67, alpha: 1),
        CGColor(red: 0.63, green: 0.45, blue: 0.22, alpha: 1),
        CGColor(red: 0.44, green: 0.48, blue: 0.52, alpha: 1),
    ]
}

private enum ChartPNGRenderer {
    static func render(_ specification: ChartSpecification) throws -> Data {
        let width = specification.width
        let height = specification.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ChartToolError.renderingFailed
        }
        context.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let left: CGFloat = 104
        let right: CGFloat = 42
        let bottom: CGFloat = specification.xAxisLabel == nil ? 82 : 104
        let top: CGFloat = specification.title == nil ? 88 : 118
        let plot = CGRect(
            x: left,
            y: bottom,
            width: CGFloat(width) - left - right,
            height: CGFloat(height) - bottom - top
        )
        let maxValue = maximumValue(specification)
        let axisMax = pleasantAxisMaximum(maxValue)

        drawTitleAndLegend(specification, context: context, plot: plot)
        drawAxes(specification, context: context, plot: plot, axisMax: axisMax)
        drawBars(specification, context: context, plot: plot, axisMax: axisMax)

        guard let image = context.makeImage() else { throw ChartToolError.renderingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ChartToolError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGTitle: specification.title ?? "Chart"]
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length >= 33 else {
            throw ChartToolError.encodingFailed
        }
        return data as Data
    }

    private static func maximumValue(_ specification: ChartSpecification) -> Double {
        if specification.stacked {
            return specification.categories.indices.map { categoryIndex in
                specification.series.reduce(0) { $0 + $1.values[categoryIndex] }
            }.max() ?? 1
        }
        return specification.series.flatMap(\.values).max() ?? 1
    }

    private static func pleasantAxisMaximum(_ value: Double) -> Double {
        let padded = max(1, value * 1.08)
        let magnitude = pow(10, floor(log10(padded)))
        let normalized = padded / magnitude
        let step: Double
        switch normalized {
        case ...1: step = 1
        case ...2: step = 2
        case ...5: step = 5
        default: step = 10
        }
        return step * magnitude
    }

    private static func drawTitleAndLegend(
        _ specification: ChartSpecification,
        context: CGContext,
        plot: CGRect
    ) {
        if let title = specification.title {
            drawText(
                title,
                context: context,
                point: CGPoint(x: plot.minX, y: CGFloat(specification.height) - 52),
                fontSize: 26,
                bold: true,
                color: CGColor(gray: 0.12, alpha: 1)
            )
        }
        var x = plot.minX
        let y = plot.maxY + 28
        for series in specification.series {
            context.setFillColor(series.color)
            context.fill(CGRect(x: x, y: y - 3, width: 16, height: 10))
            drawText(
                series.name,
                context: context,
                point: CGPoint(x: x + 23, y: y - 5),
                fontSize: 13,
                color: CGColor(gray: 0.22, alpha: 1)
            )
            x += 31 + textWidth(series.name, fontSize: 13)
        }
    }

    private static func drawAxes(
        _ specification: ChartSpecification,
        context: CGContext,
        plot: CGRect,
        axisMax: Double
    ) {
        for tick in 0...5 {
            let fraction = CGFloat(tick) / 5
            let y = plot.minY + plot.height * fraction
            context.setStrokeColor(CGColor(gray: tick == 0 ? 0.45 : 0.86, alpha: 1))
            context.setLineWidth(tick == 0 ? 1.2 : 0.7)
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.strokePath()
            let label = formatted(axisMax * Double(tick) / 5)
            let labelWidth = textWidth(label, fontSize: 12)
            drawText(
                label,
                context: context,
                point: CGPoint(x: plot.minX - labelWidth - 12, y: y - 4),
                fontSize: 12,
                color: CGColor(gray: 0.34, alpha: 1)
            )
        }
        if let label = specification.yAxisLabel {
            drawText(
                label,
                context: context,
                point: CGPoint(x: plot.minX, y: plot.maxY + 7),
                fontSize: 12,
                bold: true,
                color: CGColor(gray: 0.30, alpha: 1)
            )
        }
        if let label = specification.xAxisLabel {
            let labelWidth = textWidth(label, fontSize: 13, bold: true)
            drawText(
                label,
                context: context,
                point: CGPoint(x: plot.midX - labelWidth / 2, y: 30),
                fontSize: 13,
                bold: true,
                color: CGColor(gray: 0.30, alpha: 1)
            )
        }
    }

    private static func drawBars(
        _ specification: ChartSpecification,
        context: CGContext,
        plot: CGRect,
        axisMax: Double
    ) {
        let slot = plot.width / CGFloat(specification.categories.count)
        let usableWidth = slot * 0.68
        for categoryIndex in specification.categories.indices {
            let slotX = plot.minX + slot * CGFloat(categoryIndex)
            let label = specification.categories[categoryIndex]
            let labelWidth = textWidth(label, fontSize: 12)
            drawText(
                label,
                context: context,
                point: CGPoint(x: slotX + (slot - labelWidth) / 2, y: plot.minY - 27),
                fontSize: 12,
                color: CGColor(gray: 0.24, alpha: 1)
            )
            if specification.stacked {
                var base = plot.minY
                for series in specification.series {
                    let barHeight = plot.height * CGFloat(series.values[categoryIndex] / axisMax)
                    context.setFillColor(series.color)
                    context.fill(CGRect(
                        x: slotX + (slot - usableWidth) / 2,
                        y: base,
                        width: usableWidth,
                        height: barHeight
                    ))
                    base += barHeight
                }
            } else {
                let barWidth = usableWidth / CGFloat(specification.series.count)
                for (seriesIndex, series) in specification.series.enumerated() {
                    let barHeight = plot.height * CGFloat(series.values[categoryIndex] / axisMax)
                    context.setFillColor(series.color)
                    context.fill(CGRect(
                        x: slotX + (slot - usableWidth) / 2 + CGFloat(seriesIndex) * barWidth,
                        y: plot.minY,
                        width: max(1, barWidth - 2),
                        height: barHeight
                    ))
                }
            }
        }
    }

    private static func drawText(
        _ text: String,
        context: CGContext,
        point: CGPoint,
        fontSize: CGFloat,
        bold: Bool = false,
        color: CGColor
    ) {
        let font = CTFontCreateWithName(
            (bold ? "Helvetica-Bold" : "Helvetica") as CFString,
            fontSize,
            nil
        )
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func textWidth(_ text: String, fontSize: CGFloat, bold: Bool = false) -> CGFloat {
        let font = CTFontCreateWithName(
            (bold ? "Helvetica-Bold" : "Helvetica") as CFString,
            fontSize,
            nil
        )
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        return CGFloat(CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(attributed),
            nil,
            nil,
            nil
        ))
    }

    private static func formatted(_ value: Double) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
        if absolute >= 1_000 {
            return String(format: "%.1fK", value / 1_000).replacingOccurrences(of: ".0K", with: "K")
        }
        return String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
    }
}

private enum ChartToolError: Error, CustomStringConvertible {
    case encodingFailed
    case invalidData(String)
    case invalidOutput(String)
    case renderingFailed

    var description: String {
        switch self {
        case .encodingFailed: "Could not encode or verify the PNG chart."
        case .invalidData(let message), .invalidOutput(let message): message
        case .renderingFailed: "Could not create the chart bitmap context."
        }
    }
}
