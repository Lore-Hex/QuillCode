import Foundation
import QuillCodePersistence
import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopDailyDriverSmokeFixtureTests: XCTestCase {
    func testSeederCreatesDeterministicProjectScopedDailyDriverWorkspace() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let stateRoot = parent.appendingPathComponent("daily-driver", isDirectory: true)

        try QuillCodeDesktopDailyDriverSmokeFixture.seed(at: stateRoot)

        let paths = QuillCodePaths(home: stateRoot.appendingPathComponent("app-state"))
        let projects = try JSONProjectStore(fileURL: paths.projectsFile).load()
        let threads = try JSONThreadStore(directory: paths.threadsDirectory).list()
        let selectedThread = try XCTUnwrap(threads.first)
        let trustedRouterCredential = try FileSecretStore(directory: paths.secretsDirectory)
            .read(QuillSecretKeys.trustedRouterAPIKey)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(
            trustedRouterCredential,
            QuillCodeDesktopDailyDriverSmokeFixture.mockCredential
        )
        XCTAssertEqual(projects.first?.path, stateRoot.appendingPathComponent("workspace").path)
        XCTAssertEqual(threads.count, QuillCodeDesktopDailyDriverSmokeFixture.chatCount)
        XCTAssertEqual(Set(threads.map(\.id)).count, threads.count)
        XCTAssertTrue(threads.allSatisfy { $0.projectID == projects.first?.id })
        XCTAssertEqual(selectedThread.title, "Keyboard ergonomics 100")
        XCTAssertTrue(selectedThread.isPinned)
        XCTAssertEqual(
            selectedThread.messages.count,
            QuillCodeDesktopDailyDriverSmokeFixture.selectedThreadTurnCount * 2
        )
        XCTAssertTrue(
            threads.dropFirst().allSatisfy {
                $0.messages.count == QuillCodeDesktopDailyDriverSmokeFixture.shortThreadTurnCount * 2
            }
        )

        let fixtureBytes = try FileManager.default.contentsOfDirectory(
            at: paths.threadsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).reduce(0) { total, url in
            total + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertGreaterThan(fixtureBytes, 250_000)
        XCTAssertLessThan(fixtureBytes, 2_000_000)

        let request = try XCTUnwrap(QuillCodeDesktopWindowSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-window-smoke",
            "--window-smoke-state-root",
            stateRoot.path,
            "--window-smoke-performance-workload",
            QuillCodeDesktopPerformanceWorkload.dailyDriver100Chats.rawValue
        ]))
        let workspaceRoot = QuillCodeDesktopWindowSmokeWorkspaceRoot(request: request)
        let controller = workspaceRoot.makeController()
        XCTAssertTrue(controller.model.root.trustedRouterAPIKeyConfigured)
        XCTAssertFalse(
            QuillCodeDesktopAccessibilityActivationSampler.applicableActivationContractIDs(
                includesInitialSurface: true,
                controller: controller
            ).contains("onboarding.developer-key")
        )
        XCTAssertEqual(
            try QuillCodeDesktopDailyDriverSmokeFixture.validate(
                workloadID: request.performanceWorkloadID,
                controller: controller,
                workspaceRoot: workspaceRoot
            ),
            .dailyDriver100Chats
        )
    }

    func testActivationSamplerRequiresOnboardingForUnconfiguredFirstRun() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let stateRoot = parent.appendingPathComponent("first-run", isDirectory: true)
        let request = try XCTUnwrap(QuillCodeDesktopWindowSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-window-smoke",
            "--window-smoke-state-root",
            stateRoot.path
        ]))
        let workspaceRoot = QuillCodeDesktopWindowSmokeWorkspaceRoot(request: request)
        let controller = workspaceRoot.makeController()

        XCTAssertFalse(controller.model.root.trustedRouterAPIKeyConfigured)
        XCTAssertTrue(
            QuillCodeDesktopAccessibilityActivationSampler.applicableActivationContractIDs(
                includesInitialSurface: true,
                controller: controller
            ).contains("onboarding.developer-key")
        )
    }

    func testSeederParsesRequiredStateRootAndRefusesExistingDestination() throws {
        XCTAssertNil(QuillCodeDesktopDailyDriverSmokeSeedRequest(arguments: ["Quill Cowork"]))
        let request = try XCTUnwrap(QuillCodeDesktopDailyDriverSmokeSeedRequest(arguments: [
            "Quill Cowork",
            "--seed-daily-driver-window-smoke",
            "--window-smoke-state-root",
            "/tmp/quill-daily-driver"
        ]))
        XCTAssertEqual(request.stateRootPath, "/tmp/quill-daily-driver")

        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let stateRoot = parent.appendingPathComponent("daily-driver", isDirectory: true)
        try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)

        XCTAssertThrowsError(try QuillCodeDesktopDailyDriverSmokeFixture.seed(at: stateRoot)) { error in
            XCTAssertEqual(
                error as? QuillCodeDesktopDailyDriverSmokeFixtureError,
                .stateRootAlreadyExists
            )
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: stateRoot.path), [])
    }

    func testDailyDriverValidationRejectsTamperedMarker() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let stateRoot = parent.appendingPathComponent("daily-driver", isDirectory: true)
        try QuillCodeDesktopDailyDriverSmokeFixture.seed(at: stateRoot)

        let markerURL = stateRoot.appendingPathComponent(
            QuillCodeDesktopDailyDriverSmokeFixture.markerFileName
        )
        var marker = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: markerURL)) as? [String: Any]
        )
        marker["chatCount"] = 99
        try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
            .write(to: markerURL, options: .atomic)

        let request = try XCTUnwrap(QuillCodeDesktopWindowSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-window-smoke",
            "--window-smoke-state-root",
            stateRoot.path,
            "--window-smoke-performance-workload",
            QuillCodeDesktopPerformanceWorkload.dailyDriver100Chats.rawValue
        ]))
        let workspaceRoot = QuillCodeDesktopWindowSmokeWorkspaceRoot(request: request)
        let controller = workspaceRoot.makeController()

        XCTAssertThrowsError(
            try QuillCodeDesktopDailyDriverSmokeFixture.validate(
                workloadID: request.performanceWorkloadID,
                controller: controller,
                workspaceRoot: workspaceRoot
            )
        ) { error in
            XCTAssertEqual(
                error as? QuillCodeDesktopDailyDriverSmokeFixtureError,
                .invalidFixture("marker contract mismatch")
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-daily-driver-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
