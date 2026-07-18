import Foundation

// Computes per-card win-rate scores and produces a ShopRecommendation.
// Uses a weighted factor model rather than a pure ML model so it's
// explainable and works without training data.
actor WinRateService {

    static let shared = WinRateService()

    private let api = HSReplayAPIService.shared

    func recommend(for state: GameState) async -> ShopRecommendation {
        let statsMap = await api.minionStats()
        var picks: [Recommendation] = []

        for slot in state.shopCards {
            guard let card = slot.card else { continue }
            let stats = statsMap[card.id]
            let (score, reasons) = computeScore(card: card, state: state, stats: stats)
            let rec = Recommendation(
                card: card,
                shopSlotIndex: slot.id,
                shopSlotRegion: slot.screenRegion,
                winRateScore: score,
                reasons: reasons,
                tier: .from(score: score)
            )
            picks.append(rec)
        }

        picks.sort { $0.winRateScore > $1.winRateScore }

        let freeze = shouldFreeze(state: state, picks: picks)
        return ShopRecommendation(
            bestPick: picks.first ?? dummyRecommendation(),
            allPicks: picks,
            shouldFreeze: freeze.should,
            freezeReason: freeze.reason,
            alternativePlays: generateAlternatives(state: state, picks: picks),
            generatedAt: Date()
        )
    }

    // MARK: – Core scoring

    private func computeScore(
        card: Card,
        state: GameState,
        stats: MinionStats?
    ) -> (score: Double, reasons: [Recommendation.ReasonItem]) {
        var score = 0.0
        var reasons: [Recommendation.ReasonItem] = []

        // 1. Base win-rate from HSReplay data when available, else the card's
        //    own prior (tier-derived for remote cards, curated for bundled ones)
        let baseScore = stats?.normalizedScore ?? card.baseWinRate
        let baseContrib = baseScore * 0.35
        score += baseContrib
        if let s = stats {
            let placementStr = String(format: "%.2f", s.avgPlacement)
            reasons.append(.init(
                icon: "chart.bar.fill",
                text: "平均排名 \(placementStr)（前4率 \(Int(s.top4Rate * 100))%）",
                weight: baseContrib
            ))
        }

        // 2. Tribe synergy with player's current board (weight: 25%)
        let tribeContrib = tribeSynergyScore(card: card, state: state)
        score += tribeContrib * 0.25
        if tribeContrib > 0.3 {
            let tribe = card.primaryTribe.displayName
            let count = state.boardTribeCounts[card.primaryTribe] ?? 0
            reasons.append(.init(
                icon: "star.fill",
                text: "強化 \(tribe) 陣容（已有 \(count) 張）",
                weight: tribeContrib * 0.25
            ))
        }

        // 3. Board completion bonus – approaching triple or tribal threshold (weight: 15%)
        let completionContrib = completionBonus(card: card, state: state)
        score += completionContrib * 0.15
        if completionContrib > 0.4 {
            reasons.append(.init(
                icon: "3.circle.fill",
                text: "接近完成三倍牌或核心組合",
                weight: completionContrib * 0.15
            ))
        }

        // 4. Future scaling potential (weight: 15%)
        let scalingContrib = scalingScore(card: card, state: state)
        score += scalingContrib * 0.15
        if scalingContrib > 0.5 {
            reasons.append(.init(
                icon: "arrow.up.right.circle.fill",
                text: "後期成長性高（\(card.primaryTribe.displayName)）",
                weight: scalingContrib * 0.15
            ))
        }

        // 5. Counter-opponent adjustment (weight: 10%)
        let counterContrib = counterScore(card: card, state: state)
        score += counterContrib * 0.10
        if counterContrib > 0.4 {
            reasons.append(.init(
                icon: "shield.lefthalf.filled",
                text: "有效反制當前對手陣容",
                weight: counterContrib * 0.10
            ))
        } else if counterContrib < -0.2 {
            score += counterContrib * 0.10  // already added, reason is warning
            reasons.append(.init(
                icon: "exclamationmark.triangle.fill",
                text: "多名對手使用相同族群，競爭激烈",
                weight: counterContrib * 0.10
            ))
        }

        // 6. Tavern-tier value (right tier = right card) (bonus/penalty ±0.05)
        let tierBonus = tierValueBonus(card: card, state: state)
        score += tierBonus
        if tierBonus > 0.03 {
            reasons.append(.init(
                icon: "crown.fill",
                text: "此酒館等級的高效率選擇",
                weight: tierBonus
            ))
        }

        // Clamp to [0, 1]
        score = max(0, min(1, score))

        // Guarantee the HUD always has 3 reason lines — pad with card facts
        // when no threshold-gated reason fired.
        if reasons.count < 3 {
            let tribeName = card.primaryTribe.displayName
            reasons.append(.init(
                icon: "info.circle",
                text: "酒館 \(card.tavernTier) 星 · \(tribeName) · \(card.attack)/\(card.health)",
                weight: 0.003
            ))
        }
        if stats == nil, reasons.count < 3 {
            reasons.append(.init(
                icon: "wifi.slash",
                text: "HSReplay 尚無此卡數據，使用基準評分",
                weight: 0.002
            ))
        }
        if reasons.count < 3 {
            reasons.append(.init(
                icon: "square.grid.2x2",
                text: tribeContrib > 0.2 ? "與現有陣容有部分協同" : "與現有陣容協同有限，屬過渡選擇",
                weight: 0.001
            ))
        }

        return (score, reasons)
    }

    // MARK: – Factor helpers

    private func tribeSynergyScore(card: Card, state: GameState) -> Double {
        guard !card.tribes.contains(.neutral) || card.tribes.isEmpty else { return 0.2 }

        var best = 0.0
        for tribe in card.tribes where tribe != .neutral {
            guard state.activeTribePool.contains(tribe) else { continue }
            let owned = state.boardTribeCounts[tribe] ?? 0
            let threshold = tribe.synergyThreshold

            if owned == 0 {
                // Starting a new tribe only good early game
                let noveltyBonus = state.isEarlyGame ? 0.3 : 0.1
                best = max(best, noveltyBonus)
            } else if owned < threshold {
                // Building toward threshold
                let progress = Double(owned) / Double(threshold)
                best = max(best, 0.4 + progress * 0.4)
            } else {
                // Already at/above threshold – card adds depth
                best = max(best, 0.9)
            }

            // Penalise if tribe not in active pool
            if !state.activeTribePool.tribes.contains(tribe) {
                best = min(best, 0.2)
            }
        }
        return best
    }

    private func completionBonus(card: Card, state: GameState) -> Double {
        var bonus = 0.0

        // Triple completion
        let seenCount = state.seenCards[card.id] ?? 0
        let owned = state.playerBoard.filter { $0.id == card.id }.count
             + state.playerHand.filter { $0.id == card.id }.count
        if owned == 2 || seenCount >= 2 {
            bonus = max(bonus, 0.9)  // one more = triple!
        } else if owned == 1 {
            bonus = max(bonus, 0.4)
        }

        // Board tribal synergy threshold completion
        for tribe in card.tribes where tribe != .neutral {
            let owned = state.boardTribeCounts[tribe] ?? 0
            if owned == tribe.synergyThreshold - 1 {
                bonus = max(bonus, 0.8)  // one more = threshold
            }
        }
        return bonus
    }

    private func scalingScore(card: Card, state: GameState) -> Double {
        var score = card.scalingPotential / 8.0  // normalise ~0–1

        // Scaling matters more in mid/late game
        if state.isMidGame  { score *= 1.2 }
        if state.isLateGame { score *= 1.4 }

        // Tribe scaling
        if let tribe = card.tribes.first(where: { $0 != .neutral }), tribe.isScaling {
            score += 0.2
        }
        return min(score, 1.0)
    }

    private func counterScore(card: Card, state: GameState) -> Double {
        var score = 0.0

        // Poisonous/Venomous is a hard counter to high-attack comps (Mechs, Undead)
        if card.keywords.contains(.poisonous) || card.keywords.contains(.venomous) {
            let highAttackOpponents = state.opponents.filter {
                $0.board.map(\.attack).max() ?? 0 > 8
            }.count
            score += Double(highAttackOpponents) * 0.15
        }

        // Divine Shield is counter to wide board (Murlocs, Mechs)
        if card.keywords.contains(.divineShield) {
            let wideBoards = state.opponents.filter { $0.board.count >= 5 }.count
            score += Double(wideBoards) * 0.10
        }

        // Penalise if many opponents run same tribe (resource competition)
        for tribe in card.tribes where tribe != .neutral {
            let threat = state.opponentThreat(for: tribe)
            score -= Double(threat) * 0.08
        }
        return max(-1.0, min(1.0, score))
    }

    private func tierValueBonus(card: Card, state: GameState) -> Double {
        let diff = abs(card.tavernTier - state.tavernTier)
        switch diff {
        case 0: return 0.04   // perfect tier match
        case 1: return 0.01
        default: return -0.02  // too high tier = probably rolled, not ideal
        }
    }

    // MARK: – Freeze suggestion

    private func shouldFreeze(
        state: GameState,
        picks: [Recommendation]
    ) -> (should: Bool, reason: String?) {
        guard let best = picks.first else { return (false, nil) }

        // All remaining gold after buying top pick
        let goldLeft = state.gold - 3   // buying costs 3
        if goldLeft >= 1 && best.winRateScore < 0.5 && picks.count > 1 {
            let secondBest = picks[1]
            if secondBest.winRateScore > 0.6 {
                return (true, "凍結可保留 \(secondBest.card.name) 給下一回合（節省 3 金幣）")
            }
        }

        // Already have a great shop – freeze to guarantee next turn
        if picks.filter({ $0.winRateScore > 0.7 }).count >= 2 {
            return (true, "商店中有多張高勝率牌，凍結可確保下回合選擇")
        }
        return (false, nil)
    }

    // MARK: – Alternative suggestions

    private func generateAlternatives(state: GameState, picks: [Recommendation]) -> [String] {
        var alts: [String] = []

        // Suggest selling weakest board minion for a shop card
        if let weakestOnBoard = state.playerBoard.min(by: { $0.offensiveScore + $0.defensiveScore < $1.offensiveScore + $1.defensiveScore }),
           let bestPick = picks.first, bestPick.winRateScore > 0.65 {
            alts.append("考慮賣掉 \(weakestOnBoard.name)（最弱牌），買入 \(bestPick.card.name)")
        }

        // Upgrading tavern might be better than buying
        let upgradeCost = max(4, 10 - state.turn)
        if state.gold >= upgradeCost + 3 && state.tavernTier < 6 &&
           (picks.first?.winRateScore ?? 0) < 0.55 {
            alts.append("本回合商店選擇不佳，考慮升級酒館（\(upgradeCost) 金幣）")
        }
        return alts
    }

    private func dummyRecommendation() -> Recommendation {
        Recommendation(
            card: Card(id: "", name: "（無牌）", tribes: [.neutral], tavernTier: 1,
                       attack: 0, health: 0, keywords: [], text: "", synergyTags: [],
                       baseWinRate: 0, avgPlacement: 4),
            shopSlotIndex: 0, shopSlotRegion: .zero,
            winRateScore: 0, reasons: [], tier: .skip
        )
    }
}
