import AppKit
import Foundation
import XCTest
@testable import TempoApp

final class CheckInPromptPresentationTests: XCTestCase {
    @MainActor
    func testBackdropIgnoresMouseEvents() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let window = CheckInPromptWindowController.makeBackdropWindow(screenFrame: screenFrame)

        XCTAssertEqual(window.frame, screenFrame)
        XCTAssertTrue(window.ignoresMouseEvents)
    }

    @MainActor
    func testPromptUsesFullScreenAuxiliary() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let panel = CheckInPromptWindowController.makePromptWindow(screenFrame: screenFrame)

        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testElapsedFormattingUsesMinutes() {
        XCTAssertEqual(
            TempoAppModel.formattedElapsedText(for: 25 * 60),
            "Elapsed 25 min"
        )
    }
}
