import AppKit
import SwiftUI

@MainActor
final class CheckInPromptWindowController {
    private static let standardPromptSize = CGSize(width: 360, height: 320)
    private static let idleResolutionPromptSize = CGSize(width: 392, height: 420)

    private(set) var backdropWindow: NSWindow?
    private(set) var promptWindow: NSWindow?
    private weak var appModel: TempoAppModel?
    private var priorActivationPolicy: NSApplication.ActivationPolicy?
    private var activationObserver: NSObjectProtocol?

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
        removeActivationObserver()

        if let priorActivationPolicy {
            NSApplication.shared.setActivationPolicy(priorActivationPolicy)
            self.priorActivationPolicy = nil
        }
    }

    func show(using state: CheckInPromptState) {
        let screenFrame = NSScreen.main?.frame ?? .zero
        let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame
        let anchorRect = currentMenuBarAnchorRect(in: visibleFrame)

        if promptWindow == nil {
            promptWindow = Self.makePromptWindow(screenFrame: visibleFrame, state: state)
        }

        if Self.wantsBackdrop(for: state) {
            if backdropWindow == nil {
                backdropWindow = Self.makeBackdropWindow(screenFrame: screenFrame)
            }

            backdropWindow?.setFrame(screenFrame, display: false)
            backdropWindow?.orderFrontRegardless()
        } else {
            backdropWindow?.orderOut(nil)
        }

        promptWindow?.setFrame(Self.promptFrame(in: visibleFrame, state: state, anchorRect: anchorRect), display: false)
        promptWindow?.contentViewController = NSHostingController(
            rootView: CheckInPromptView(appModel: appModel, state: state)
        )

        installActivationObserverIfNeeded()
        bringPromptToFront()
    }

    private func promoteAppForPromptInteraction() {
        let app = NSApplication.shared
        if priorActivationPolicy == nil {
            priorActivationPolicy = app.activationPolicy()
        }

        if app.activationPolicy() != .regular {
            app.setActivationPolicy(.regular)
        }
    }

    private func installActivationObserverIfNeeded() {
        guard activationObserver == nil else {
            return
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reassertPromptFocusIfNeeded()
            }
        }
    }

    private func removeActivationObserver() {
        guard let activationObserver else {
            return
        }

        NotificationCenter.default.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    private func reassertPromptFocusIfNeeded() {
        guard promptWindow?.isVisible == true else {
            return
        }

        bringPromptToFront()
    }

    private func bringPromptToFront() {
        promoteAppForPromptInteraction()
        NSApplication.shared.activate(ignoringOtherApps: true)
        backdropWindow?.orderFrontRegardless()
        promptWindow?.orderFrontRegardless()
        promptWindow?.makeMain()
        promptWindow?.makeKeyAndOrderFront(nil)
    }

    private func currentMenuBarAnchorRect(in visibleFrame: CGRect) -> CGRect? {
        candidateMenuBarWindows(in: visibleFrame)
            .first?
            .frame
    }

    private func candidateMenuBarWindows(in visibleFrame: CGRect) -> [NSWindow] {
        NSApplication.shared.windows
            .filter { window in
                window !== promptWindow &&
                window !== backdropWindow &&
                window.isVisible &&
                !window.frame.isEmpty &&
                window.frame.maxY >= visibleFrame.maxY - 120 &&
                window.frame.width <= 420 &&
                window.frame.height <= 520
            }
            .sorted { lhs, rhs in
                if lhs.frame.maxX == rhs.frame.maxX {
                    if lhs.frame.maxY == rhs.frame.maxY {
                        return lhs.frame.width > rhs.frame.width
                    }

                    return lhs.frame.maxY > rhs.frame.maxY
                }

                return lhs.frame.maxX > rhs.frame.maxX
            }
    }

    static func makeBackdropWindow(screenFrame: CGRect) -> NSWindow {
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return window
    }

    static func makePromptWindow(screenFrame: CGRect, state: CheckInPromptState = .hidden) -> NSWindow {
        let frame = promptFrame(in: screenFrame, state: state)
        let panel = CheckInPromptWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.isMovable = false
        return panel
    }

    static func promptFrame(in screenFrame: CGRect, state: CheckInPromptState = .hidden, anchorRect: CGRect? = nil) -> CGRect {
        let size = promptSize(for: state)
        return CGRect(
            x: screenFrame.midX - (size.width / 2),
            y: screenFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    static func promptSize(for state: CheckInPromptState) -> CGSize {
        standardPromptSize
    }

    static func wantsBackdrop(for state: CheckInPromptState) -> Bool {
        state.isPresented
    }
}

private final class CheckInPromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {}
}
