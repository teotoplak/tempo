import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CheckInHotKeyTests: XCTestCase {
    func testHotKeyDisplayCombinesModifiersAndKey() {
        let hotKey = CheckInHotKey(
            keyCode: 8,
            modifierFlags: CheckInHotKey.modifierFlags(command: true, option: true)
        )

        XCTAssertEqual(hotKey.displayString, "Option+Command+C")
    }

    @MainActor
    func testSettingHotKeyPersistsAndRegisters() {
        let store = InMemoryCheckInHotKeyStore()
        let registrar = RecordingCheckInHotKeyRegistrar()
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            launchAtLoginController: FixedHotKeyLaunchAtLoginController(isEnabled: false),
            checkInHotKeyStore: store,
            checkInHotKeyRegistrar: registrar
        )
        let hotKey = CheckInHotKey(
            keyCode: 8,
            modifierFlags: CheckInHotKey.modifierFlags(command: true, option: true)
        )

        appModel.setCheckInHotKey(hotKey)

        XCTAssertEqual(appModel.checkInHotKey, hotKey)
        XCTAssertEqual(store.savedHotKey, hotKey)
        XCTAssertEqual(registrar.registeredHotKey, hotKey)
    }

    @MainActor
    func testRegisteredHotKeyPresentsCheckInPrompt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryCheckInHotKeyStore()
        let registrar = RecordingCheckInHotKeyRegistrar()
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedHotKeyClock(now: now),
            launchAtLoginController: FixedHotKeyLaunchAtLoginController(isEnabled: false),
            checkInHotKeyStore: store,
            checkInHotKeyRegistrar: registrar
        )
        let hotKey = CheckInHotKey(
            keyCode: 8,
            modifierFlags: CheckInHotKey.modifierFlags(command: true, option: true)
        )

        appModel.setCheckInHotKey(hotKey)
        registrar.trigger()

        XCTAssertTrue(appModel.checkInPromptState.isPresented)
        XCTAssertTrue(appModel.isPromptOverdue)
    }

    @MainActor
    func testClearingHotKeyPersistsAndUnregisters() {
        let hotKey = CheckInHotKey(
            keyCode: 8,
            modifierFlags: CheckInHotKey.modifierFlags(command: true, option: true)
        )
        let store = InMemoryCheckInHotKeyStore(initialHotKey: hotKey)
        let registrar = RecordingCheckInHotKeyRegistrar()
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            launchAtLoginController: FixedHotKeyLaunchAtLoginController(isEnabled: false),
            checkInHotKeyStore: store,
            checkInHotKeyRegistrar: registrar
        )

        appModel.clearCheckInHotKey()

        XCTAssertNil(appModel.checkInHotKey)
        XCTAssertNil(store.savedHotKey)
        XCTAssertTrue(registrar.didUnregister)
    }
}

@MainActor
private final class InMemoryCheckInHotKeyStore: CheckInHotKeyStoring {
    private var hotKey: CheckInHotKey?
    private(set) var savedHotKey: CheckInHotKey?

    init(initialHotKey: CheckInHotKey? = nil) {
        self.hotKey = initialHotKey
        self.savedHotKey = initialHotKey
    }

    func load() -> CheckInHotKey? {
        hotKey
    }

    func save(_ hotKey: CheckInHotKey?) {
        self.hotKey = hotKey
        savedHotKey = hotKey
    }
}

@MainActor
private final class RecordingCheckInHotKeyRegistrar: CheckInHotKeyRegistering {
    private(set) var registeredHotKey: CheckInHotKey?
    private(set) var didUnregister = false
    private var action: (@MainActor () -> Void)?

    func register(_ hotKey: CheckInHotKey?, action: @escaping @MainActor () -> Void) throws {
        registeredHotKey = hotKey
        didUnregister = hotKey == nil
        self.action = action
    }

    func unregister() {
        registeredHotKey = nil
        didUnregister = true
        action = nil
    }

    func trigger() {
        action?()
    }
}

private struct FixedHotKeyClock: SchedulerClock {
    let now: Date
}

private final class FixedHotKeyLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
