import AppKit

// A borderless, click-through, always-on-top panel that floats over Hearthstone.
final class OverlayWindow: NSPanel {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level            = .screenSaver          // above everything, including full-screen games
        backgroundColor  = .clear
        isOpaque         = false
        hasShadow        = false
        ignoresMouseEvents = true                // pass all input to the game
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        alphaValue       = 1.0
    }

    // Update frame to track the Hearthstone window
    func trackWindow(frame: CGRect) {
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
