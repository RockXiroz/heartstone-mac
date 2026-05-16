import AppKit

// A borderless, click-through panel that floats above Hearthstone on the same screen.
final class OverlayWindow: NSPanel {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Use the overlay level (102) rather than screenSaver (1000).
        // kCGOverlayWindowLevel correctly joins full-screen app Spaces on macOS 13+.
        level            = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        backgroundColor  = .clear
        isOpaque         = false
        hasShadow        = false
        ignoresMouseEvents  = true          // all clicks pass through to the game
        isReleasedWhenClosed = false
        collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        alphaValue = 1.0
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
