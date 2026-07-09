import XCTest
@testable import QuillCodeApp

final class QuillCodeCommandPaletteDensityTests: XCTestCase {
    func testCommandPaletteRowChromeIsCompactButKeepsHitTargetProtection() {
        XCTAssertLessThan(
            QuillCodeMetrics.commandPaletteRowVerticalPadding,
            12,
            "Command palette rows should keep Codex-like visual density; hit-target size comes from quillCodeFullRowButtonTarget."
        )
        XCTAssertGreaterThanOrEqual(
            QuillCodeMetrics.minimumHitTarget,
            40,
            "Tighter visible row padding must not weaken the shared native hit-target minimum."
        )
        XCTAssertLessThanOrEqual(
            QuillCodeMetrics.commandPaletteRowRadius,
            9,
            "Command palette rows should avoid oversized card-like corners."
        )
    }
}
