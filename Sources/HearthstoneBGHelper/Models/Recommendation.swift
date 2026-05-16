import Foundation
import CoreGraphics

// A single purchase recommendation for one shop slot
struct Recommendation: Identifiable {
    let id = UUID()
    let card: Card
    let shopSlotIndex: Int
    let shopSlotRegion: CGRect     // screen rect in game window coords
    let winRateScore: Double       // composite 0.0–1.0
    let reasons: [ReasonItem]
    let tier: Tier

    enum Tier: String {
        case mustBuy   = "Must Buy"    // > 0.75
        case goodBuy   = "Good Buy"    // 0.55–0.75
        case situational = "Situational" // 0.40–0.55
        case skip      = "Skip"        // < 0.40

        var color: (red: Double, green: Double, blue: Double) {
            switch self {
            case .mustBuy:    return (0.1, 0.9, 0.2)
            case .goodBuy:    return (0.5, 0.9, 0.1)
            case .situational: return (1.0, 0.7, 0.0)
            case .skip:       return (0.9, 0.2, 0.1)
            }
        }

        static func from(score: Double) -> Tier {
            switch score {
            case 0.75...: return .mustBuy
            case 0.55..<0.75: return .goodBuy
            case 0.40..<0.55: return .situational
            default: return .skip
            }
        }
    }

    struct ReasonItem: Identifiable {
        let id = UUID()
        let icon: String       // SF Symbol name
        let text: String
        let weight: Double     // contribution to total score
    }

    var winRatePercent: Int { Int((winRateScore * 100).rounded()) }

    // The top-3 reasons sorted by weight
    var topReasons: [ReasonItem] {
        Array(reasons.sorted { $0.weight > $1.weight }.prefix(3))
    }
}

// Full set of recommendations for one shop state
struct ShopRecommendation {
    let bestPick: Recommendation          // highest scoring slot
    let allPicks: [Recommendation]        // all slots ranked
    let shouldFreeze: Bool                // freeze the shop next turn?
    let freezeReason: String?
    let alternativePlays: [String]        // e.g., "Sell X and buy Y"
    let generatedAt: Date

    // Recommendation for each slot, keyed by slot index
    var bySlot: [Int: Recommendation] {
        Dictionary(uniqueKeysWithValues: allPicks.map { ($0.shopSlotIndex, $0) })
    }
}
