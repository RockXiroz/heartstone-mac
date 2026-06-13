import Foundation
import CoreGraphics
import AppKit

// Maintains the live game state from Power.log parsing and produces shop
// recommendations. Card identity comes from the game log (exact card IDs),
// not screen OCR — far more reliable.
@MainActor
final class GameStateTracker: ObservableObject {

    static let shared = GameStateTracker()

    @Published private(set) var state          = GameState()
    @Published private(set) var recommendation: ShopRecommendation?
    @Published private(set) var isProcessing   = false
    @Published private(set) var statusMessage  = "⏳ 啟動中…"

    private let db      = CardDatabase.shared
    private let winRate = WinRateService.shared

    // Screen geometry used to place arrows over the on-screen shop slots.
    // Shop minion row in the recruit phase sits in the upper-middle of the screen.
    var screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

    // MARK: – Log-driven status

    func logStatus(_ message: String) {
        statusMessage = message
    }

    // MARK: – Shop update (from PowerLogParser)

    func updateShop(cardIDs: [Int: String]) {
        let slots: [ShopSlot] = cardIDs.sorted { $0.key < $1.key }.compactMap { (index, cardId) in
            guard let card = db.findCard(byID: cardId) else { return nil }
            return ShopSlot(id: index, card: card, screenRegion: slotRect(index: index))
        }

        guard !slots.isEmpty else {
            recommendation = nil
            statusMessage = "⚔️ 戰鬥 / 選擇階段（商店無小兵）"
            return
        }

        state.shopCards = slots
        for slot in slots {
            if let card = slot.card { state.seenCards[card.id, default: 0] += 1 }
        }

        isProcessing = true
        statusMessage = "分析中…（\(slots.count) 張卡）"

        Task {
            let rec = await winRate.recommend(for: state)
            recommendation = rec
            let best = rec.bestPick
            statusMessage = "推薦：\(best.card.name)（\(best.winRatePercent)% 勝率）"
            isProcessing = false
        }
    }

    // MARK: – Opponent tracking

    func recordOpponentBoard(seat: Int, board: [Card], tavernTier: Int, health: Int) {
        if let idx = state.opponents.firstIndex(where: { $0.id == seat }) {
            state.opponents[idx].board      = board
            state.opponents[idx].tavernTier = tavernTier
            state.opponents[idx].health     = health
        } else {
            state.opponents.append(PlayerState(
                id: seat, board: board, tavernTier: tavernTier, health: health
            ))
        }
    }

    func setActiveTribePool(_ tribes: Set<Tribe>) {
        state.activeTribePool = ActiveTribePool(tribes: tribes)
    }

    // MARK: – Shop slot geometry (top-left origin; OverlayVC flips to AppKit coords)

    private func slotRect(index: Int) -> CGRect {
        let firstX: CGFloat = 0.30   // centre of slot 0
        let lastX:  CGFloat = 0.70   // centre of slot 6
        let slotW:  CGFloat = 0.075
        let rowY:   CGFloat = 0.38   // top of minion row
        let rowH:   CGFloat = 0.20

        let step = (lastX - firstX) / 6.0
        let cx = firstX + CGFloat(index) * step
        return CGRect(
            x: (cx - slotW / 2) * screenSize.width,
            y: rowY * screenSize.height,
            width: slotW * screenSize.width,
            height: rowH * screenSize.height
        )
    }
}
