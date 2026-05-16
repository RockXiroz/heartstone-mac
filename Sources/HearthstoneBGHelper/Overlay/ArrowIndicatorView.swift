import AppKit
import QuartzCore

// Renders an animated bouncing arrow + win-rate badge above a shop slot.
final class ArrowIndicatorView: NSView {

    private let arrowLayer   = CAShapeLayer()
    private let badgeLayer   = CALayer()
    private let percentLabel = CATextLayer()
    private let tierLabel    = CATextLayer()

    private var bounceTimer: Timer?

    var recommendation: Recommendation? { didSet { update() } }

    // MARK: – Setup

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        setupArrow()
        setupBadge()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupArrow() {
        arrowLayer.lineWidth  = 4
        arrowLayer.fillColor  = NSColor.systemGreen.cgColor
        arrowLayer.strokeColor = NSColor.white.cgColor
        layer?.addSublayer(arrowLayer)
    }

    private func setupBadge() {
        badgeLayer.cornerRadius = 8
        badgeLayer.masksToBounds = true
        layer?.addSublayer(badgeLayer)

        percentLabel.fontSize  = 16
        percentLabel.fontName  = "AvenirNext-Bold"
        percentLabel.foregroundColor = CGColor.white
        percentLabel.alignmentMode  = .center
        percentLabel.contentsScale  = 2
        badgeLayer.addSublayer(percentLabel)

        tierLabel.fontSize  = 11
        tierLabel.fontName  = "AvenirNext-Medium"
        tierLabel.foregroundColor = CGColor.white
        tierLabel.alignmentMode  = .center
        tierLabel.contentsScale  = 2
        badgeLayer.addSublayer(tierLabel)
    }

    // MARK: – Update

    private func update() {
        guard let rec = recommendation else {
            isHidden = true
            stopBounce()
            return
        }
        isHidden = false

        let (r, g, b) = rec.tier.color
        let color = NSColor(red: r, green: g, blue: b, alpha: 1).cgColor

        // Draw downward-pointing arrow centred in the view
        let arrowPath = NSBezierPath()
        let cx = bounds.midX
        let top: CGFloat = 8
        let shaft = bounds.height * 0.45
        let headH = bounds.height * 0.35
        let headW: CGFloat = 28

        arrowPath.move(to: NSPoint(x: cx - 8, y: top))
        arrowPath.line(to: NSPoint(x: cx + 8, y: top))
        arrowPath.line(to: NSPoint(x: cx + 8, y: top + shaft))
        arrowPath.line(to: NSPoint(x: cx + headW, y: top + shaft))
        arrowPath.line(to: NSPoint(x: cx, y: top + shaft + headH))
        arrowPath.line(to: NSPoint(x: cx - headW, y: top + shaft))
        arrowPath.line(to: NSPoint(x: cx - 8, y: top + shaft))
        arrowPath.close()

        arrowLayer.path        = arrowPath.cgPath
        arrowLayer.fillColor   = color
        arrowLayer.strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor

        // Badge
        let badgeW: CGFloat = 72, badgeH: CGFloat = 36
        let badgeRect = CGRect(x: cx - badgeW/2, y: bounds.height - badgeH - 2, width: badgeW, height: badgeH)
        badgeLayer.frame = badgeRect
        badgeLayer.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor

        percentLabel.frame  = CGRect(x: 0, y: badgeH/2 - 2, width: badgeW, height: badgeH/2)
        percentLabel.string = "\(rec.winRatePercent)%"

        tierLabel.frame  = CGRect(x: 0, y: 2, width: badgeW, height: badgeH/2)
        tierLabel.string = rec.tier.rawValue
        let (tr, tg, tb) = rec.tier.color
        tierLabel.foregroundColor = NSColor(red: tr, green: tg, blue: tb, alpha: 1).cgColor

        startBounce()
    }

    // MARK: – Animation

    private func startBounce() {
        stopBounce()
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = 0
        bounce.toValue   = -10
        bounce.duration  = 0.55
        bounce.autoreverses = true
        bounce.repeatCount  = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arrowLayer.add(bounce, forKey: "bounce")

        // Gentle pulse on the badge
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.85
        pulse.toValue   = 1.0
        pulse.duration  = 0.55
        pulse.autoreverses = true
        pulse.repeatCount  = .infinity
        badgeLayer.add(pulse, forKey: "pulse")
    }

    private func stopBounce() {
        arrowLayer.removeAnimation(forKey: "bounce")
        badgeLayer.removeAnimation(forKey: "pulse")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopBounce() }
    }
}

// MARK: – Reason tooltip popup

final class ReasonTooltipView: NSView {

    private let stackView = NSStackView()
    private let cardNameLabel = NSTextField(labelWithString: "")
    private let divider = NSBox()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth  = 1
        layer?.borderColor  = NSColor.white.withAlphaComponent(0.15).cgColor

        cardNameLabel.font = NSFont.boldSystemFont(ofSize: 14)
        cardNameLabel.textColor = .white
        cardNameLabel.alignment = .center

        divider.boxType = .separator

        stackView.orientation  = .vertical
        stackView.spacing      = 6
        stackView.edgeInsets   = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stackView.addArrangedSubview(cardNameLabel)
        stackView.addArrangedSubview(divider)
    }

    func configure(with recommendation: Recommendation) {
        // Remove old reason rows
        stackView.arrangedSubviews.dropFirst(2).forEach { $0.removeFromSuperview() }

        cardNameLabel.stringValue = recommendation.card.name

        for reason in recommendation.topReasons {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6

            let iconLabel = NSTextField(labelWithString: sfSymbol(reason.icon))
            iconLabel.font = NSFont.systemFont(ofSize: 13)
            iconLabel.textColor = .white

            let textLabel = NSTextField(wrappingLabelWithString: reason.text)
            textLabel.font = NSFont.systemFont(ofSize: 12)
            textLabel.textColor = NSColor(white: 0.9, alpha: 1)
            textLabel.lineBreakMode = .byWordWrapping

            row.addArrangedSubview(iconLabel)
            row.addArrangedSubview(textLabel)
            stackView.addArrangedSubview(row)
        }

        // Alternatives section
        if let altText = recommendation.card.cardText {
            let cardText = NSTextField(wrappingLabelWithString: "「\(altText)」")
            cardText.font = NSFont.systemFont(ofSize: 11)
            cardText.textColor = NSColor(white: 0.65, alpha: 1)
            cardText.lineBreakMode = .byWordWrapping
            stackView.addArrangedSubview(cardText)
        }

        let winRateRow = NSTextField(labelWithString: "綜合勝率評分：\(recommendation.winRatePercent)%")
        winRateRow.font = NSFont.boldSystemFont(ofSize: 13)
        let (r, g, b) = recommendation.tier.color
        winRateRow.textColor = NSColor(red: r, green: g, blue: b, alpha: 1)
        winRateRow.alignment = .center
        stackView.addArrangedSubview(winRateRow)
    }

    // Minimal SF Symbol → Unicode fallback for text rendering
    private func sfSymbol(_ name: String) -> String {
        switch name {
        case "chart.bar.fill":           return "📊"
        case "star.fill":                return "⭐"
        case "3.circle.fill":            return "3️⃣"
        case "arrow.up.right.circle.fill": return "📈"
        case "shield.lefthalf.filled":   return "🛡"
        case "exclamationmark.triangle.fill": return "⚠️"
        case "crown.fill":               return "👑"
        default:                         return "•"
        }
    }
}

// Allow Card.cardText to be optional in the tooltip
private extension Card {
    var cardText: String? { text.isEmpty ? nil : text }
}
