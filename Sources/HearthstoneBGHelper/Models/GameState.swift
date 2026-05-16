import Foundation

struct PlayerState: Identifiable {
    let id: Int           // seat 0–7
    var board: [Card]
    var tavernTier: Int
    var health: Int
    var isAlive: Bool { health > 0 }

    // Dominant tribe on this opponent's board
    var dominantTribe: Tribe? {
        let tribeCounts = board.flatMap { $0.tribes.filter { $0 != .neutral } }
            .reduce(into: [Tribe: Int]()) { $0[$1, default: 0] += 1 }
        return tribeCounts.max(by: { $0.value < $1.value })?.key
    }

    // True when opponent runs ≥3 minions of the same tribe
    var isRunningTribeComp: Bool {
        let tribeCounts = board.flatMap { $0.tribes.filter { $0 != .neutral } }
            .reduce(into: [Tribe: Int]()) { $0[$1, default: 0] += 1 }
        return tribeCounts.values.contains(where: { $0 >= 3 })
    }
}

struct GameState {
    var playerSeat: Int = 0
    var playerBoard: [Card] = []
    var playerHand: [Card] = []          // cards held (bought but not played)
    var shopCards: [ShopSlot] = []       // current shop contents
    var frozenCards: [Card] = []         // frozen from last turn
    var opponents: [PlayerState] = []
    var activeTribePool: ActiveTribePool = .full
    var tavernTier: Int = 1
    var gold: Int = 3
    var turn: Int = 1
    var playerHealth: Int = 40

    // Cards the player has seen / tracked across turns (for triple prediction)
    var seenCards: [String: Int] = [:]   // cardID → count seen

    // Approximate probability of completing a triple for a card
    func tripleCompletionProbability(for card: Card, owned: Int) -> Double {
        // 2 copies needed, 6 instances per card in the pool minus owned/seen
        let poolSize = 6
        let inPool = poolSize - owned - (seenCards[card.id] ?? 0)
        guard inPool > 0 else { return 0 }
        return Double(inPool) / Double(max(inPool, 20)) * Double(owned)
    }

    // How many opponents actively pursue the same tribe
    func opponentThreat(for tribe: Tribe) -> Int {
        opponents.filter { $0.dominantTribe == tribe }.count
    }

    // Board tribe composition
    var boardTribeCounts: [Tribe: Int] {
        playerBoard.flatMap { $0.tribes.filter { $0 != .neutral } }
            .reduce(into: [Tribe: Int]()) { $0[$1, default: 0] += 1 }
    }

    // Current "primary" build tribe (most represented)
    var primaryBuildTribe: Tribe? {
        boardTribeCounts.max(by: { $0.value < $1.value })?.key
    }

    var isEarlyGame: Bool  { turn <= 4 }
    var isMidGame: Bool    { turn > 4 && turn <= 8 }
    var isLateGame: Bool   { turn > 8 }
}

struct ShopSlot: Identifiable {
    let id: Int           // slot index 0–6
    var card: Card?
    var isFrozen: Bool = false
    // Screen region in Hearthstone window coordinates (unit: pixels)
    var screenRegion: CGRect = .zero
}
