import AppKit
import Combine

// Draws arrow indicators directly over each shop slot.
// The HUDWindow handles the recommendation text / status.
final class OverlayViewController: NSViewController {

    private let tracker = GameStateTracker.shared
    private var cancellables = Set<AnyCancellable>()
    private var arrows: [Int: ArrowIndicatorView] = [:]
    private let maxSlots = 7

    // MARK: – Lifecycle

    override func loadView() {
        // autoresizingMask fills the window without Auto Layout
        let v = NSView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        v.layer?.backgroundColor = CGColor.clear
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for i in 0..<maxSlots {
            let arrow = ArrowIndicatorView(frame: .zero)
            arrow.isHidden = true
            view.addSubview(arrow)
            arrows[i] = arrow
        }
        tracker.$recommendation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rec in self?.apply(rec) }
            .store(in: &cancellables)
    }

    // MARK: – Arrows

    private func apply(_ rec: ShopRecommendation?) {
        arrows.values.forEach { $0.isHidden = true }
        guard let rec else { return }
        let h = view.bounds.height

        for pick in rec.allPicks where pick.tier != .skip {
            guard let arrow = arrows[pick.shopSlotIndex] else { continue }
            let slot = pick.shopSlotRegion
            // Convert from top-left origin (SCCapture) → AppKit bottom-left origin
            let arrowFrame = CGRect(
                x: slot.midX - 32,
                y: h - slot.minY - 80 - 90,
                width: 64,
                height: 80
            )
            arrow.frame = arrowFrame
            arrow.recommendation = pick
            arrow.isHidden = false
        }
    }
}
