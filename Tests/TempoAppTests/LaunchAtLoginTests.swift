import Foundation
import XCTest
@testable import TempoApp

final class LaunchAtLoginTests: XCTestCase {
    @MainActor
    func testBootstrapSyncUsesControllerState() throws {
        let controller = StubLaunchAtLoginController(isEnabled: true)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedLaunchAtLoginClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
            launchAtLoginController: controller
        )

        model.performInitialLaunchIfNeeded()

        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertTrue(model.settings.launchAtLoginEnabled)
    }

    @MainActor
    func testDefaultPreferenceEnablesLaunchAtLoginDuringBootstrap() throws {
        let controller = StubLaunchAtLoginController(isEnabled: false)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedLaunchAtLoginClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
            launchAtLoginController: controller
        )

        XCTAssertTrue(model.settings.launchAtLoginEnabled)
        XCTAssertFalse(model.launchAtLoginEnabled)

        model.performInitialLaunchIfNeeded()

        XCTAssertEqual(controller.setEnabledCalls, [true])
        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertTrue(model.settings.launchAtLoginEnabled)
        XCTAssertNil(model.launchAtLoginErrorMessage)
    }

    @MainActor
    func testBootstrapPreservesPreferredDefaultWhenRegistrationFails() throws {
        let controller = StubLaunchAtLoginController(
            isEnabled: false,
            error: LaunchAtLoginControllerError.registrationFailed(underlying: TestLaunchAtLoginError.registrationFailed)
        )
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedLaunchAtLoginClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
            launchAtLoginController: controller
        )

        model.performInitialLaunchIfNeeded()

        XCTAssertEqual(controller.setEnabledCalls, [true])
        XCTAssertFalse(model.launchAtLoginEnabled)
        XCTAssertTrue(model.settings.launchAtLoginEnabled)
        XCTAssertNotNil(model.launchAtLoginErrorMessage)
    }

    @MainActor
    func testSaveLaunchAtLoginPreferencePersistsEnabledState() throws {
        let controller = StubLaunchAtLoginController(isEnabled: false)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedLaunchAtLoginClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
            launchAtLoginController: controller
        )

        try model.saveLaunchAtLoginPreference(true)

        XCTAssertEqual(controller.setEnabledCalls, [true])
        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertTrue(model.settings.launchAtLoginEnabled)
    }

    @MainActor
    func testSaveLaunchAtLoginPreferenceRestoresSystemStateAfterFailure() {
        let controller = StubLaunchAtLoginController(
            isEnabled: false,
            error: LaunchAtLoginControllerError.registrationFailed(underlying: TestLaunchAtLoginError.registrationFailed)
        )
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedLaunchAtLoginClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
            launchAtLoginController: controller
        )

        XCTAssertThrowsError(try model.saveLaunchAtLoginPreference(true))
        XCTAssertFalse(model.launchAtLoginEnabled)
        XCTAssertFalse(model.settings.launchAtLoginEnabled)
        XCTAssertNotNil(model.launchAtLoginErrorMessage)
    }

    func testSettingsPopoverContainsLaunchAtLoginSection() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/Features/Settings/SettingsPopoverView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(viewSource.contains("Section(\"Launch at Login\")"))
        XCTAssertTrue(viewSource.contains("Launch Tempo when I sign in"))
    }
}

@MainActor
private final class StubLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var isEnabled: Bool
    private let error: (any Error)?
    private(set) var setEnabledCalls: [Bool] = []

    init(isEnabled: Bool, error: (any Error)? = nil) {
        self.isEnabled = isEnabled
        self.error = error
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let error {
            throw error
        }

        isEnabled = enabled
    }
}

private enum TestLaunchAtLoginError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Registration failed"
        }
    }
}

private struct FixedLaunchAtLoginClock: SchedulerClock {
    let now: Date
}
