import AppKit
import SwiftUI

@MainActor
final class CheckInPromptWindowController {
    private(set) var backdropWindow: NSWindow?
    private(set) var promptWindow: NSPanel?
    private weak var appModel: TempoAppModel?

    func bind(appModel: TempoAppModel) {
        self.appModel = appModel
    }

    func update(with state: CheckInPromptState) {
        if state.isPresented {
            show(using: state)
        } else {
            hide()
        }
    }

    func hide() {
        promptWindow?.orderOut(nil)
        backdropWindow?.orderOut(nil)
    }

    func show(using state: CheckInPromptState) {
        let screenFrame = NSScreen.main?.frame ?? .zero

        if backdropWindow == nil {
            backdropWindow = Self.makeBackdropWindow(screenFrame: screenFrame)
        }

        if promptWindow == nil {
            promptWindow = Self.makePromptWindow(screenFrame: screenFrame)
        }

        backdropWindow?.setFrame(screenFrame, display: false)
        promptWindow?.setFrame(Self.promptFrame(in: screenFrame), display: false)
        promptWindow?.contentViewController = NSHostingController(
            rootView: CheckInPromptView(appModel: appModel, state: state)
        )

        backdropWindow?.orderFrontRegardless()
        promptWindow?.orderFrontRegardless()
    }

    static func makeBackdropWindow(screenFrame: CGRect) -> NSWindow {
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    static func makePromptWindow(screenFrame: CGRect) -> NSPanel {
        let frame = promptFrame(in: screenFrame)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }

    static func promptFrame(in screenFrame: CGRect) -> CGRect {
        let size = CGSize(width: 520, height: 420)
        return CGRect(
            x: screenFrame.midX - (size.width / 2),
            y: screenFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }
}
