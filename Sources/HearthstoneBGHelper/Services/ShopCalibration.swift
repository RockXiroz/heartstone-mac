import Foundation
import CoreGraphics

// User-measured shop geometry, stored as fractions of the game window so it
// survives window moves and proportional resizes. Captured by clicking the
// centre of the leftmost and rightmost visible shop cards once.
// All coordinates are in global TOP-LEFT space (CGWindow convention).
struct ShopCalibration: Codable {

    var firstX: CGFloat        // centre X of the first clicked card ÷ window width
    var firstY: CGFloat        // centre Y ÷ window height
    var spacing: CGFloat       // per-slot X distance ÷ window width
    var firstZonePos: Int      // zonePos of the first clicked card

    // Card hit-box size derived from spacing.
    var slotWidthFraction:  CGFloat { spacing * 0.85 }
    var slotHeightFraction: CGFloat { spacing * 1.45 }

    func rect(forZonePos pos: Int, in frame: CGRect) -> CGRect {
        let cx = frame.minX + (firstX + CGFloat(pos - firstZonePos) * spacing) * frame.width
        let cy = frame.minY + firstY * frame.height
        let w  = slotWidthFraction  * frame.width
        let h  = slotHeightFraction * frame.width   // spacing is width-relative
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    // MARK: – Persistence

    private static let defaultsKey = "shopCalibration.v1"

    static func load() -> ShopCalibration? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ShopCalibration.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
