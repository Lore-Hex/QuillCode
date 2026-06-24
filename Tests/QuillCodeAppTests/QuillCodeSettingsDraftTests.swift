import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeSettingsDraftTests: XCTestCase {
    func testDraftInitializesFromSettingsSurface() {
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(
                apiBaseURL: "https://api.trustedrouter.test/v1",
                authMode: .developerOverride,
                developerOverrideEnabled: true
            ),
            hasStoredAPIKey: true
        )

        let draft = QuillCodeSettingsDraft(settings: settings)

        XCTAssertEqual(draft.apiBaseURL, "https://api.trustedrouter.test/v1")
        XCTAssertEqual(draft.authMode, .developerOverride)
        XCTAssertTrue(draft.developerOverrideEnabled)
        XCTAssertTrue(draft.canSave)
    }

    func testUpdateTrimsFieldsAndKeepsBlankReplacementKeyNil() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "  https://api.trustedrouter.test/v1  "
        draft.authMode = .oauth
        draft.developerOverrideEnabled = false
        draft.replacementAPIKey = " \n "

        let update = draft.update

        XCTAssertEqual(update.apiBaseURL, "https://api.trustedrouter.test/v1")
        XCTAssertEqual(update.authMode, .oauth)
        XCTAssertFalse(update.developerOverrideEnabled)
        XCTAssertNil(update.replacementAPIKey)
        XCTAssertFalse(update.shouldClearAPIKey)
    }

    func testUpdatePreservesClearFlagAndTrimmedReplacementKey() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "https://api.trustedrouter.test/v1"
        draft.authMode = .developerOverride
        draft.developerOverrideEnabled = true
        draft.replacementAPIKey = "  sk-tr-test  "
        draft.shouldClearAPIKey = true

        let update = draft.update

        XCTAssertEqual(update.authMode, .developerOverride)
        XCTAssertTrue(update.developerOverrideEnabled)
        XCTAssertEqual(update.replacementAPIKey, "sk-tr-test")
        XCTAssertTrue(update.shouldClearAPIKey)
    }

    func testBlankAPIBaseURLCannotSave() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = " \n "

        XCTAssertFalse(draft.canSave)
    }
}
