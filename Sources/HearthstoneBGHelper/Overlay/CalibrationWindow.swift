import AppKit

// Full-screen dimmed window that captures exactly two clicks: the centre of the
// leftmost visible shop card, then the rightmost. Returns the points in
// bottom-left (AppKit) global coordinates.
@MainActor
final class CalibrationWindow: NSWindow {

    private var points: [CGPoint] = []
    private let onFinish: ([CGPoint]) -> Void
    private let hintLabel = NSTextField(labelWithString: "")

    init(screen: NSScreen, onFinish: @escaping ([CGPoint]) -> Void) {
        self.onFinish = onFinish
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        backgroundColor = NSColor.black.withAlphaComponent(0.35)
        isOpaque = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let v = ClickView(frame: screen.frame)
        v.onClick = { [weak self] p in self?.record(p) }
        contentView = v

        hintLabel.font = .boldSystemFont(ofSize: 22)
        hintLabel.textColor = .white
        hintLabel.alignment = .center
        hintLabel.frame = NSRect(x: 0, y: screen.frame.height - 140,
                                 width: screen.frame.width, height: 40)
        v.addSubview(hintLabel)
        updateHint()
    }

    override var canBecomeKey: Bool { true }

    private func updateHint() {
        hintLabel.stringValue = points.isEmpty
            ? "校準 1/2：請點擊「最左邊」商店卡的正中央"
            : "校準 2/2：請點擊「最右邊」商店卡的正中央"
    }

    private func record(_ p: CGPoint) {
        points.append(p)
        if points.count >= 2 {
            orderOut(nil)
            onFinish(points)
        } else {
            updateHint()
        }
    }

    private final class ClickView: NSView {
        var onClick: ((CGPoint) -> Void)?
        override func mouseDown(with event: NSEvent) {
            onClick?(NSEvent.mouseLocation)
        }
    }
}
