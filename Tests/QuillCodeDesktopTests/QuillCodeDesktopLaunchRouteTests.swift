import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopLaunchRouteTests: XCTestCase {
    func testOrdinaryLaunchHasNoSpecialRouteCandidates() {
        XCTAssertEqual(
            QuillCodeDesktopLaunchRoute.candidates(arguments: ["Quill Cowork", "--project", "/tmp/work"]),
            []
        )
    }

    func testCandidatesPreserveEstablishedPrecedenceRegardlessOfArgumentOrder() {
        let arguments = [
            "Quill Cowork",
            "--native-render-smoke",
            "--cowork-eval",
            QuillCodeDesktopUpdaterSmokeRequest.modeArgument,
            QuillCodeDesktopUpdateHelperRequest.modeArgument,
            "--native-window-smoke",
            "--composer-draft-crash-smoke",
            QuillCodeDesktopRelocationSmokeRequest.modeArgument,
            "--agent-run-crash-smoke",
            "--seed-daily-driver-window-smoke",
            "--cowork-eval",
        ]

        XCTAssertEqual(
            QuillCodeDesktopLaunchRoute.candidates(arguments: arguments),
            [
                .updateHelper,
                .dailyDriverSeed,
                .relocationSmoke,
                .updaterSmoke,
                .coworkEval,
                .composerDraftCrashSmoke,
                .agentRunCrashSmoke,
                .windowSmoke,
                .renderSmoke,
            ]
        )
    }
}
