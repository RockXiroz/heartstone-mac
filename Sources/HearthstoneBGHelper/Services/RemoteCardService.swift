import Foundation

// Downloads the full Battlegrounds card list from HearthstoneJSON (the community
// card database used by HDT/Firestone) and maps it into our Card model.
// The bundled 20-card JSON is only a bootstrap; a live game offers hundreds of
// distinct minions, so full coverage is required for log-based detection.
actor RemoteCardService {

    static let shared = RemoteCardService()

    private let locales = ["zhTW", "enUS"]   // user's client is zh-TW; enUS fallback
    private let cacheTTL: TimeInterval = 7 * 24 * 3600

    // MARK: – Public

    // Returns all current BG pool minions, from cache when fresh, else network.
    func loadBattlegroundsCards() async -> [Card] {
        if let cached = loadCache(), !cached.isEmpty { return cached }

        for locale in locales {
            do {
                let cards = try await fetch(locale: locale)
                if !cards.isEmpty {
                    saveCache(cards)
                    return cards
                }
            } catch {
                print("[RemoteCardService] fetch \(locale) failed: \(error)")
            }
        }
        return []
    }

    // MARK: – Network

    private func fetch(locale: String) async throws -> [Card] {
        let url = URL(string: "https://api.hearthstonejson.com/v1/latest/\(locale)/cards.json")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let all = try JSONDecoder().decode([HSJSONCard].self, from: data)

        // BG pool minions: have a tech level and are the normal (non-golden) copy.
        let pool = all.filter {
            $0.type == "MINION" &&
            $0.techLevel != nil &&
            $0.battlegroundsNormalDbfId == nil
        }
        return pool.map { $0.toCard() }
    }

    // MARK: – Disk cache

    private var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HearthstoneBGHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("bg_cards.json")
    }

    private func loadCache() -> [Card]? {
        let url = cacheURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < cacheTTL,
              let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([Card].self, from: data) else { return nil }
        return cards
    }

    private func saveCache(_ cards: [Card]) {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

// MARK: – HearthstoneJSON schema (subset)

private struct HSJSONCard: Decodable {
    let id: String
    let name: String?
    let type: String?
    let text: String?
    let attack: Int?
    let health: Int?
    let techLevel: Int?
    let race: String?
    let races: [String]?
    let mechanics: [String]?
    let battlegroundsNormalDbfId: Int?

    func toCard() -> Card {
        let tier = techLevel ?? 1
        return Card(
            id: id,
            name: name ?? id,
            tribes: mappedTribes(),
            tavernTier: tier,
            attack: attack ?? 0,
            health: health ?? 0,
            keywords: mappedKeywords(),
            text: cleanedText(),
            synergyTags: [],
            // Neutral priors; HSReplay stats and synergy factors refine at runtime.
            baseWinRate: 0.44 + 0.02 * Double(tier),
            avgPlacement: 4.4 - 0.15 * Double(tier)
        )
    }

    private func mappedTribes() -> [Tribe] {
        let raw = races ?? (race.map { [$0] } ?? [])
        if raw.contains("ALL") {
            return [.beast, .demon, .dragon, .elemental, .mech,
                    .murloc, .naga, .pirate, .quilboar, .undead]
        }
        let map: [String: Tribe] = [
            "BEAST": .beast, "DEMON": .demon, "DRAGON": .dragon,
            "ELEMENTAL": .elemental, "MECHANICAL": .mech, "MURLOC": .murloc,
            "NAGA": .naga, "PIRATE": .pirate, "QUILBOAR": .quilboar,
            "UNDEAD": .undead, "TITAN": .titan
        ]
        let tribes = raw.compactMap { map[$0] }
        return tribes.isEmpty ? [.neutral] : tribes
    }

    private func mappedKeywords() -> [Card.Keyword] {
        let map: [String: Card.Keyword] = [
            "DIVINE_SHIELD": .divineShield, "TAUNT": .taunt,
            "POISONOUS": .poisonous, "VENOMOUS": .venomous,
            "WINDFURY": .windfury, "DEATHRATTLE": .deathrattle,
            "BATTLECRY": .battlecry, "REBORN": .reborn,
            "MODULAR": .magnetize, "MAGNETIC": .magnetize,
            "AVENGE": .avenge
        ]
        return (mechanics ?? []).compactMap { map[$0] }
    }

    private func cleanedText() -> String {
        guard var t = text else { return "" }
        for tag in ["<b>", "</b>", "<i>", "</i>", "[x]"] {
            t = t.replacingOccurrences(of: tag, with: "")
        }
        return t.replacingOccurrences(of: "\n", with: " ")
    }
}
