import AppKit
import Foundation

struct QuillCodeDesktopSourceOpenRequest: Equatable {
    var fileURL: URL
    var lineNumber: Int?
}

@MainActor
protocol QuillCodeDesktopSourceOpening {
    @discardableResult
    func openSource(_ request: QuillCodeDesktopSourceOpenRequest) -> Bool
}

struct MacSourceOpener: QuillCodeDesktopSourceOpening {
    @discardableResult
    func openSource(_ request: QuillCodeDesktopSourceOpenRequest) -> Bool {
        if let lineNumber = request.lineNumber,
           openWithXed(fileURL: request.fileURL, lineNumber: lineNumber) {
            return true
        }
        return NSWorkspace.shared.open(request.fileURL)
    }

    private func openWithXed(fileURL: URL, lineNumber: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xed", "-l", String(lineNumber), fileURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
