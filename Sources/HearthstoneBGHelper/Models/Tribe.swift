import Foundation

enum Tribe: String, Codable, CaseIterable, Hashable {
    case beast     = "Beast"
    case demon     = "Demon"
    case dragon    = "Dragon"
    case elemental = "Elemental"
    case mech      = "Mech"
    case murloc    = "Murloc"
    case naga      = "Naga"
    case pirate    = "Pirate"
    case quilboar  = "Quilboar"
    case undead    = "Undead"
    case titan     = "Titan"
    case neutral   = "Neutral"

    var displayName: String { rawValue }

    // Determines whether a tribe is typically "scaling" (grows power over turns)
    var isScaling: Bool {
        switch self {
        case .undead, .naga, .quilboar, .elemental: return true
        default: return false
        }
    }

    // Typical tribe synergy threshold (need N minions of this tribe for bonus)
    var synergyThreshold: Int {
        switch self {
        case .murloc: return 3
        case .mech: return 3
        case .quilboar: return 2
        default: return 3
        }
    }
}

// Represents the tribe pool for the current game session (5 of 11 tribes active)
struct ActiveTribePool {
    let tribes: Set<Tribe>

    static let full = ActiveTribePool(tribes: Set(Tribe.allCases))

    func contains(_ tribe: Tribe) -> Bool {
        tribe == .neutral || tribes.contains(tribe)
    }

    // How many of the supplied minions belong to active tribes
    func activeTribeCount(in cards: [Card]) -> Int {
        cards.filter { $0.tribes.contains(where: { contains($0) && $0 != .neutral }) }.count
    }
}
