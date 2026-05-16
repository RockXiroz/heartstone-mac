import AppKit
import Combine

// Manages all arrow indicators and the recommendation panel inside the overlay window.
final class OverlayViewController: NSViewController {

    private let tracker = GameStateTracker.shared
    private var cancellables = Set<AnyCancellable>()

    // One ArrowIndicatorView per shop slot (max 7)
    private var arrows: [Int: ArrowIndicatorView] = [:]
    // One tooltip that moves to the best slot
    private let tooltip = ReasonTooltipView(frame: .zero)
    // Status bar at top of overlay
    private let statusBar = OverlayStatusBar()

    private let maxSlots = 7

    // MARK: – Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSlots()
        setupTooltip()
        setupStatusBar()
        bindTracker()
    }

    // MARK: – Setup

    private func setupSlots() {
        for i in 0..<maxSlots {
            let arrow = ArrowIndicatorView(frame: .zero)
            arrow.isHidden = true
            view.addSubview(arrow)
            arrows[i] = arrow
        }
    }

    private func setupTooltip() {
        tooltip.isHidden = true
        view.addSubview(tooltip)
    }

    private func setupStatusBar() {
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)
        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            statusBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28),
            statusBar.widthAnchor.constraint(lessThanOrEqualToConstant: 600)
        ])
    }

    // MARK: – Data binding

    private func bindTracker() {
        tracker.$recommendation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rec in self?.applyRecommendation(rec) }
            .store(in: &cancellables)

        tracker.$statusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in self?.statusBar.update(message: msg) }
            .store(in: &cancellables)

        tracker.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processing in self?.statusBar.setSpinner(active: processing) }
            .store(in: &cancellables)
    }

    // MARK: – Recommendation rendering

    private func applyRecommendation(_ shopRec: ShopRecommendation?) {
        // Hide all arrows first
        arrows.values.forEach { $0.isHidden = true }
        tooltip.isHidden = true

        guard let shopRec else { return }

        let viewBounds = view.bounds

        // Position each arrow above its slot
        for pick in shopRec.allPicks {
            guard let arrow = arrows[pick.shopSlotIndex] else { continue }
            let slotRect = normalise(rect: pick.shopSlotRegion, to: viewBounds)
            // Arrow sits in the upper portion of the card slot
            let arrowRect = CGRect(
                x: slotRect.midX - 32,
                y: slotRect.minY - 90,
                width: 64,
                height: 80
            )
            arrow.frame = arrowRect
            arrow.recommendation = pick
            arrow.isHidden = (pick.tier == .skip)
        }

        // Show tooltip above the best pick
        let best = shopRec.bestPick
        let bestSlot = normalise(rect: best.shopSlotRegion, to: viewBounds)
        let tooltipW: CGFloat = 260, tooltipH: CGFloat = 180
        let tooltipX = min(max(bestSlot.midX - tooltipW/2, 8), viewBounds.width - tooltipW - 8)
        let tooltipY = bestSlot.minY - tooltipH - 100

        tooltip.frame = CGRect(x: tooltipX, y: max(tooltipY, 8), width: tooltipW, height: tooltipH)
        tooltip.configure(with: best)
        tooltip.isHidden = false

        // Freeze suggestion badge
        if shopRec.shouldFreeze, let freezeReason = shopRec.freezeReason {
            statusBar.showFreezeSuggestion(freezeReason)
        }
    }

    // MARK: – Coordinate helpers

    // Convert from Hearthstone window coords → overlay view coords (same space after window tracking)
    private func normalise(rect: CGRect, to bounds: CGRect) -> CGRect {
        // Both overlay and HS window have the same frame; coords are 1:1
        // Flip Y axis: CGRect origin is bottom-left in AppKit, top-left in our tracking
        return CGRect(
            x: rect.minX,
            y: bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

// MARK: – Status Bar

final class OverlayStatusBar: NSView {

    private let label    = NSTextField(labelWithString: "爐石英雄戰場助手")
    private let spinner  = NSProgressIndicator()
    private let freezeBadge = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.70).cgColor
        layer?.cornerRadius = 8

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true

        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center

        freezeBadge.font = NSFont.systemFont(ofSize: 11)
        freezeBadge.textColor = NSColor.systemCyan
        freezeBadge.isHidden = true

        [spinner, label, freezeBadge].forEach {
            ($0 as! NSView).translatesAutoresizingMaskIntoConstraints = false
            addSubview($0 as! NSView)
        }
        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            freezeBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            freezeBadge.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(message: String) { label.stringValue = message }
    func setSpinner(active: Bool) {
        spinner.isHidden = !active
        if active { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
    func showFreezeSuggestion(_ text: String) {
        freezeBadge.stringValue = "❄ \(text)"
        freezeBadge.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.freezeBadge.isHidden = true
        }
    }
}
