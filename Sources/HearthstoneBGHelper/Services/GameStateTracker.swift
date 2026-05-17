import Foundation
import CoreGraphics

// Maintains a running game state model by combining OCR results with the
// card database. Calls the WinRateService whenever the shop changes.
@MainActor
final class GameStateTracker: ObservableObject {

    static let shared = GameStateTracker()

    @Published private(set) var state    = GameState()
    @Published private(set) var recommendation: ShopRecommendation?
    @Published private(set) var isProcessing = false
    @Published private(set) var statusMessage = "等待遊戲畫面…"

    private let ocr      = OCRService.shared
    private let db       = CardDatabase.shared
    private let winRate  = WinRateService.shared

    private var lastShopHash = "uninitialised"  // sentinel ≠ "" so empty result is still processed once
    private var frameCount = 0

    // Called by ScreenCaptureService for every new frame
    func processFrame(_ image: CGImage, windowFrame: CGRect) {
        frameCount += 1
        Task { await analyse(image: image, windowFrame: windowFrame) }
    }

    // MARK: – Analysis pipeline

    private func analyse(image: CGImage, windowFrame: CGRect) async {
        // 1. Extract text fields in parallel
        async let rawShop    = ocr.extractShopCardNames(from: image)
        async let rawTier    = ocr.extractTavernTier(from: image)
        async let rawGold    = ocr.extractGold(from: image)

        let (shopNames, tier, gold) = await (rawShop, rawTier, rawGold)

        // 2. Always update status so the user knows frames are arriving,
        //    even during battle phase when the shop is empty.
        let shopHash = shopNames.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined()

        if shopNames.isEmpty {
            // Battle / selection phase – no shop visible.
            // Always update status so the HUD shows the live frame count.
            if recommendation != nil { recommendation = nil }
            lastShopHash  = ""
            statusMessage = "⚔️ 戰鬥階段，等待補兵畫面… (\(frameCount) 幀)"
            isProcessing  = false
            return
        }

        guard shopHash != lastShopHash else { return }
        lastShopHash = shopHash

        isProcessing = true
        statusMessage = "分析中…"

        // 3. Map OCR names → Card models
        let slots: [ShopSlot] = shopNames.compactMap { (index, name) in
            guard let card = db.findCard(named: name) else { return nil }
            let slotX = computeSlotX(index: index, windowWidth: windowFrame.width)
            let slotRect = CGRect(x: slotX, y: windowFrame.height * 0.82,
                                  width: windowFrame.width * 0.09,
                                  height: windowFrame.height * 0.16)
            return ShopSlot(id: index, card: card, screenRegion: slotRect)
        }

        // 4. Update game state
        state.shopCards = slots
        if let tier { state.tavernTier = tier }
        if let gold { state.gold = gold }
        state.turn += 0  // turn is incremented separately when we detect round change

        // 5. Track seen cards
        for slot in slots {
            if let card = slot.card {
                state.seenCards[card.id, default: 0] += 1
            }
        }

        // 6. Compute recommendations
        let rec = await winRate.recommend(for: state)
        recommendation = rec

        let best = rec.bestPick
        statusMessage = "推薦購買：\(best.card.name)（\(best.winRatePercent)% 勝率）"
        isProcessing = false
    }

    // MARK: – Opponent tracking

    // Called after each combat sequence ends (detected by health change)
    func recordOpponentBoard(seat: Int, board: [Card], tavernTier: Int, health: Int) {
        if let idx = state.opponents.firstIndex(where: { $0.id == seat }) {
            state.opponents[idx].board = board
            state.opponents[idx].tavernTier = tavernTier
            state.opponents[idx].health = health
        } else {
            state.opponents.append(PlayerState(
                id: seat, board: board, tavernTier: tavernTier, health: health
            ))
        }
    }

    func setActiveTribePool(_ tribes: Set<Tribe>) {
        state.activeTribePool = ActiveTribePool(tribes: tribes)
    }

    // MARK: – Helpers

    private func computeSlotX(index: Int, windowWidth: CGFloat) -> CGFloat {
        let firstX: CGFloat = 0.21
        let lastX:  CGFloat = 0.79
        let step = (lastX - firstX) / 6.0
        return (firstX + CGFloat(index) * step) * windowWidth - windowWidth * 0.045
    }
}
