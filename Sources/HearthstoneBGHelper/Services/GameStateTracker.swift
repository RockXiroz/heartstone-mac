import Foundation
import CoreGraphics
import AppKit

// Maintains the live game state from Power.log parsing and produces shop
// recommendations. Card identity comes from the game log (exact card IDs).
@MainActor
final class GameStateTracker: ObservableObject {

    static let shared = GameStateTracker()

    // Bump on every user-visible fix so the running build is identifiable in the HUD.
    static let version = "v0.6"

    @Published private(set) var state          = GameState()
    @Published private(set) var recommendation: ShopRecommendation?
    @Published private(set) var isProcessing   = false
    @Published private(set) var statusMessage  = "⏳ \(GameStateTracker.version) 啟動中…"

    private let db      = CardDatabase.shared
    private let winRate = WinRateService.shared

    // Screen geometry used to place arrows over the on-screen shop slots.
    var screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

    private var lastShopIDs: [Int: String] = [:]
    private var recommendTask: Task<Void, Never>?

    // MARK: – Log-driven status

    func logStatus(_ message: String) {
        // Don't let background status overwrite an active recommendation.
        guard recommendation == nil else { return }
        statusMessage = message
    }

    func phaseChanged(isShopping: Bool) {
        if !isShopping {
            recommendation = nil
            statusMessage = "⚔️ 戰鬥階段，等待下一輪補兵…"
        }
    }

    // Called when the remote card database finishes loading — re-resolve the
    // current shop so placeholder names become real cards.
    func cardDatabaseDidUpdate() {
        statusMessage = "📚 卡牌資料庫已載入（\(db.count) 張）"
        if !lastShopIDs.isEmpty {
            updateShop(cardIDs: lastShopIDs)
        }
    }

    // MARK: – Shop update (from PowerLogParser)

    func updateShop(cardIDs: [Int: String]) {
        lastShopIDs = cardIDs

        guard !cardIDs.isEmpty else {
            recommendation = nil
            statusMessage = "⚔️ 戰鬥 / 等待階段（商店無小兵）"
            return
        }

        // Anchor slot geometry to the actual game window (may be windowed).
        let gameFrame = GameWindowLocator.findHearthstoneWindow()
            ?? CGRect(origin: .zero, size: screenSize)

        let ordered = cardIDs.sorted { $0.key < $1.key }
        let slotCount = ordered.count
        let slots: [ShopSlot] = ordered.enumerated().map { (position, entry) in
            let (slotIndex, cardId) = entry
            let card = db.findCard(byID: cardId) ?? .placeholder(id: cardId)
            return ShopSlot(id: slotIndex, card: card,
                            screenRegion: slotRect(position: position, of: slotCount, in: gameFrame))
        }

        state.shopCards = slots
        for slot in slots {
            if let card = slot.card { state.seenCards[card.id, default: 0] += 1 }
        }

        isProcessing = true
        statusMessage = "🔎 分析中…（\(slots.count) 張卡）"

        recommendTask?.cancel()
        let snapshot = state
        recommendTask = Task { [weak self] in
            guard let self else { return }
            let rec = await self.winRate.recommend(for: snapshot)
            guard !Task.isCancelled else { return }
            self.recommendation = rec
            let best = rec.bestPick
            self.statusMessage = "推薦：\(best.card.name)（\(best.winRatePercent)% 勝率）"
            self.isProcessing = false
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

    // MARK: – Shop slot geometry (global top-left origin, relative to game window)

    // Hearthstone scales its UI to a 16:9 content box centred in the window:
    // wider windows letterbox horizontally, narrower ones vertically. Slot
    // positions therefore derive from the content-box HEIGHT (measured from
    // real screenshots): spacing ≈ 0.171·H, row centre ≈ 0.508·H from content top.
    private func slotRect(position: Int, of count: Int, in frame: CGRect) -> CGRect {
        let contentH   = min(frame.height, frame.width / 1.78)
        let contentTop = frame.midY - contentH / 2

        let spacing = 0.171 * contentH
        let slotW   = 0.130 * contentH
        let slotH   = 0.240 * contentH
        let rowCenterY = contentTop + 0.508 * contentH

        let cx = frame.midX + (CGFloat(position) - CGFloat(count - 1) / 2) * spacing
        return CGRect(
            x: cx - slotW / 2,
            y: rowCenterY - slotH / 2,
            width: slotW,
            height: slotH
        )
    }
}
