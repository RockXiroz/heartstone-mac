import AppKit

// Small always-visible HUD showing status and the current recommendation.
// Positioned at the top-right corner so it never blocks the game board.
final class HUDWindow: NSPanel {

    // MARK: – Subviews (frame-based, no Auto Layout)

    private let statusLabel  = NSTextField()
    private let cardLabel    = NSTextField()
    private let winRateLabel = NSTextField()
    private let divider      = NSBox()
    private let reasonLabels = (0..<3).map { _ in NSTextField() }
    private let freezeLabel  = NSTextField()

    private var refreshTimer: Timer?

    // MARK: – Init

    init(screen: NSScreen) {
        let w: CGFloat = 340
        let h: CGFloat = 220
        let x = screen.visibleFrame.maxX - w - 12
        let y = screen.visibleFrame.maxY - h - 4

        super.init(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level               = .screenSaver
        backgroundColor     = NSColor(white: 0.08, alpha: 0.92)
        isOpaque            = false
        hasShadow           = true
        isReleasedWhenClosed = false
        ignoresMouseEvents  = false
        isMovableByWindowBackground = true
        collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        buildLayout()
        orderFrontRegardless()
        startTimer()
    }

    // MARK: – Layout

    private func buildLayout() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.cornerRadius  = 12
        cv.layer?.masksToBounds = true

        let W = cv.bounds.width
        var y = cv.bounds.height

        y -= 32
        configure(statusLabel, size: 11, color: NSColor(white: 0.55, alpha: 1))
        statusLabel.frame = NSRect(x: 12, y: y, width: W - 24, height: 18)
        cv.addSubview(statusLabel)

        y -= 8
        divider.boxType = .separator
        divider.frame   = NSRect(x: 8, y: y, width: W - 16, height: 1)
        cv.addSubview(divider)

        y -= 28
        configure(cardLabel, size: 15, color: .white, bold: true)
        cardLabel.frame = NSRect(x: 12, y: y, width: W - 90, height: 22)
        cv.addSubview(cardLabel)

        configure(winRateLabel, size: 15, color: .systemGreen, bold: true)
        winRateLabel.alignment = .right
        winRateLabel.frame = NSRect(x: W - 86, y: y, width: 74, height: 22)
        cv.addSubview(winRateLabel)

        for label in reasonLabels {
            y -= 22
            configure(label, size: 12, color: NSColor(white: 0.82, alpha: 1))
            label.frame = NSRect(x: 12, y: y, width: W - 24, height: 18)
            cv.addSubview(label)
        }

        y -= 22
        configure(freezeLabel, size: 11, color: .systemCyan)
        freezeLabel.frame = NSRect(x: 12, y: y, width: W - 24, height: 18)
        freezeLabel.isHidden = true
        cv.addSubview(freezeLabel)

        statusLabel.stringValue  = "⏳ 啟動中…"
        cardLabel.stringValue    = "—"
        winRateLabel.stringValue = ""
    }

    private func configure(_ f: NSTextField, size: CGFloat,
                            color: NSColor, bold: Bool = false) {
        f.isBezeled       = false
        f.isEditable      = false
        f.drawsBackground = false
        f.textColor       = color
        f.font            = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        f.lineBreakMode   = .byTruncatingTail
    }

    // MARK: – Timer-based refresh (avoids Combine actor-isolation subtleties)

    private func startTimer() {
        // 0.15s keeps hover feedback responsive; the Task hops to @MainActor.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    @MainActor
    private func refresh() {
        let tracker = GameStateTracker.shared
        statusLabel.stringValue = tracker.statusMessage

        guard let rec = tracker.recommendation else {
            cardLabel.stringValue    = "—"
            winRateLabel.stringValue = ""
            reasonLabels.forEach { $0.stringValue = "" }
            freezeLabel.isHidden = true
            return
        }

        // Hovering a shop card shows that card's analysis; otherwise the best pick.
        let hovered = hoveredPick(in: rec)
        let shown   = hovered ?? rec.bestPick
        let isBest  = shown.shopSlotIndex == rec.bestPick.shopSlotIndex

        let (r, g, b) = shown.tier.color
        let prefix = hovered != nil ? "👉 " : ""
        let star   = isBest ? " ⭐" : ""
        cardLabel.stringValue    = "\(prefix)\(shown.card.name)\(star)"
        winRateLabel.stringValue = "\(shown.winRatePercent)%"
        winRateLabel.textColor   = NSColor(red: r, green: g, blue: b, alpha: 1)

        for (i, label) in reasonLabels.enumerated() {
            label.stringValue = i < shown.topReasons.count
                ? "• \(shown.topReasons[i].text)" : ""
        }

        if rec.shouldFreeze, let reason = rec.freezeReason {
            freezeLabel.stringValue = "❄ \(reason)"
            freezeLabel.isHidden = false
        } else {
            freezeLabel.isHidden = true
        }
    }

    // Maps the global mouse position to a shop slot. Slot regions use global
    // top-left origin (CGWindow coords); NSEvent.mouseLocation uses bottom-left
    // origin relative to the primary screen — flip against the primary height.
    @MainActor
    private func hoveredPick(in rec: ShopRecommendation) -> Recommendation? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
        let mouse = NSEvent.mouseLocation

        return rec.allPicks.first { pick in
            let slot = pick.shopSlotRegion
            let flipped = NSRect(
                x: slot.minX,
                y: primaryHeight - slot.maxY,
                width: slot.width,
                height: slot.height
            ).insetBy(dx: -8, dy: -20)   // generous margin: geometry is approximate
            return flipped.contains(mouse)
        }
    }

    deinit { refreshTimer?.invalidate() }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
