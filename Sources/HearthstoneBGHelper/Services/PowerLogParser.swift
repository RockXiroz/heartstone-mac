import Foundation

// Parses Hearthstone Power.log lines into a live entity model and extracts the
// minions currently offered in Bob's Tavern (the Battlegrounds shop).
//
// Real Power.log structure (GameState lines only; PowerTaskList duplicates them):
//
//   D 21:35:41.18 GameState.DebugPrintPower() - CREATE_GAME
//   D ... GameState.DebugPrintPower() -     FULL_ENTITY - Creating ID=68 CardID=BGS_106
//   D ... GameState.DebugPrintPower() -         tag=CONTROLLER value=8
//   D ... GameState.DebugPrintPower() -         tag=CARDTYPE value=MINION
//   D ... GameState.DebugPrintPower() -         tag=ZONE value=PLAY
//   D ... GameState.DebugPrintPower() -         tag=ZONE_POSITION value=1
//   D ... GameState.DebugPrintPower() -     FULL_ENTITY - Updating [entityName=X id=64 zone=PLAY zonePos=2 cardId=BG26_147 player=8] CardID=BG26_147
//   D ... GameState.DebugPrintPower() -     TAG_CHANGE Entity=[entityName=X id=64 ... player=8] tag=ZONE value=REMOVEDFROMGAME
//   D ... GameState.DebugPrintPower() -     TAG_CHANGE Entity=GameEntity tag=BOARD_VISUAL_STATE value=1
//
// Key Battlegrounds facts:
//  * Bob's hero entity has CardID "TB_BaconShopBob" — its controller id is the
//    tavern controller. Shop minions are PLAY-zone MINIONs with that controller.
//  * GameEntity tag BOARD_VISUAL_STATE: 1 = recruit/shopping phase, 2 = combat.
@MainActor
final class PowerLogParser {

    struct Entity {
        var id: Int
        var cardId: String = ""
        var zone: String = ""
        var zonePos: Int = 0
        var controller: Int = 0
        var cardType: String = ""
    }

    /// Ordered (slot index → CardID). Empty dictionary = shop is empty/cleared.
    var onShopChanged: (@MainActor ([Int: String]) -> Void)?
    /// true = recruit (shopping) phase, false = combat.
    var onPhaseChanged: (@MainActor (Bool) -> Void)?
    /// Human-readable diagnostics for the console / HUD status.
    var onDiagnostic: (@MainActor (String) -> Void)?

    private(set) var entities: [Int: Entity] = [:]
    private var bobControllerId: Int?
    private var bobEntityId: Int?
    private var isShopping = true

    private var blockEntityId: Int?          // entity the current FULL/SHOW_ENTITY block describes
    private var lastShopSignature = "∅"
    private var pendingRecompute: Task<Void, Never>?

    // MARK: – Ingest

    func ingest(_ rawLine: String) {
        // Only GameState lines — PowerTaskList repeats every event with a delay.
        guard rawLine.contains("GameState.DebugPrintPower()") else { return }
        guard let dashRange = rawLine.range(of: "- ") else { return }
        let line = String(rawLine[dashRange.upperBound...])

        if line.contains("CREATE_GAME") {
            entities.removeAll()
            bobControllerId = nil
            bobEntityId = nil
            blockEntityId = nil
            lastShopSignature = "∅"
            isShopping = true
            onDiagnostic?("🎮 偵測到新對戰開始")
            return
        }

        if line.contains("FULL_ENTITY") || line.contains("SHOW_ENTITY") || line.contains("CHANGE_ENTITY") {
            parseEntityHeader(line)
        } else if line.contains("TAG_CHANGE") || line.contains("HIDE_ENTITY") {
            blockEntityId = nil
            parseTagChange(line)
        } else if isBlockTagLine(line) {
            parseBlockTag(line)
        } else {
            // BLOCK_START / BLOCK_END / options etc. terminate any entity block.
            blockEntityId = nil
        }
    }

    // MARK: – FULL_ENTITY / SHOW_ENTITY headers

    private func parseEntityHeader(_ line: String) {
        var id: Int?
        var cardId = ""
        var fields: BracketFields?

        if let bracket = bracketFields(in: line) {
            fields = bracket
            id = bracket.id
        } else if let creating = intValue(after: "ID=", in: line) {
            // "FULL_ENTITY - Creating ID=68 CardID=BGS_106"
            id = creating
        }
        if let c = stringValue(after: "CardID=", in: line), !c.isEmpty {
            cardId = c
        }

        guard let entityId = id else { blockEntityId = nil; return }

        var e = entities[entityId] ?? Entity(id: entityId)
        if let f = fields {
            if !f.cardId.isEmpty  { e.cardId = f.cardId }
            if !f.zone.isEmpty    { e.zone = f.zone }
            if f.zonePos > 0      { e.zonePos = f.zonePos }
            if f.controller > 0   { e.controller = f.controller }
        }
        if !cardId.isEmpty { e.cardId = cardId }
        entities[entityId] = e
        blockEntityId = entityId

        checkForBob(e)
        scheduleRecompute()
    }

    // MARK: – Indented tag lines inside an entity block

    private func isBlockTagLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("tag=") && trimmed.contains("value=")
    }

    private func parseBlockTag(_ line: String) {
        guard let entityId = blockEntityId, var e = entities[entityId],
              let tag = stringValue(after: "tag=", in: line),
              let value = stringValue(after: "value=", in: line) else { return }
        apply(tag: tag, value: value, to: &e)
        entities[entityId] = e
        checkForBob(e)
        scheduleRecompute()
    }

    // MARK: – TAG_CHANGE

    private func parseTagChange(_ line: String) {
        guard let tag = stringValue(after: "tag=", in: line),
              let value = stringValue(after: "value=", in: line) else { return }

        // Phase switch: GameEntity BOARD_VISUAL_STATE 1=shop 2=combat
        if line.contains("Entity=GameEntity") {
            if tag == "BOARD_VISUAL_STATE" {
                let shopping = (value == "1")
                if shopping != isShopping {
                    isShopping = shopping
                    onPhaseChanged?(shopping)
                    onDiagnostic?(shopping ? "🛒 進入補兵階段" : "⚔️ 進入戰鬥階段")
                    scheduleRecompute()
                }
            }
            return
        }

        // Entity=[entityName=... id=530 ...] — take the id from inside the bracket.
        guard let bracket = bracketFields(in: line) else { return }
        var e = entities[bracket.id] ?? Entity(id: bracket.id)
        if !bracket.cardId.isEmpty { e.cardId = bracket.cardId }
        apply(tag: tag, value: value, to: &e)
        entities[bracket.id] = e
        checkForBob(e)
        scheduleRecompute()
    }

    private func apply(tag: String, value: String, to e: inout Entity) {
        switch tag {
        case "ZONE":          e.zone = value
        case "ZONE_POSITION": e.zonePos = Int(value) ?? e.zonePos
        case "CONTROLLER":    e.controller = Int(value) ?? e.controller
        case "CARDTYPE":      e.cardType = value
        default: break
        }
    }

    // MARK: – Bob (tavern) detection

    private func checkForBob(_ e: Entity) {
        guard bobEntityId == nil || bobEntityId == e.id else { return }
        // Bob the bartender's hero card. Do NOT match "TB_BaconShop_HERO_*" —
        // that prefix belongs to the PLAYER-selectable heroes.
        guard e.cardId.contains("TB_BaconShopBob") else { return }
        bobEntityId = e.id
        if e.controller > 0, bobControllerId != e.controller {
            bobControllerId = e.controller
            onDiagnostic?("🍺 酒館控制者 = 玩家 \(e.controller)")
        }
    }

    // MARK: – Shop recompute (debounced — shop refresh creates 3–7 entities in a burst)

    private func scheduleRecompute() {
        pendingRecompute?.cancel()
        pendingRecompute = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.recomputeShop()
        }
    }

    private func recomputeShop() {
        guard isShopping else { emitIfChanged([:]); return }

        // Tavern controller must be known; without it we cannot separate the
        // shop from the player's own board.
        guard let bob = bobControllerId else { return }

        let minions = entities.values
            .filter {
                $0.zone == "PLAY" &&
                $0.controller == bob &&
                $0.cardType == "MINION" &&
                $0.id != bobEntityId &&
                !$0.cardId.isEmpty
            }
            .sorted { $0.zonePos < $1.zonePos }

        var shop: [Int: String] = [:]
        for (i, e) in minions.prefix(7).enumerated() { shop[i] = e.cardId }
        emitIfChanged(shop)
    }

    private func emitIfChanged(_ shop: [Int: String]) {
        let signature = shop.sorted { $0.key < $1.key }
                            .map { "\($0.key):\($0.value)" }
                            .joined(separator: ",")
        guard signature != lastShopSignature else { return }
        lastShopSignature = signature
        onDiagnostic?("🛍️ 商店更新：\(shop.count) 張卡 [\(signature)]")
        onShopChanged?(shop)
    }

    // MARK: – Field extraction

    private struct BracketFields {
        var id: Int
        var cardId: String
        var zone: String
        var zonePos: Int
        var controller: Int
    }

    // Extracts the fields between the FIRST '[' and the LAST ']' that precedes
    // any trailing " tag=" clause. entityName may itself contain a nested
    // bracket ("[cardType=INVALID]"), so first-']' scanning is not safe.
    private func bracketFields(in line: String) -> BracketFields? {
        let searchRegion: Substring
        if let tagRange = line.range(of: " tag=") {
            searchRegion = line[..<tagRange.lowerBound]
        } else {
            searchRegion = line[...]
        }
        guard let open = searchRegion.firstIndex(of: "["),
              let close = searchRegion.lastIndex(of: "]"),
              open < close else { return nil }
        let inner = String(searchRegion[searchRegion.index(after: open)..<close])
        guard let id = intValue(after: " id=", in: " " + inner) else { return nil }
        return BracketFields(
            id: id,
            cardId: stringValue(after: "cardId=", in: inner) ?? "",
            zone: stringValue(after: "zone=", in: inner) ?? "",
            zonePos: intValue(after: "zonePos=", in: inner) ?? 0,
            controller: intValue(after: "player=", in: inner) ?? 0
        )
    }

    private func stringValue(after key: String, in s: String) -> String? {
        guard let r = s.range(of: key) else { return nil }
        let token = s[r.upperBound...].prefix { !$0.isWhitespace && $0 != "]" }
        return token.isEmpty ? nil : String(token)
    }

    private func intValue(after key: String, in s: String) -> Int? {
        guard let str = stringValue(after: key, in: s) else { return nil }
        return Int(str.prefix { $0.isNumber || $0 == "-" })
    }
}
