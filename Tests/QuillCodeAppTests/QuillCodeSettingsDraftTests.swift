import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeSettingsDraftTests: XCTestCase {
    func testInitializesFromSettingsSurface() {
        let config = AppConfig(
            apiBaseURL: "https://api.example.test/v1",
            authMode: .developerOverride,
            developerOverrideEnabled: true
        )
        let surface = WorkspaceSettingsSurface(config: config, hasStoredAPIKey: true)

        let draft = QuillCodeSettingsDraft(settings: surface)

        XCTAssertEqual(draft.apiBaseURL, "https://api.example.test/v1")
        XCTAssertEqual(draft.authMode, .developerOverride)
        XCTAssertTrue(draft.developerOverrideEnabled)
        XCTAssertEqual(draft.replacementAPIKey, "")
        XCTAssertFalse(draft.shouldClearAPIKey)
    }

    func testUpdateTrimsBaseURLAndReplacementKey() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "  https://api.trustedrouter.test/v1  "
        draft.authMode = .developerOverride
        draft.developerOverrideEnabled = true
        draft.replacementAPIKey = "  sk-tr-v1-test  "

        let update = draft.update

        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(update.apiBaseURL, "https://api.trustedrouter.test/v1")
        XCTAssertEqual(update.authMode, .developerOverride)
        XCTAssertTrue(update.developerOverrideEnabled)
        XCTAssertEqual(update.replacementAPIKey, "sk-tr-v1-test")
        XCTAssertFalse(update.shouldClearAPIKey)
    }

    func testBlankReplacementKeyBecomesNilAndClearFlagIsPreserved() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "https://api.trustedrouter.test/v1"
        draft.replacementAPIKey = "   "
        draft.shouldClearAPIKey = true

        let update = draft.update

        XCTAssertNil(update.replacementAPIKey)
        XCTAssertTrue(update.shouldClearAPIKey)
    }

    func testBlankBaseURLCannotSave() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = " \n\t "

        XCTAssertFalse(draft.canSave)
        XCTAssertEqual(draft.update.apiBaseURL, "")
    }
}
