import AppKit
import Combine

// Small always-visible HUD that shows status and the current recommendation.
// Positioned at the top-right corner so it never blocks the game board.
final class HUDWindow: NSPanel {

    // MARK: – Subviews

    private let statusLabel   = NSTextField()
    private let cardLabel     = NSTextField()
    private let winRateLabel  = NSTextField()
    private let divider       = NSBox()
    private let reasonLabels  = (0..<3).map { _ in NSTextField() }
    private let freezeLabel   = NSTextField()

    private var tracker: GameStateTracker { GameStateTracker.shared }
    private var cancellables  = Set<AnyCancellable>()

    // MARK: – Init

    init(screen: NSScreen) {
        let w: CGFloat = 340
        let h: CGFloat = 220
        // Top-right corner, 12 pt inset from screen edge, below menu bar
        let x = screen.visibleFrame.maxX - w - 12
        let y = screen.visibleFrame.maxY - h - 4

        super.init(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level              = .screenSaver
        backgroundColor    = NSColor(white: 0.08, alpha: 0.92)
        isOpaque           = false
        hasShadow          = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = false           // allow dragging
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        setupContent()
        bind()
        orderFrontRegardless()
    }

    // MARK: – Layout (frame-based, no Auto Layout)

    private func setupContent() {
        guard let cv = contentView else { return }

        // Corner radius via layer
        cv.wantsLayer  = true
        cv.layer?.cornerRadius  = 12
        cv.layer?.masksToBounds = true

        let W = cv.bounds.width
        var y  = cv.bounds.height   // we'll walk down from the top

        // ── Status row ──────────────────────────────────────────────
        y -= 32
        style(statusLabel, size: 11, color: NSColor(white: 0.6, alpha: 1))
        statusLabel.frame = NSRect(x: 12, y: y, width: W - 24, height: 18)
        cv.addSubview(statusLabel)

        // ── Divider ─────────────────────────────────────────────────
        y -= 6
        divider.boxType = .separator
        divider.frame   = NSRect(x: 8, y: y, width: W - 16, height: 1)
        cv.addSubview(divider)
        y -= 6

        // ── Card name + win-rate ─────────────────────────────────────
        y -= 24
        style(cardLabel, size: 15, color: .white, bold: true)
        cardLabel.frame = NSRect(x: 12, y: y, width: W - 90, height: 20)
        cv.addSubview(cardLabel)

        style(winRateLabel, size: 15, color: NSColor.systemGreen, bold: true)
        winRateLabel.alignment = .right
        winRateLabel.frame = NSRect(x: W - 86, y: y, width: 74, height: 20)
        cv.addSubview(winRateLabel)

        // ── Reason rows ──────────────────────────────────────────────
        for label in reasonLabels {
            y -= 20
            style(label, size: 12, color: NSColor(white: 0.85, alpha: 1))
            label.frame = NSRect(x: 12, y: y, width: W - 24, height: 16)
            cv.addSubview(label)
        }

        // ── Freeze suggestion ────────────────────────────────────────
        y -= 22
        style(freezeLabel, size: 11, color: NSColor.systemCyan)
        freezeLabel.frame = NSRect(x: 12, y: y, width: W - 24, height: 16)
        freezeLabel.isHidden = true
        cv.addSubview(freezeLabel)

        // Default status
        statusLabel.stringValue  = "⏳ 等待遊戲畫面…"
        cardLabel.stringValue    = "—"
        winRateLabel.stringValue = ""
    }

    private func style(
        _ f: NSTextField, size: CGFloat, color: NSColor,
        bold: Bool = false
    ) {
        f.isBezeled   = false
        f.isEditable  = false
        f.drawsBackground = false
        f.textColor   = color
        f.font        = bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
        f.lineBreakMode = .byTruncatingTail
    }

    // MARK: – Combine bindings

    private func bind() {
        tracker.$statusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in self?.statusLabel.stringValue = msg }
            .store(in: &cancellables)

        tracker.$recommendation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rec in self?.apply(rec) }
            .store(in: &cancellables)
    }

    private func apply(_ rec: ShopRecommendation?) {
        guard let rec else {
            cardLabel.stringValue    = "—"
            winRateLabel.stringValue = ""
            reasonLabels.forEach { $0.stringValue = "" }
            freezeLabel.isHidden = true
            return
        }
        let best = rec.bestPick
        let (r, g, b) = best.tier.color
        cardLabel.stringValue    = best.card.name
        winRateLabel.stringValue = "\(best.winRatePercent)%"
        winRateLabel.textColor   = NSColor(red: r, green: g, blue: b, alpha: 1)

        let reasons = best.topReasons
        for (i, label) in reasonLabels.enumerated() {
            label.stringValue = i < reasons.count ? "• \(reasons[i].text)" : ""
        }

        if rec.shouldFreeze, let reason = rec.freezeReason {
            freezeLabel.stringValue = "❄ \(reason)"
            freezeLabel.isHidden = false
        } else {
            freezeLabel.isHidden = true
        }
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
