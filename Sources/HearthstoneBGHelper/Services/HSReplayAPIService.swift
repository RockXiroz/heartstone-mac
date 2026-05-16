import Foundation

// Fetches and caches win-rate data from HSReplay's public Battlegrounds endpoints.
// Falls back to bundled JSON if the network is unavailable.
actor HSReplayAPIService {

    static let shared = HSReplayAPIService()

    private let session: URLSession
    private let cacheURL: URL
    private var cachedMinions: [String: MinionStats] = [:]
    private var lastFetchDate: Date?

    // Refresh every 4 hours
    private let cacheTTL: TimeInterval = 4 * 3600

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)

        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HearthstoneBGHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("hsreplay_minions.json")
    }

    // Returns stats for all tracked minions, fetching fresh data if stale.
    func minionStats() async -> [String: MinionStats] {
        if let last = lastFetchDate, Date().timeIntervalSince(last) < cacheTTL, !cachedMinions.isEmpty {
            return cachedMinions
        }
        if let fresh = await fetchRemote() {
            cachedMinions = fresh
            lastFetchDate = Date()
            persist(fresh)
            return fresh
        }
        if let disk = loadFromDisk() {
            cachedMinions = disk
            return disk
        }
        return loadBundledFallback()
    }

    func stats(for cardID: String) async -> MinionStats? {
        await minionStats()[cardID]
    }

    // MARK: – Remote

    private func fetchRemote() async -> [String: MinionStats]? {
        // HSReplay public minion stats endpoint
        let url = URL(string: "https://hsreplay.net/api/v1/battlegrounds/minions/?locale=enUS")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 HearthstoneBGHelper", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await session.data(for: request),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        return parse(data)
    }

    private func parse(_ data: Data) -> [String: MinionStats]? {
        guard let raw = try? JSONDecoder().decode([HSReplayMinion].self, from: data) else { return nil }
        var result: [String: MinionStats] = [:]
        for m in raw {
            result[m.card_id] = MinionStats(
                cardID: m.card_id,
                avgPlacement: m.avg_final_placement,
                top4Rate: m.top_4_rate,
                top1Rate: m.top_1_rate,
                pickRate: m.pick_rate,
                sampleSize: m.total_games
            )
        }
        return result
    }

    // MARK: – Persistence

    private func persist(_ stats: [String: MinionStats]) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadFromDisk() -> [String: MinionStats]? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode([String: MinionStats].self, from: data)
    }

    private func loadBundledFallback() -> [String: MinionStats] {
        guard let url = Bundle.main.url(forResource: "BattlegroundsCards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([BundledCard].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: cards.map { card in
            (card.id, MinionStats(
                cardID: card.id,
                avgPlacement: card.avgPlacement,
                top4Rate: card.top4Rate,
                top1Rate: card.top1Rate,
                pickRate: card.pickRate,
                sampleSize: 10_000
            ))
        })
    }

    // MARK: – Codable helpers

    private struct HSReplayMinion: Decodable {
        let card_id: String
        let avg_final_placement: Double
        let top_4_rate: Double
        let top_1_rate: Double
        let pick_rate: Double
        let total_games: Int
    }

    private struct BundledCard: Decodable {
        let id: String
        let avgPlacement: Double
        let top4Rate: Double
        let top1Rate: Double
        let pickRate: Double
    }
}

struct MinionStats: Codable {
    let cardID: String
    let avgPlacement: Double   // 1.0 (best) – 8.0 (worst)
    let top4Rate: Double       // 0.0–1.0
    let top1Rate: Double       // 0.0–1.0
    let pickRate: Double       // 0.0–1.0
    let sampleSize: Int

    // Normalised win-rate score: 0.0 (terrible) – 1.0 (perfect)
    var normalizedScore: Double {
        // Blend of top1 and top4 rates; weight top1 more heavily late game
        let blended = top1Rate * 0.6 + top4Rate * 0.4
        // Penalise low-sample outliers
        let confidence = min(1.0, Double(sampleSize) / 5000.0)
        return blended * confidence + 0.3 * (1 - confidence)  // regress to 0.3 baseline
    }
}
