import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class QuillCodeSSHConnectionDialogCoordinatorTests: XCTestCase {
    func testPresentLoadsHostsAndSelectsFirstAlias() async {
        let coordinator = QuillCodeSSHConnectionDialogCoordinator()
        let host = SSHHostConfiguration(alias: "production", hostName: "prod.example.com")

        coordinator.present {
            SSHHostDiscoveryResult(hosts: [host], configPath: "/tmp/config")
        }
        await waitUntil("SSH hosts loaded") { coordinator.draft.hostLoad.hasLoaded }

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.draft.selectedHostID, host.id)
        XCTAssertEqual(coordinator.draft.request?.connection.host, "production")
    }

    func testFailedRegistrationKeepsDialogOpenWithError() async {
        let coordinator = readyCoordinator()

        coordinator.connect { request in
            XCTAssertEqual(request.connection.host, "production")
            return .failure(message: "Permission denied.")
        }
        await waitUntil("registration failure shown") {
            coordinator.draft.errorMessage == "Permission denied."
        }

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertFalse(coordinator.draft.isConnecting)
        XCTAssertTrue(coordinator.draft.canConnect)
    }

    func testSuccessfulRegistrationDismissesDialog() async {
        let coordinator = readyCoordinator()

        coordinator.connect { _ in .success(projectID: UUID()) }
        await waitUntil("SSH dialog dismissed") { !coordinator.isPresented }

        XCTAssertFalse(coordinator.draft.isConnecting)
    }

    func testDismissIgnoresLateDiscoveryResult() async {
        let gate = SSHConnectionAsyncGate()
        let coordinator = QuillCodeSSHConnectionDialogCoordinator()

        coordinator.present {
            await gate.wait()
            return SSHHostDiscoveryResult(
                hosts: [SSHHostConfiguration(alias: "late")],
                configPath: "/tmp/config"
            )
        }
        coordinator.dismiss()
        await gate.open()
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertFalse(coordinator.draft.hostLoad.hasLoaded)
        XCTAssertTrue(coordinator.draft.hostLoad.hosts.isEmpty)
    }

    func testDismissCancelsConnectionAndIgnoresLateRegistrationResult() async {
        let gate = SSHConnectionAsyncGate()
        let coordinator = readyCoordinator()

        coordinator.connect { _ in
            await gate.wait()
            return .success(projectID: UUID())
        }
        XCTAssertTrue(coordinator.draft.isConnecting)
        coordinator.dismiss()
        await gate.open()
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertFalse(coordinator.draft.isConnecting)
        XCTAssertNil(coordinator.draft.errorMessage)
    }

    private func readyCoordinator() -> QuillCodeSSHConnectionDialogCoordinator {
        let coordinator = QuillCodeSSHConnectionDialogCoordinator()
        coordinator.isPresented = true
        coordinator.draft.apply(SSHHostDiscoveryResult(
            hosts: [SSHHostConfiguration(alias: "production")],
            configPath: "/tmp/config"
        ))
        return coordinator
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)")
    }
}

private actor SSHConnectionAsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
