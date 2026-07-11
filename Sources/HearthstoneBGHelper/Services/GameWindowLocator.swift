import Foundation
import CoreGraphics

// Finds the Hearthstone window's on-screen bounds so shop-slot geometry can be
// anchored to the actual game window (which may be windowed, not full-screen).
// CGWindowListCopyWindowInfo exposes owner name and bounds without any special
// permission (only window *titles* are permission-gated).
enum GameWindowLocator {

    // Returns the game window frame in global top-left-origin coordinates,
    // or nil if Hearthstone has no visible window.
    static func findHearthstoneWindow() -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var best: CGRect?
        for w in info {
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            guard owner.lowercased().contains("hearthstone") else { continue }
            guard let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            // Skip tiny helper/splash windows; keep the largest real window.
            guard rect.width > 400, rect.height > 300 else { continue }
            if best == nil || rect.width * rect.height > best!.width * best!.height {
                best = rect
            }
        }
        return best
    }
}
