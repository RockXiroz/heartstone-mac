import Foundation

// In-memory card database.  Loaded once at startup from the bundled JSON.
// Fuzzy name matching handles minor OCR errors.
final class CardDatabase {

    static let shared = CardDatabase()

    private var cards: [String: Card] = [:]   // id → Card
    private var byName: [String: Card] = [:]  // lowercased name → Card

    init() { load() }

    func findCard(byID id: String) -> Card? { cards[id] }

    func findCard(named name: String) -> Card? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = byName[key] { return exact }
        // Fuzzy: return best Levenshtein match within distance 2
        return byName.min(by: { levenshtein($0.key, key) < levenshtein($1.key, key) })
            .flatMap { levenshtein($0.key, key) <= 2 ? $0.value : nil }
    }

    var allCards: [Card] { Array(cards.values) }
    var count: Int { cards.count }

    // Merge remotely fetched cards (HearthstoneJSON). Remote entries win over
    // the small bundled bootstrap set, except curated synergy tags and win-rate
    // priors are kept when the remote copy has none.
    func merge(_ remote: [Card]) {
        for var card in remote {
            if let existing = cards[card.id] {
                if card.synergyTags.isEmpty { card.synergyTags = existing.synergyTags }
                card.baseWinRate  = existing.baseWinRate
                card.avgPlacement = existing.avgPlacement
            }
            register(card)
        }
    }

    // MARK: – Loading

    private func load() {
        guard let url = Bundle.module.url(forResource: "BattlegroundsCards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CardJSON].self, from: data) else {
            loadHardcoded()
            return
        }
        for c in decoded { register(c.toCard()) }
    }

    private func register(_ card: Card) {
        cards[card.id] = card
        byName[card.name.lowercased()] = card
    }

    // MARK: – Fuzzy match

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]; dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                dp[j] = a[i-1] == b[j-1] ? prev : 1 + min(prev, min(dp[j], dp[j-1]))
                prev = temp
            }
        }
        return dp[b.count]
    }

    // MARK: – Hardcoded fallback (key meta cards)

    private func loadHardcoded() {
        let fallback: [Card] = [
            // ── Undead ──────────────────────────────────────────────
            Card(id: "BG26_055", name: "Voidlord",
                 tribes: [.demon], tavernTier: 5,
                 attack: 3, health: 9, keywords: [.taunt, .deathrattle],
                 text: "Taunt. Deathrattle: Summon three 1/3 Voidwalkers with Taunt.",
                 synergyTags: [.undeadDeathrattle], baseWinRate: 0.55, avgPlacement: 3.2),

            Card(id: "BG26_GIL_513", name: "Ghoul of the Feast",
                 tribes: [.undead], tavernTier: 2,
                 attack: 3, health: 2, keywords: [.deathrattle],
                 text: "Deathrattle: Give a friendly minion +3/+3.",
                 synergyTags: [.undeadDeathrattle, .statBuffer], baseWinRate: 0.52, avgPlacement: 3.5),

            Card(id: "BG26_812", name: "Rotting Idol",
                 tribes: [.undead], tavernTier: 3,
                 attack: 2, health: 4, keywords: [.reborn, .taunt],
                 text: "At the end of your turn, give your other Undead minions +1/+1.",
                 synergyTags: [.undeadDeathrattle, .statBuffer], baseWinRate: 0.58, avgPlacement: 3.1),

            Card(id: "BG28_964", name: "Bran Bronzebeard",
                 tribes: [.neutral], tavernTier: 5,
                 attack: 2, health: 4, keywords: [.battlecry],
                 text: "Your Battlecries trigger twice.",
                 synergyTags: [.tripleWorthy, .economyValue], baseWinRate: 0.62, avgPlacement: 2.8),

            // ── Naga ─────────────────────────────────────────────────
            Card(id: "BG26_157", name: "Amalgadon",
                 tribes: [.neutral], tavernTier: 6,
                 attack: 0, health: 0, keywords: [.battlecry],
                 text: "Battlecry: For each different minion type you have, gain a random bonus.",
                 synergyTags: [.tripleWorthy, .lateBoardCap], baseWinRate: 0.60, avgPlacement: 2.9),

            Card(id: "BG26_521", name: "Scale of Onyxia",
                 tribes: [.naga], tavernTier: 4,
                 attack: 4, health: 4, keywords: [.divineShield, .deathrattle],
                 text: "Deathrattle: Deal 4 damage to all minions.",
                 synergyTags: [.nagaSpell, .divineShieldGenerator], baseWinRate: 0.56, avgPlacement: 3.2),

            Card(id: "BG27_000", name: "Nami Dah",
                 tribes: [.naga], tavernTier: 3,
                 attack: 3, health: 5, keywords: [.startOfCombat],
                 text: "Start of Combat: Give your lowest-Attack Naga +3 Attack.",
                 synergyTags: [.nagaSpell, .statBuffer], baseWinRate: 0.54, avgPlacement: 3.4),

            // ── Quilboar ─────────────────────────────────────────────
            Card(id: "BG20_100", name: "Bristleback Knight",
                 tribes: [.quilboar], tavernTier: 2,
                 attack: 2, health: 6, keywords: [.divineShield],
                 text: "Whenever this loses Divine Shield, gain +1/+1.",
                 synergyTags: [.quilboarGem, .divineShieldGenerator], baseWinRate: 0.53, avgPlacement: 3.5),

            Card(id: "BG20_202", name: "Groundshaker",
                 tribes: [.quilboar], tavernTier: 4,
                 attack: 2, health: 6, keywords: [.deathrattle],
                 text: "Deathrattle: Give your Quilboar +2/+2.",
                 synergyTags: [.quilboarGem, .statBuffer], baseWinRate: 0.55, avgPlacement: 3.3),

            // ── Elemental ────────────────────────────────────────────
            Card(id: "BG21_012", name: "Sellemental",
                 tribes: [.elemental], tavernTier: 1,
                 attack: 1, health: 1, keywords: [],
                 text: "When you sell this, add a 1/1 Elemental to your hand.",
                 synergyTags: [.elementalPlayedLast, .economyValue], baseWinRate: 0.48, avgPlacement: 3.7),

            Card(id: "BG21_009", name: "Wildfire Elemental",
                 tribes: [.elemental], tavernTier: 5,
                 attack: 7, health: 4, keywords: [.startOfCombat],
                 text: "Start of Combat: Deal excess damage to neighbours.",
                 synergyTags: [.elementalPlayedLast, .lateBoardCap], baseWinRate: 0.59, avgPlacement: 3.1),

            // ── Mech ─────────────────────────────────────────────────
            Card(id: "GVG_103", name: "Screwjank Clunker",
                 tribes: [.mech], tavernTier: 3,
                 attack: 2, health: 5, keywords: [.battlecry, .magnetize],
                 text: "Battlecry: Give a friendly Mech +2/+2.",
                 synergyTags: [.mechMagnetize, .statBuffer], baseWinRate: 0.52, avgPlacement: 3.5),

            Card(id: "BG26_178", name: "Deflect-o-Bot",
                 tribes: [.mech], tavernTier: 3,
                 attack: 3, health: 3, keywords: [.divineShield, .magnetize],
                 text: "At the start of your turn, gain +1 Attack and Divine Shield.",
                 synergyTags: [.mechMagnetize, .divineShieldGenerator], baseWinRate: 0.57, avgPlacement: 3.2),

            // ── Murloc ────────────────────────────────────────────────
            Card(id: "ICC_075", name: "Primalfin Lookout",
                 tribes: [.murloc], tavernTier: 3,
                 attack: 3, health: 2, keywords: [.battlecry],
                 text: "Battlecry: If you control another Murloc, Discover a Murloc.",
                 synergyTags: [.murloc, .economyValue], baseWinRate: 0.53, avgPlacement: 3.6),

            Card(id: "BG_CFM_852", name: "Gentle Megasaur",
                 tribes: [.beast, .murloc], tavernTier: 4,
                 attack: 5, health: 4, keywords: [.battlecry],
                 text: "Battlecry: Adapt your Murlocs.",
                 synergyTags: [.murloc, .statBuffer], baseWinRate: 0.56, avgPlacement: 3.3),

            // ── Dragon ────────────────────────────────────────────────
            Card(id: "BG26_RLK_224", name: "Kalecgos, Arcane Aspect",
                 tribes: [.dragon], tavernTier: 6,
                 attack: 4, health: 12, keywords: [.startOfCombat],
                 text: "Start of Combat: Give all friendly Dragons +2/+1.",
                 synergyTags: [.dragonHold, .statBuffer, .lateBoardCap], baseWinRate: 0.63, avgPlacement: 2.7),

            Card(id: "BGS_036", name: "Murozond",
                 tribes: [.dragon], tavernTier: 5,
                 attack: 5, health: 5, keywords: [.battlecry],
                 text: "Battlecry: Add a minion from your last opponent's warband.",
                 synergyTags: [.dragonHold, .economyValue], baseWinRate: 0.57, avgPlacement: 3.1),

            // ── Beast ─────────────────────────────────────────────────
            Card(id: "BG26_800", name: "Stormpike Raider",
                 tribes: [.beast], tavernTier: 3,
                 attack: 4, health: 4, keywords: [.windfury, .battlecry],
                 text: "Battlecry: Gain +2 Attack if you have a Beast.",
                 synergyTags: [.beastBuff], baseWinRate: 0.51, avgPlacement: 3.7),

            Card(id: "BGS_006", name: "Mama Bear",
                 tribes: [.beast], tavernTier: 5,
                 attack: 4, health: 4, keywords: [],
                 text: "Whenever you summon a Beast, give it +4/+4.",
                 synergyTags: [.beastBuff, .statBuffer], baseWinRate: 0.58, avgPlacement: 3.2),

            // ── Demon ─────────────────────────────────────────────────
            Card(id: "FP1_022", name: "Mal'Ganis",
                 tribes: [.demon], tavernTier: 5,
                 attack: 9, health: 7, keywords: [],
                 text: "Your other Demons have +2/+2. Your hero is Immune.",
                 synergyTags: [.demonSelf, .statBuffer, .lateBoardCap], baseWinRate: 0.60, avgPlacement: 2.9),

            // ── Pirate ────────────────────────────────────────────────
            Card(id: "BGS_060", name: "Cap'n Hoggarr",
                 tribes: [.pirate, .beast], tavernTier: 2,
                 attack: 6, health: 6, keywords: [],
                 text: "After you play a Pirate, gain +2/+2.",
                 synergyTags: [.pirateCoin, .statBuffer], baseWinRate: 0.52, avgPlacement: 3.5),

            // ── Universal high-value ──────────────────────────────────
            Card(id: "BG20_HERO_100p", name: "Tavern Tipper",
                 tribes: [.neutral], tavernTier: 1,
                 attack: 1, health: 2, keywords: [.battlecry],
                 text: "Battlecry: Give a random friendly minion +2/+1.",
                 synergyTags: [.statBuffer], baseWinRate: 0.44, avgPlacement: 4.0),

            Card(id: "BGS_044", name: "Shifter Zerus",
                 tribes: [.neutral], tavernTier: 1,
                 attack: 1, health: 1, keywords: [],
                 text: "Each turn this is in your hand, transform into a random minion.",
                 synergyTags: [.economyValue, .tripleWorthy], baseWinRate: 0.42, avgPlacement: 4.2),
        ]
        for card in fallback { register(card) }
    }
}

// MARK: – JSON decoding bridge

private struct CardJSON: Decodable {
    let id: String
    let name: String
    let tribes: [String]
    let tavernTier: Int
    let attack: Int
    let health: Int
    let keywords: [String]
    let text: String
    let synergyTags: [String]
    let baseWinRate: Double
    let avgPlacement: Double

    func toCard() -> Card {
        Card(
            id: id, name: name,
            tribes: tribes.compactMap { Tribe(rawValue: $0) },
            tavernTier: tavernTier, attack: attack, health: health,
            keywords: keywords.compactMap { Card.Keyword(rawValue: $0) },
            text: text,
            synergyTags: synergyTags.compactMap { Card.SynergyTag(rawValue: $0) },
            baseWinRate: baseWinRate, avgPlacement: avgPlacement
        )
    }
}
