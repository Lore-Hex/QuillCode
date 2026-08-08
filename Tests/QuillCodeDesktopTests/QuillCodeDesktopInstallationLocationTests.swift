import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopInstallationLocationTests: XCTestCase {
    func testWritableApplicationDoesNotPresentReminder() {
        let controller = makeController(availability: .available)

        controller.startIfNeeded()

        XCTAssertFalse(controller.isPresented)
    }

    func testReadOnlyApplicationAlreadyInApplicationsDoesNotPresentReminder() {
        var configuration = makeConfiguration()
        configuration.applicationURL = URL(
            fileURLWithPath: "/Applications/Quill Cowork.app",
            isDirectory: true
        )
        let controller = makeController(
            configuration: configuration,
            availability: .requiresRelocation
        )

        controller.startIfNeeded()

        XCTAssertFalse(controller.isPresented)
    }

    func testReadOnlyApplicationPresentsAndDismissesOncePerBuild() {
        let defaults = makeDefaults()
        let configuration = makeDiskImageConfiguration(currentBuild: "43")
        let controller = makeController(
            configuration: configuration,
            availability: .requiresRelocation,
            defaults: defaults
        )

        controller.startIfNeeded()
        XCTAssertTrue(controller.isPresented)

        controller.dismiss()
        XCTAssertFalse(controller.isPresented)
        controller.startIfNeeded()
        XCTAssertFalse(controller.isPresented)

        var nextBuild = configuration
        nextBuild.currentBuild = "44"
        let nextBuildController = makeController(
            configuration: nextBuild,
            availability: .requiresRelocation,
            defaults: defaults
        )
        nextBuildController.startIfNeeded()
        XCTAssertTrue(nextBuildController.isPresented)
    }

    func testOpenApplicationsDismissesAndOpensConfiguredFolder() {
        let applicationsURL = URL(fileURLWithPath: "/Test Applications", isDirectory: true)
        var openedURL: URL?
        let controller = makeController(
            availability: .requiresRelocation,
            applicationsURL: applicationsURL,
            openApplications: { openedURL = $0 }
        )
        controller.startIfNeeded()
        XCTAssertTrue(controller.isPresented)

        controller.openApplicationsFolder()

        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(openedURL, applicationsURL.standardizedFileURL)
    }

    func testUnavailableConfigurationNeverPresents() {
        let controller = QuillCodeDesktopInstallationLocationController(
            configuration: nil,
            inspector: InstallationLocationInspectorStub(.requiresRelocation),
            defaults: makeDefaults(),
            openApplications: { _ in XCTFail("Should not open Applications") }
        )

        controller.startIfNeeded()
        controller.dismiss()

        XCTAssertFalse(controller.isPresented)
    }

    private func makeController(
        configuration: QuillCodeDesktopUpdateConfiguration? = nil,
        availability: QuillCodeDesktopUpdateInstallationAvailability,
        defaults: UserDefaults? = nil,
        applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        openApplications: @escaping @MainActor (URL) -> Void = { _ in }
    ) -> QuillCodeDesktopInstallationLocationController {
        QuillCodeDesktopInstallationLocationController(
            configuration: configuration ?? makeDiskImageConfiguration(),
            inspector: InstallationLocationInspectorStub(availability),
            defaults: defaults ?? makeDefaults(),
            applicationsURL: applicationsURL,
            openApplications: openApplications
        )
    }

    private func makeDiskImageConfiguration(
        currentBuild: String = "42"
    ) -> QuillCodeDesktopUpdateConfiguration {
        var configuration = makeConfiguration(currentBuild: currentBuild)
        configuration.applicationURL = URL(
            fileURLWithPath: "/Volumes/Quill Cowork/Quill Cowork.app",
            isDirectory: true
        )
        return configuration
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "InstallationLocationTests.\(UUID().uuidString)") ?? .standard
    }
}

private struct InstallationLocationInspectorStub: QuillCodeDesktopUpdateInstallationInspecting {
    var availabilityValue: QuillCodeDesktopUpdateInstallationAvailability

    init(_ availabilityValue: QuillCodeDesktopUpdateInstallationAvailability) {
        self.availabilityValue = availabilityValue
    }

    func availability(
        for configuration: QuillCodeDesktopUpdateConfiguration
    ) -> QuillCodeDesktopUpdateInstallationAvailability {
        availabilityValue
    }
}
