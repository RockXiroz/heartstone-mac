import AppKit

// Full-screen transparent panel for drawing arrows over the game.
// Mouse events pass through so the game remains fully playable.
final class OverlayWindow: NSPanel {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level               = .screenSaver
        backgroundColor     = .clear
        isOpaque            = false
        hasShadow           = false
        ignoresMouseEvents  = true
        isReleasedWhenClosed = false
        collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        alphaValue = 1.0
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
