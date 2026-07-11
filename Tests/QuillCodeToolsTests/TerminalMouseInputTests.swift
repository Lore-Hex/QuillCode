import XCTest
@testable import QuillCodeTools

final class TerminalMouseInputTests: XCTestCase {
    func testRendererTracksButtonModeAndSGREncoding() {
        let frame = TerminalOutputRenderer.renderFrame("\u{1B}[?1000;1006hmenu")

        XCTAssertEqual(frame.text, "menu")
        XCTAssertEqual(
            frame.mouseReporting,
            TerminalMouseReporting(trackingMode: .button, encoding: .sgr)
        )
    }

    func testRendererTracksModePrecedenceAndIndependentDisable() {
        let frame = TerminalOutputRenderer.renderFrame(
            "\u{1B}[?1000;1002;1003;1005;1015;1006h"
                + "\u{1B}[?1003;1006lactive"
        )

        XCTAssertEqual(frame.text, "active")
        XCTAssertEqual(frame.mouseReporting.trackingMode, .buttonMotion)
        XCTAssertEqual(frame.mouseReporting.encoding, .urxvt)
    }

    func testRendererDisablesMouseTrackingWithoutLeakingPrivateModes() {
        let frame = TerminalOutputRenderer.renderFrame(
            "\u{1B}[?1000;1006hready\u{1B}[?1000;1006ldone"
        )

        XCTAssertEqual(frame.text, "readydone")
        XCTAssertEqual(frame.mouseReporting, .disabled)
    }

    func testIncrementalParserPreservesSplitSequencesAndResetsInConstantWork() {
        var parser = TerminalMouseReportingParser()

        parser.consume("plain\u{1B}[?100")
        XCTAssertEqual(parser.reporting, .disabled)
        parser.consume("2;1006hmenu")
        XCTAssertEqual(
            parser.reporting,
            TerminalMouseReporting(trackingMode: .buttonMotion, encoding: .sgr)
        )

        parser.consume("\u{1B}[31mignored\u{1B}[?1002;1006l")
        XCTAssertEqual(parser.reporting, .disabled)
        parser.consume("\u{1B}[?1003;1015h")
        XCTAssertEqual(
            parser.reporting,
            TerminalMouseReporting(trackingMode: .anyMotion, encoding: .urxvt)
        )
        parser.reset()
        XCTAssertEqual(parser.reporting, .disabled)
    }

    func testSGREncodesPressReleaseMotionScrollAndModifiers() throws {
        let reporting = TerminalMouseReporting(trackingMode: .anyMotion, encoding: .sgr)
        let position = TerminalMousePosition(column: 12, row: 4)

        XCTAssertEqual(
            encode(.press, button: .left, position: position, reporting: reporting),
            "\u{1B}[<0;12;4M"
        )
        XCTAssertEqual(
            encode(.release, button: .left, position: position, reporting: reporting),
            "\u{1B}[<0;12;4m"
        )
        XCTAssertEqual(
            encode(.motion, button: .left, position: position, reporting: reporting),
            "\u{1B}[<32;12;4M"
        )
        XCTAssertEqual(
            encode(
                .scrollDown,
                position: position,
                modifiers: TerminalMouseModifiers(shift: true, option: true, control: true),
                reporting: reporting
            ),
            "\u{1B}[<93;12;4M"
        )
    }

    func testTrackingModeRejectsUnsupportedMotion() {
        let position = TerminalMousePosition(column: 2, row: 3)
        let buttonOnly = TerminalMouseReporting(trackingMode: .button, encoding: .sgr)
        let drag = TerminalMouseReporting(trackingMode: .buttonMotion, encoding: .sgr)

        XCTAssertNil(encode(.motion, button: .left, position: position, reporting: buttonOnly))
        XCTAssertNil(encode(.motion, button: .none, position: position, reporting: drag))
        XCTAssertEqual(
            encode(.motion, button: .left, position: position, reporting: drag),
            "\u{1B}[<32;2;3M"
        )
    }

    func testLegacyUTF8AndURXVTEncodings() {
        let position = TerminalMousePosition(column: 2, row: 3)

        XCTAssertEqual(
            encode(
                .press,
                button: .left,
                position: position,
                reporting: .init(trackingMode: .button, encoding: .x10)
            ),
            "\u{1B}[M \"#"
        )
        XCTAssertEqual(
            encode(
                .release,
                button: .left,
                position: position,
                reporting: .init(trackingMode: .button, encoding: .urxvt)
            ),
            "\u{1B}[35;2;3M"
        )
        XCTAssertNotNil(encode(
            .press,
            button: .left,
            position: .init(column: 400, row: 300),
            reporting: .init(trackingMode: .button, encoding: .utf8)
        ))
        XCTAssertNil(encode(
            .press,
            button: .left,
            position: .init(column: 224, row: 1),
            reporting: .init(trackingMode: .button, encoding: .x10)
        ))
    }

    func testDisabledAndInvalidCoordinatesProduceNoInput() {
        XCTAssertNil(encode(
            .press,
            button: .left,
            position: .init(column: 1, row: 1),
            reporting: .disabled
        ))
        XCTAssertNil(encode(
            .press,
            button: .left,
            position: .init(column: 0, row: 1),
            reporting: .init(trackingMode: .button, encoding: .sgr)
        ))
    }

    func testScrollAccumulatorQuantizesPreciseTrackpadDeltas() {
        var accumulator = TerminalScrollWheelAccumulator()

        XCTAssertEqual(
            accumulator.consume(horizontalDelta: 0, verticalDelta: 3, isPrecise: true),
            []
        )
        XCTAssertEqual(
            accumulator.consume(horizontalDelta: 0, verticalDelta: 5, isPrecise: true),
            [.scrollUp]
        )
        XCTAssertEqual(
            accumulator.consume(horizontalDelta: 0, verticalDelta: -16, isPrecise: true),
            [.scrollDown, .scrollDown]
        )
    }

    func testScrollAccumulatorUsesDominantAxisAndResetsAcrossAxisChanges() {
        var accumulator = TerminalScrollWheelAccumulator()

        XCTAssertEqual(
            accumulator.consume(horizontalDelta: 1, verticalDelta: 0, isPrecise: false),
            [.scrollLeft]
        )
        XCTAssertEqual(
            accumulator.consume(horizontalDelta: -1, verticalDelta: 0, isPrecise: false),
            [.scrollRight]
        )
        XCTAssertEqual(
            accumulator.consume(horizontalDelta: 20, verticalDelta: -40, isPrecise: true),
            [.scrollDown, .scrollDown, .scrollDown, .scrollDown, .scrollDown]
        )
    }

    func testScrollAccumulatorBoundsBurstsAndRejectsInvalidInput() {
        var accumulator = TerminalScrollWheelAccumulator()

        XCTAssertEqual(
            accumulator.consume(horizontalDelta: 0, verticalDelta: 1_000, isPrecise: true).count,
            TerminalScrollWheelAccumulator.defaultMaximumEventsPerUpdate
        )
        XCTAssertEqual(
            accumulator.consume(
                horizontalDelta: 0,
                verticalDelta: .greatestFiniteMagnitude,
                isPrecise: true
            ).count,
            TerminalScrollWheelAccumulator.defaultMaximumEventsPerUpdate
        )
        XCTAssertEqual(
            accumulator.consume(horizontalDelta: .nan, verticalDelta: 1, isPrecise: false),
            []
        )
        XCTAssertEqual(
            accumulator.consume(horizontalDelta: 0, verticalDelta: 1, isPrecise: false),
            [.scrollUp]
        )
    }

    private func encode(
        _ kind: TerminalMouseEventKind,
        button: TerminalMouseButton = .none,
        position: TerminalMousePosition,
        modifiers: TerminalMouseModifiers = TerminalMouseModifiers(),
        reporting: TerminalMouseReporting
    ) -> String? {
        TerminalMouseInputEncoder.encode(TerminalMouseInputRequest(
            event: TerminalMouseInputEvent(
                kind: kind,
                button: button,
                position: position,
                modifiers: modifiers
            ),
            reporting: reporting
        ))
    }
}
