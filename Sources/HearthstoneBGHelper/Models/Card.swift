import Foundation

struct Card: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let tribes: [Tribe]
    let tavernTier: Int
    let attack: Int
    let health: Int
    let keywords: [Keyword]
    let text: String
    var synergyTags: [SynergyTag]

    var primaryTribe: Tribe { tribes.first ?? .neutral }

    // Base win-rate contribution from HSReplay data (0.0–1.0)
    // Updated dynamically from API; fallback baked in here
    var baseWinRate: Double

    // Average placement when this card is purchased (lower is better, 1–8 scale)
    var avgPlacement: Double

    enum Keyword: String, Codable, Hashable {
        case reborn          = "Reborn"
        case divineShield    = "Divine Shield"
        case taunt           = "Taunt"
        case poisonous       = "Poisonous"
        case windfury        = "Windfury"
        case megaWindfury    = "Mega-Windfury"
        case cleave          = "Cleave"
        case deathrattle     = "Deathrattle"
        case battlecry       = "Battlecry"
        case endOfTurn       = "End of Turn"
        case startOfCombat   = "Start of Combat"
        case magnetize       = "Magnetize"
        case avenge          = "Avenge"
        case venomous        = "Venomous"
    }

    enum SynergyTag: String, Codable, Hashable {
        // Tribe enablers
        case undeadDeathrattle = "undead_deathrattle"
        case beastBuff         = "beast_buff"
        case mechMagnetize     = "mech_magnetize"
        case murloc            = "murloc_buff"
        case nagaSpell         = "naga_spell"
        case quilboarGem       = "quilboar_gem"
        case dragonHold        = "dragon_hold"
        case pirateCoin        = "pirate_coin"
        case demonSelf         = "demon_self_damage"
        case elementalPlayedLast = "elemental_chain"

        // Universal synergies
        case divineShieldGenerator = "divine_shield_gen"
        case statBuffer            = "stat_buffer"
        case reborner              = "give_reborn"
        case tauntProvider         = "give_taunt"
        case tripleWorthy          = "triple_worthy"
        case lateBoardCap          = "late_board_cap"
        case economyValue          = "economy_value"
    }

    static func == (lhs: Card, rhs: Card) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Card {
    // Minimal stand-in for a card ID not yet in the database, so the shop can
    // still be shown while the full card list downloads.
    static func placeholder(id: String) -> Card {
        Card(id: id, name: id, tribes: [.neutral], tavernTier: 1,
             attack: 0, health: 0, keywords: [], text: "",
             synergyTags: [], baseWinRate: 0.5, avgPlacement: 4.0)
    }

    var hasKeyword: (Card.Keyword) -> Bool {
        { [keywords] kw in keywords.contains(kw) }
    }

    // Defensive value score: divine shield + reborn + taunt
    var defensiveScore: Double {
        var score = 0.0
        if keywords.contains(.divineShield) { score += 2.0 }
        if keywords.contains(.reborn)       { score += 1.5 }
        if keywords.contains(.taunt)        { score += 1.0 }
        if keywords.contains(.poisonous) || keywords.contains(.venomous) { score += 2.5 }
        return score
    }

    // Offensive value score: windfury + cleave + attack
    var offensiveScore: Double {
        var score = Double(attack) * 0.5
        if keywords.contains(.megaWindfury) { score += 4.0 }
        if keywords.contains(.windfury)     { score += 2.0 }
        if keywords.contains(.cleave)       { score += 1.5 }
        return score
    }

    // How much this card scales with more copies / turns
    var scalingPotential: Double {
        var score = 0.0
        if keywords.contains(.endOfTurn)   { score += 2.0 }
        if keywords.contains(.deathrattle) { score += 1.5 }
        if keywords.contains(.reborn)      { score += 1.0 }
        synergyTags.forEach { tag in
            switch tag {
            case .undeadDeathrattle, .nagaSpell, .quilboarGem, .elementalPlayedLast:
                score += 2.0
            case .statBuffer, .divineShieldGenerator:
                score += 1.5
            default: break
            }
        }
        return score
    }
}
