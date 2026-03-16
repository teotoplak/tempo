import AppKit
import SwiftUI

@MainActor
final class CheckInPromptWindowController {
    private static let standardPromptSize = CGSize(width: 360, height: 320)
    private static let idleResolutionPromptSize = CGSize(width: 620, height: 560)

    private(set) var backdropWindow: NSWindow?
    private(set) var promptWindow: NSWindow?
    private weak var appModel: TempoAppModel?
    private var priorActivationPolicy: NSApplication.ActivationPolicy?

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

        if let priorActivationPolicy {
            NSApplication.shared.setActivationPolicy(priorActivationPolicy)
            self.priorActivationPolicy = nil
        }
    }

    func show(using state: CheckInPromptState) {
        let screenFrame = NSScreen.main?.frame ?? .zero
        let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame
        let shouldShowBackdrop = Self.wantsBackdrop(for: state)
        let anchorRect = currentMenuBarAnchorRect(in: visibleFrame)

        if shouldShowBackdrop, backdropWindow == nil {
            backdropWindow = Self.makeBackdropWindow(screenFrame: screenFrame)
        }

        if promptWindow == nil {
            promptWindow = Self.makePromptWindow(screenFrame: visibleFrame, state: state)
        }

        if shouldShowBackdrop {
            backdropWindow?.setFrame(screenFrame, display: false)
            backdropWindow?.orderFrontRegardless()
        } else {
            backdropWindow?.orderOut(nil)
        }

        promptWindow?.setFrame(Self.promptFrame(in: visibleFrame, state: state, anchorRect: anchorRect), display: false)
        promptWindow?.contentViewController = NSHostingController(
            rootView: CheckInPromptView(appModel: appModel, state: state)
        )

        promoteAppForPromptInteraction()
        NSApplication.shared.activate(ignoringOtherApps: true)
        promptWindow?.orderFrontRegardless()
        promptWindow?.makeMain()
        promptWindow?.makeKeyAndOrderFront(nil)
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

    private func currentMenuBarAnchorRect(in visibleFrame: CGRect) -> CGRect? {
        NSApplication.shared.windows
            .filter { window in
                window !== promptWindow &&
                window !== backdropWindow &&
                window.isVisible &&
                !window.frame.isEmpty &&
                window.frame.maxY >= visibleFrame.maxY - 120
            }
            .sorted { lhs, rhs in
                if lhs.frame.maxY == rhs.frame.maxY {
                    return lhs.frame.width < rhs.frame.width
                }

                return lhs.frame.maxY > rhs.frame.maxY
            }
            .first?
            .frame
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

    static func makePromptWindow(screenFrame: CGRect, state: CheckInPromptState = .hidden) -> NSWindow {
        let frame = promptFrame(in: screenFrame, state: state)
        let panel = CheckInPromptWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        return panel
    }

    static func promptFrame(in screenFrame: CGRect, state: CheckInPromptState = .hidden, anchorRect: CGRect? = nil) -> CGRect {
        let size = promptSize(for: state)
        if wantsBackdrop(for: state) {
            return CGRect(
                x: screenFrame.midX - (size.width / 2),
                y: screenFrame.midY - (size.height / 2),
                width: size.width,
                height: size.height
            )
        }

        if let anchorRect {
            let gap: CGFloat = 8
            let minX = screenFrame.minX + 12
            let maxX = screenFrame.maxX - size.width - 12
            let anchoredX = max(minX, min(anchorRect.midX - (size.width / 2), maxX))
            let anchoredY = anchorRect.minY - size.height - gap

            return CGRect(
                x: anchoredX,
                y: max(screenFrame.minY + 12, anchoredY),
                width: size.width,
                height: size.height
            )
        }

        let topInset: CGFloat = 10
        let trailingInset: CGFloat = 20
        return CGRect(
            x: screenFrame.maxX - size.width - trailingInset,
            y: screenFrame.maxY - size.height - topInset,
            width: size.width,
            height: size.height
        )
    }

    static func promptSize(for state: CheckInPromptState) -> CGSize {
        state.promptTitle == "Resolve idle time" ? idleResolutionPromptSize : standardPromptSize
    }

    static func wantsBackdrop(for state: CheckInPromptState) -> Bool {
        state.promptTitle == "Resolve idle time"
    }
}

private final class CheckInPromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
