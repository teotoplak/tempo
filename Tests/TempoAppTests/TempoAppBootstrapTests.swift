import Foundation
import XCTest
@testable import TempoApp

final class TempoAppBootstrapTests: XCTestCase {
    func testTempoAppModelBootstraps() throws {
        let model = TempoAppModel(modelContainer: TempoModelContainer.inMemory())

        XCTAssertEqual(model.launchState, .launching)
        XCTAssertEqual(model.settings.pollingIntervalMinutes, 25)
        XCTAssertEqual(model.settings.idleThresholdMinutes, 5)
    }

    func testPackageManifestStaysLocalOnly() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = rootURL.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL)

        XCTAssertTrue(manifest.contains("platforms: ["))
        XCTAssertTrue(manifest.contains(".executableTarget("))
        XCTAssertFalse(manifest.contains(".package(url:"))
    }
}
