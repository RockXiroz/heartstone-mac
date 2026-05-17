import Foundation
import CoreGraphics

@MainActor
final class GameStateTracker: ObservableObject {

    static let shared = GameStateTracker()

    @Published private(set) var state          = GameState()
    @Published private(set) var recommendation: ShopRecommendation?
    @Published private(set) var isProcessing   = false
    @Published private(set) var statusMessage  = "⏳ 啟動擷取中…"

    private let ocr     = OCRService.shared
    private let db      = CardDatabase.shared
    private let winRate = WinRateService.shared

    private var lastShopHash = "uninitialised"
    private var frameCount   = 0
    private var idleTimer: Timer?

    // Called by AppDelegate once the SCStream successfully starts.
    func captureDidStart() {
        statusMessage = "🎥 擷取已啟動，掃描畫面中…"
        // If no frame arrives within 6 s, show a hint about permissions.
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.frameCount == 0 else { return }
                self.statusMessage = "⚠️ 已啟動但未收到畫面，請至「系統設定 → 隱私與安全 → 螢幕錄製」確認授權。"
            }
        }
    }

    // Called by ScreenCaptureService for every new frame.
    func processFrame(_ image: CGImage, windowFrame: CGRect) {
        if frameCount == 0 { idleTimer?.invalidate() }
        frameCount += 1
        Task { await analyse(image: image, windowFrame: windowFrame) }
    }

    // MARK: – Analysis pipeline

    private func analyse(image: CGImage, windowFrame: CGRect) async {
        async let rawShop = ocr.extractShopCardNames(from: image)
        async let rawTier = ocr.extractTavernTier(from: image)
        async let rawGold = ocr.extractGold(from: image)

        let (shopNames, tier, gold) = await (rawShop, rawTier, rawGold)

        let shopHash = shopNames.sorted { $0.key < $1.key }
                                .map { "\($0.key):\($0.value)" }.joined()

        if shopNames.isEmpty {
            if recommendation != nil { recommendation = nil }
            lastShopHash  = ""
            statusMessage = "⚔️ 戰鬥 / 選擇階段 (\(frameCount) 幀已接收)"
            isProcessing  = false
            return
        }

        guard shopHash != lastShopHash else { return }
        lastShopHash = shopHash
        isProcessing = true
        statusMessage = "分析中…"

        let slots: [ShopSlot] = shopNames.compactMap { (index, name) in
            guard let card = db.findCard(named: name) else { return nil }
            let slotX = computeSlotX(index: index, windowWidth: windowFrame.width)
            let slotRect = CGRect(x: slotX, y: windowFrame.height * 0.82,
                                  width: windowFrame.width * 0.09,
                                  height: windowFrame.height * 0.16)
            return ShopSlot(id: index, card: card, screenRegion: slotRect)
        }

        state.shopCards = slots
        if let tier { state.tavernTier = tier }
        if let gold  { state.gold = gold }

        for slot in slots {
            if let card = slot.card {
                state.seenCards[card.id, default: 0] += 1
            }
        }

        let rec  = await winRate.recommend(for: state)
        recommendation = rec

        let best = rec.bestPick
        statusMessage = "推薦：\(best.card.name)（\(best.winRatePercent)% 勝率）"
        isProcessing  = false
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

    // MARK: – Helpers

    private func computeSlotX(index: Int, windowWidth: CGFloat) -> CGFloat {
        let firstX: CGFloat = 0.21
        let lastX:  CGFloat = 0.79
        let step = (lastX - firstX) / 6.0
        return (firstX + CGFloat(index) * step) * windowWidth - windowWidth * 0.045
    }
}
