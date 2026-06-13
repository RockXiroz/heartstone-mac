import Foundation

// Parses Hearthstone Power.log lines into a live entity model and extracts the
// set of minions currently offered in Bob's Tavern (the Battlegrounds shop).
//
// Power.log format (stable across versions):
//   FULL_ENTITY - Creating ID=27 CardID=BGS_039
//   FULL_ENTITY - Updating [entityName=X id=27 zone=PLAY zonePos=1 cardId=BGS_039 player=2]
//   SHOW_ENTITY - Updating Entity=[... id=27 zone=DECK ...] CardID=BGS_039
//   TAG_CHANGE Entity=[... id=27 ...] tag=ZONE value=PLAY
//   TAG_CHANGE Entity=[... id=27 ...] tag=ZONE value=HAND
//
// Battlegrounds shop minions live in zone PLAY but are controlled by the
// "tavern" player (a controller id distinct from the local hero). We track each
// entity's zone + controller and expose the tavern's PLAY-zone minions as the shop.
@MainActor
final class PowerLogParser {

    struct Entity {
        var id: Int
        var cardId: String
        var zone: String
        var zonePos: Int
        var controller: Int
    }

    /// Called whenever the detected shop minion set changes.
    /// Provides ordered (slot index → CardID) pairs.
    var onShopChanged: (([Int: String]) -> Void)?
    /// Diagnostic stream (raw card IDs seen, phase changes).
    var onDiagnostic: ((String) -> Void)?

    private var entities: [Int: Entity] = [:]
    private var localController: Int?      // the local player's controller id
    private var lastShopSignature = ""

    // MARK: – Public entry

    func ingest(_ line: String) {
        if line.contains("FULL_ENTITY") {
            parseFullEntity(line)
        } else if line.contains("SHOW_ENTITY") {
            parseShowEntity(line)
        } else if line.contains("TAG_CHANGE") {
            parseTagChange(line)
        } else if line.contains("CREATE_GAME") {
            // New game — reset.
            entities.removeAll(); localController = nil; lastShopSignature = ""
        }
        recomputeShopIfNeeded()
    }

    // MARK: – Line parsers

    // FULL_ENTITY - Creating ID=27 CardID=BGS_039
    // FULL_ENTITY - Updating [entityName=X id=27 zone=PLAY zonePos=1 cardId=BGS_039 player=2]
    private func parseFullEntity(_ line: String) {
        if let bracket = bracketFields(in: line) {
            upsert(from: bracket)
        } else if let id = intValue(after: "ID=", in: line) {
            let cardId = stringValue(after: "CardID=", in: line) ?? ""
            var e = entities[id] ?? Entity(id: id, cardId: "", zone: "", zonePos: 0, controller: 0)
            if !cardId.isEmpty { e.cardId = cardId; diagCard(cardId) }
            entities[id] = e
        }
    }

    // SHOW_ENTITY - Updating Entity=[... id=27 zone=DECK ...] CardID=BGS_039
    private func parseShowEntity(_ line: String) {
        guard let bracket = bracketFields(in: line) else { return }
        var fields = bracket
        // CardID often appears after the bracket for SHOW_ENTITY (hidden→revealed).
        if let cardId = stringValue(after: "CardID=", in: line), !cardId.isEmpty {
            fields.cardId = cardId
        }
        upsert(from: fields)
    }

    // TAG_CHANGE Entity=[... id=27 ...] tag=ZONE value=PLAY
    private func parseTagChange(_ line: String) {
        guard let id = entityID(in: line) else {
            detectLocalController(line); return
        }
        guard var e = entities[id] else {
            detectLocalController(line); return
        }
        if let tag = stringValue(after: "tag=", in: line),
           let value = stringValue(after: "value=", in: line) {
            switch tag {
            case "ZONE":        e.zone = value
            case "ZONE_POSITION": e.zonePos = Int(value) ?? e.zonePos
            case "CONTROLLER":  e.controller = Int(value) ?? e.controller
            default: break
            }
            entities[id] = e
        }
    }

    // The local player's controller is identified when the game tags the
    // controlling player. We capture the first PLAYER controller we see acting.
    private func detectLocalController(_ line: String) {
        // e.g. TAG_CHANGE Entity=GameEntity tag=CURRENT_PLAYER value=1
        // We refine this against real logs; for now leave nil → no controller filter.
        _ = line
    }

    // MARK: – Entity upsert from a bracket field set

    private struct Bracket {
        var id: Int
        var cardId: String
        var zone: String
        var zonePos: Int
        var controller: Int
    }

    private func upsert(from b: Bracket) {
        var e = entities[b.id] ?? Entity(id: b.id, cardId: "", zone: "", zonePos: 0, controller: 0)
        if !b.cardId.isEmpty { e.cardId = b.cardId; diagCard(b.cardId) }
        if !b.zone.isEmpty   { e.zone = b.zone }
        if b.zonePos > 0     { e.zonePos = b.zonePos }
        if b.controller > 0  { e.controller = b.controller }
        entities[b.id] = e
    }

    // MARK: – Shop extraction

    private func recomputeShopIfNeeded() {
        let db = CardDatabase.shared

        // Candidate shop minions: in zone PLAY, CardID resolves to a known BG card.
        // (Refinement seam: once we identify the tavern controller id from real
        //  logs, filter by controller != localController to exclude our own board.)
        let candidates = entities.values
            .filter { $0.zone == "PLAY" && !$0.cardId.isEmpty }
            .filter { db.findCard(byID: $0.cardId) != nil }
            .sorted { $0.zonePos < $1.zonePos }

        guard !candidates.isEmpty else { return }

        var shop: [Int: String] = [:]
        for (i, e) in candidates.prefix(7).enumerated() { shop[i] = e.cardId }

        let signature = shop.sorted { $0.key < $1.key }
                            .map { "\($0.key):\($0.value)" }.joined(separator: ",")
        guard signature != lastShopSignature else { return }
        lastShopSignature = signature
        onShopChanged?(shop)
    }

    // MARK: – Field extraction helpers

    private func bracketFields(in line: String) -> Bracket? {
        guard let open = line.firstIndex(of: "["),
              let close = line[open...].firstIndex(of: "]") else { return nil }
        let inner = String(line[line.index(after: open)..<close])
        guard let id = intValue(after: "id=", in: inner) else { return nil }
        return Bracket(
            id: id,
            cardId: stringValue(after: "cardId=", in: inner) ?? "",
            zone: stringValue(after: "zone=", in: inner) ?? "",
            zonePos: intValue(after: "zonePos=", in: inner) ?? 0,
            controller: intValue(after: "player=", in: inner) ?? 0
        )
    }

    private func entityID(in line: String) -> Int? {
        // TAG_CHANGE Entity=[... id=27 ...]  → grab id inside the bracket.
        if let b = bracketFields(in: line) { return b.id }
        return nil
    }

    private func stringValue(after key: String, in s: String) -> String? {
        guard let r = s.range(of: key) else { return nil }
        let rest = s[r.upperBound...]
        let token = rest.prefix { !$0.isWhitespace && $0 != "]" }
        return token.isEmpty ? nil : String(token)
    }

    private func intValue(after key: String, in s: String) -> Int? {
        guard let str = stringValue(after: key, in: s) else { return nil }
        return Int(str.filter { $0.isNumber || $0 == "-" })
    }

    // MARK: – Diagnostics

    private var seenCards = Set<String>()
    private func diagCard(_ cardId: String) {
        guard !seenCards.contains(cardId) else { return }
        seenCards.insert(cardId)
        let name = CardDatabase.shared.findCard(byID: cardId)?.name ?? "?"
        onDiagnostic?("看到卡牌 \(cardId) → \(name)")
    }
}
