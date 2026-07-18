import AppKit

// Draws a badge (rank + win%) and a calibration border directly over each shop
// slot, so per-card info is visible on the board itself without hovering.
// Timer-driven like HUDWindow — Combine @Published bindings from panels proved
// unreliable earlier in this project.
final class OverlayViewController: NSViewController {

    private var slotViews: [SlotBadgeView] = []
    private var timer: Timer?

    // Shows the coloured slot border so misalignment is immediately visible.
    // Toggle from the menu bar ("位置校準框").
    var showDebugFrames = true

    // MARK: – Lifecycle

    override func loadView() {
        let v = NSView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        v.layer?.backgroundColor = CGColor.clear
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for _ in 0..<7 {
            let sv = SlotBadgeView(frame: .zero)
            sv.isHidden = true
            view.addSubview(sv)
            slotViews.append(sv)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    // MARK: – Refresh

    @MainActor
    private func refresh() {
        slotViews.forEach { $0.isHidden = true }
        guard let rec = GameStateTracker.shared.recommendation else { return }

        let screenH = view.window?.screen?.frame.height
            ?? NSScreen.main?.frame.height ?? 1080

        // allPicks is ranked best-first.
        for (rank, pick) in rec.allPicks.enumerated() {
            guard rank < slotViews.count else { break }
            let sv = slotViews[rank]

            // Global top-left region → AppKit bottom-left, extended upward so
            // the badge strip sits above the card instead of covering it.
            let slot = pick.shopSlotRegion
            let badgeH: CGFloat = 26
            sv.frame = NSRect(
                x: slot.minX,
                y: screenH - slot.maxY,
                width: slot.width,
                height: slot.height + badgeH
            )
            sv.configure(rank: rank + 1, pick: pick,
                         badgeHeight: badgeH, showFrame: showDebugFrames)
            sv.isHidden = false
        }
    }
}

// MARK: – Per-slot badge

final class SlotBadgeView: NSView {

    private let borderView = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        borderView.wantsLayer = true
        borderView.layer?.borderWidth = 2.5
        borderView.layer?.cornerRadius = 10
        addSubview(borderView)

        label.font = .boldSystemFont(ofSize: 14)
        label.alignment = .center
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.cornerRadius = 7
        label.layer?.masksToBounds = true
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(rank: Int, pick: Recommendation,
                   badgeHeight: CGFloat, showFrame: Bool) {
        let (r, g, b) = pick.tier.color
        let tierColor = NSColor(red: r, green: g, blue: b, alpha: 1)

        let marker = rank == 1 ? "⭐" : "\(rank)"
        label.stringValue = "\(marker) \(pick.winRatePercent)%"
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        label.textColor = tierColor

        borderView.layer?.borderColor = tierColor
            .withAlphaComponent(showFrame ? 0.9 : 0.0).cgColor

        // Manual layout (frame-based): border wraps the card region below,
        // the badge strip sits on top.
        borderView.frame = NSRect(x: 0, y: 0,
                                  width: bounds.width,
                                  height: max(0, bounds.height - badgeHeight - 2))
        let labelW = min(bounds.width, 86)
        label.frame = NSRect(x: (bounds.width - labelW) / 2,
                             y: bounds.height - badgeHeight,
                             width: labelW,
                             height: badgeHeight - 2)
    }
}
