import AppKit
import Foundation
import QuillCodeApp
import SwiftUI

@MainActor
enum QuillCodeDesktopWindowSmokeRunner {
    private static var smokeWindow: NSWindow?
    private static var smokeController: QuillCodeDesktopController?

    static func runAndExit(_ request: QuillCodeDesktopWindowSmokeRequest) async {
        do {
            let report = try await run(request)
            let json = try report.prettyJSON()
            if let reportPath = request.reportPath, !reportPath.isEmpty {
                let reportURL = URL(fileURLWithPath: reportPath)
                try FileManager.default.createDirectory(
                    at: reportURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try json.write(to: reportURL, options: .atomic)
            }
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("quill-code-desktop window smoke failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ request: QuillCodeDesktopWindowSmokeRequest) async throws -> QuillCodeDesktopWindowSmokeReport {
        let window = try await waitForWindow()
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()

        guard let contentView = window.contentView else {
            throw QuillCodeDesktopSmokeFailure.windowCaptureFailed
        }
        let bounds = contentView.bounds.integral
        guard bounds.width >= 900, bounds.height >= 620 else {
            throw QuillCodeDesktopSmokeFailure.windowContentTooSmall(bounds.width, bounds.height)
        }

        let screenshotURL = screenshotURL(request: request)
        let stats = try await captureValidatedImageStats(
            window: window,
            contentView: contentView,
            bounds: bounds,
            to: screenshotURL
        )
        let workspaceSurface = try smokeSurface()
        let nativeHitTargets = try QuillCodeDesktopNativeHitTargetSmoke.validatedReport(for: workspaceSurface)
        let accessibilityFrameSamples = try QuillCodeDesktopAccessibilityFrameSampler.validatedReport(
            window: window,
            contentView: contentView,
            nativeHitTargets: nativeHitTargets
        )
        let surface = try QuillCodeDesktopWindowSmokeSurfaceReport(surface: workspaceSurface)

        return QuillCodeDesktopWindowSmokeReport(
            ok: true,
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "QuillCode",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            windowTitle: window.title,
            windowFrame: window.frame,
            contentSize: bounds.size,
            screenshotPath: screenshotURL.path,
            image: stats.report,
            nativeHitTargets: nativeHitTargets,
            accessibilityFrameSamples: accessibilityFrameSamples,
            surface: surface
        )
    }

    private static func waitForWindow() async throws -> NSWindow {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if smokeWindow == nil {
            openSmokeWindow()
        }
        for _ in 0..<100 {
            if let window = smokeWindow, isSmokeWindow(window) {
                return window
            }
            if let window = NSApplication.shared.windows.first(where: isSmokeWindow) {
                smokeWindow = window
                return window
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw QuillCodeDesktopSmokeFailure.windowNotFound
    }

    private static func openSmokeWindow() {
        let controller = QuillCodeDesktopController()
        let rootView = QuillCodeDesktopRootView(controller: controller)
            .frame(minWidth: 1280, minHeight: 900)
        let contentView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuillCode"
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        smokeController = controller
        smokeWindow = window
    }

    private static func smokeSurface() throws -> WorkspaceSurface {
        guard let smokeController else {
            throw QuillCodeDesktopSmokeFailure.windowSurfaceIncomplete("smoke controller was not retained")
        }
        return smokeController.surface
    }

    private static func isSmokeWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.title == "QuillCode" else {
            return false
        }
        guard let contentView = window.contentView else {
            return false
        }
        return contentView.bounds.width >= 900 && contentView.bounds.height >= 620
    }

    private static func screenshotURL(request: QuillCodeDesktopWindowSmokeRequest) -> URL {
        if let screenshotPath = request.screenshotPath, !screenshotPath.isEmpty {
            return URL(fileURLWithPath: screenshotPath)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-window-smoke-\(UUID().uuidString).png")
    }

    private static func captureValidatedImageStats(
        window: NSWindow,
        contentView: NSView,
        bounds: CGRect,
        to url: URL
    ) async throws -> QuillCodeDesktopSmokePixelStats {
        var lastValidationFailure: Error?

        for attempt in 0..<12 {
            window.displayIfNeeded()
            contentView.layoutSubtreeIfNeeded()

            let image = try capture(contentView: contentView, bounds: bounds, to: url)
            let stats = try QuillCodeDesktopSmokePixelStats(image: image)

            do {
                try validateImageStats(stats)
                return stats
            } catch {
                lastValidationFailure = error
                if attempt < 11 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }

        throw lastValidationFailure ?? QuillCodeDesktopSmokeFailure.windowCaptureFailed
    }

    private static func validateImageStats(_ stats: QuillCodeDesktopSmokePixelStats) throws {
        try stats.validate(
            expectedWidth: stats.report.width,
            expectedHeight: stats.report.height,
            minDistinctColorBuckets: 24,
            minBrightPixelRatio: 0.0005,
            minBlueAccentPixelRatio: 0.0001
        )
    }

    private static func capture(contentView: NSView, bounds: CGRect, to url: URL) throws -> CGImage {
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw QuillCodeDesktopSmokeFailure.windowCaptureFailed
        }
        contentView.cacheDisplay(in: bounds, to: bitmap)
        guard let cgImage = bitmap.cgImage else {
            throw QuillCodeDesktopSmokeFailure.windowCaptureFailed
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw QuillCodeDesktopSmokeFailure.pngEncodingFailed
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return cgImage
    }
}
