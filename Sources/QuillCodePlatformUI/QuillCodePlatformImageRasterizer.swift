import CoreGraphics
import Foundation

#if canImport(AppKit)
import AppKit
#endif

public enum QuillCodePlatformImageRasterizer {
    public static func rasterizeVectorImage(
        from data: Data,
        maximumPixelSize: Int
    ) -> CGImage? {
        #if canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        let intrinsicSize = image.size
        guard intrinsicSize.width.isFinite,
              intrinsicSize.height.isFinite,
              intrinsicSize.width > 0,
              intrinsicSize.height > 0
        else {
            return nil
        }
        let boundedPixelSize = CGFloat(max(1, maximumPixelSize))
        let scale = min(1, boundedPixelSize / max(intrinsicSize.width, intrinsicSize.height))
        let width = max(1, Int((intrinsicSize.width * scale).rounded()))
        let height = max(1, Int((intrinsicSize.height * scale).rounded()))
        var proposedRect = NSRect(x: 0, y: 0, width: width, height: height)
        guard let rasterized = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ),
              rasterized.width <= Int(boundedPixelSize),
              rasterized.height <= Int(boundedPixelSize)
        else {
            return nil
        }
        return rasterized
        #else
        return nil
        #endif
    }
}
