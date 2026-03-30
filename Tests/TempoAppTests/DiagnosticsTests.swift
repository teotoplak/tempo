import Foundation
import XCTest
@testable import TempoApp

final class DiagnosticsTests: XCTestCase {
    func testRecorderHandlesConcurrentWritesWhileRotating() throws {
        let diagnosticsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = TempoDiagnosticsRecorder(baseDirectoryURL: diagnosticsDirectory, maxFileSizeBytes: 256)

        DispatchQueue.concurrentPerform(iterations: 64) { index in
            recorder.record(
                component: "DiagnosticsTests",
                event: "concurrent-write",
                metadata: ["index": "\(index)", "payload": String(repeating: "x", count: 64)]
            )
        }

        let logFileURL = try XCTUnwrap(recorder.logFileURL)
        let archivedLogFileURL = try XCTUnwrap(recorder.archivedLogFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedLogFileURL.path))

        let currentContents = try String(contentsOf: logFileURL, encoding: .utf8)
        let archivedContents = try String(contentsOf: archivedLogFileURL, encoding: .utf8)
        XCTAssertFalse(currentContents.isEmpty)
        XCTAssertFalse(archivedContents.isEmpty)
    }

    @MainActor
    func testScreenLockAndIdleReturnWriteDiagnosticsTrace() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let diagnosticsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = TempoDiagnosticsRecorder(baseDirectoryURL: diagnosticsDirectory)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedDiagnosticsClock(now: now),
            diagnosticsRecorder: recorder,
            launchAtLoginController: FixedDiagnosticsLaunchAtLoginController(isEnabled: false)
        )

        model.handleScreenLock()
        model.handleIdleReturn()

        let logFileURL = try XCTUnwrap(recorder.logFileURL)
        let contents = try String(contentsOf: logFileURL, encoding: .utf8)

        XCTAssertTrue(contents.contains("\"event\":\"handle-screen-lock\""))
        XCTAssertTrue(contents.contains("\"event\":\"handle-idle-return\""))
        XCTAssertTrue(contents.contains("\"event\":\"runtime-state-applied\""))
    }

    @MainActor
    func testScreenWakeRecoversPendingScreenLockIdleUsingExplicitActivityDate() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let idleStart = now.addingTimeInterval(-(15 * 60))
        let recorder = TempoDiagnosticsRecorder(
            baseDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedDiagnosticsClock(now: now),
            diagnosticsRecorder: recorder,
            launchAtLoginController: FixedDiagnosticsLaunchAtLoginController(isEnabled: false)
        )
        model.modelContext.insert(
            CheckInRecord(
                timestamp: idleStart,
                kind: "idle",
                source: "screen-locked",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try model.modelContext.save()

        model.handleScreenWake(activityDate: now)

        XCTAssertTrue(model.isIdlePending)
        XCTAssertEqual(model.pendingIdleStartedAt, idleStart)
        XCTAssertEqual(model.pendingIdleEndedAt, now)
        XCTAssertTrue(model.checkInPromptState.isPresented)
    }

    @MainActor
    func testScreenWakeRecoversPendingScreenLockIdleWhenActivitySampleIsStale() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let idleStart = now.addingTimeInterval(-(15 * 60))
        let staleActivityDate = idleStart.addingTimeInterval(-60)
        let diagnosticsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = TempoDiagnosticsRecorder(baseDirectoryURL: diagnosticsDirectory)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedDiagnosticsClock(now: now),
            diagnosticsRecorder: recorder,
            launchAtLoginController: FixedDiagnosticsLaunchAtLoginController(isEnabled: false)
        )
        model.modelContext.insert(
            CheckInRecord(
                timestamp: idleStart,
                kind: "idle",
                source: "screen-locked",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try model.modelContext.save()

        model.handleScreenWake(activityDate: staleActivityDate)

        XCTAssertTrue(model.isIdlePending)
        XCTAssertEqual(model.pendingIdleStartedAt, idleStart)
        XCTAssertEqual(model.pendingIdleEndedAt, now)
        XCTAssertTrue(model.checkInPromptState.isPresented)

        let logFileURL = try XCTUnwrap(recorder.logFileURL)
        let contents = try String(contentsOf: logFileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"usedScreenLockReturnFallback\":\"true\""))
    }
}

private struct FixedDiagnosticsClock: SchedulerClock {
    let now: Date
}

@MainActor
private final class FixedDiagnosticsLaunchAtLoginController: LaunchAtLoginControlling {
    let isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {}
}
