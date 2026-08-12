import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeTools
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

final class ChartToolExecutorTests: XCTestCase {
    func testDefinitionHasValidJSONObjectSchema() throws {
        let data = Data(ToolDefinition.chartRender.parametersJSON.utf8)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "object")
        XCTAssertNotNil((object["properties"] as? [String: Any])?["path"])
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    func testRouterRendersAndReadsBackVerifiedPNG() throws {
        let root = try makeTempDirectory()
        let router = ToolRouter(workspaceRoot: root)

        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(ToolDefinition.chartRender.name))
        let result = router.execute(ToolCall(
            name: ToolDefinition.chartRender.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/regional-revenue.png",
                "title": "Quarterly revenue by region",
                "categories": ["Q1", "Q2", "Q3", "Q4"],
                "series": [
                    "Central": "15100,43000,33700,24400",
                    "East": "27500,18200,46100,36800",
                    "West": "39900,30600,21300,49200",
                ],
                "seriesOrder": ["Central", "East", "West"],
                "stacked": true,
                "xAxisLabel": "Quarter",
                "yAxisLabel": "Revenue ($)",
            ] as [String: Any])
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("Rendered 1200x675 PNG chart"), result.stdout)
        let output = root.appendingPathComponent("outputs/regional-revenue.png")
        let data = try Data(contentsOf: output)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertGreaterThan(data.count, 10_000)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1200)
        XCTAssertEqual(image.height, 675)

        let read = router.execute(ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/regional-revenue.png"])
        ))
        XCTAssertTrue(read.ok, read.error ?? "")
        XCTAssertTrue(read.stdout.contains("PNG image"), read.stdout)
        XCTAssertTrue(read.stdout.contains("1200x675 pixels"), read.stdout)
    }

    func testRejectsMismatchedSeriesAndNonPNGOutput() throws {
        let root = try makeTempDirectory()
        let chart = ChartToolExecutor(workspaceRoot: root)

        let mismatch = chart.render(
            path: "chart.png",
            categories: ["Q1", "Q2"],
            series: ["East": "10"]
        )
        XCTAssertFalse(mismatch.ok)
        XCTAssertTrue(mismatch.error?.contains("expected 2") == true, mismatch.error ?? "")

        let wrongExtension = chart.render(
            path: "chart.txt",
            categories: ["Q1"],
            series: ["East": "10"]
        )
        XCTAssertFalse(wrongExtension.ok)
        XCTAssertTrue(wrongExtension.error?.contains(".png extension") == true, wrongExtension.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("chart.txt").path))
    }

    func testEditGuardRequiresReadBeforeReplacingExistingChart() throws {
        let root = try makeTempDirectory()
        let target = root.appendingPathComponent("chart.png")
        let original = Data("existing chart placeholder".utf8)
        try original.write(to: target)
        let guardState = FileEditSessionGuard()
        let chart = ChartToolExecutor(workspaceRoot: root, editGuard: guardState)

        let blocked = chart.render(
            path: "chart.png",
            categories: ["Q1"],
            series: ["East": "10"]
        )
        XCTAssertFalse(blocked.ok)
        XCTAssertTrue(blocked.error?.contains("not read in this session") == true, blocked.error ?? "")
        XCTAssertEqual(try Data(contentsOf: target), original)

        let files = FileToolExecutor(workspaceRoot: root, editGuard: guardState)
        XCTAssertTrue(files.read(path: "chart.png").ok)
        let allowed = chart.render(
            path: "chart.png",
            categories: ["Q1"],
            series: ["East": "10"]
        )
        XCTAssertTrue(allowed.ok, allowed.error ?? "")
        XCTAssertEqual(Array(try Data(contentsOf: target).prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
    #else
    func testUnavailableRendererIsNotPublished() throws {
        XCTAssertFalse(ChartToolExecutor.isAvailable)
        XCTAssertFalse(ToolRouter.definitions.map(\.name).contains(ToolDefinition.chartRender.name))

        let result = ChartToolExecutor(workspaceRoot: FileManager.default.temporaryDirectory).render(
            path: "chart.png",
            categories: ["Q1"],
            series: ["East": "10"]
        )
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "PNG chart rendering is unavailable on this platform.")
    }
    #endif
}
