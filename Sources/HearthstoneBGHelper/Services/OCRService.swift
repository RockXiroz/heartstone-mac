import Vision
import CoreGraphics
import Foundation

// Uses the Vision framework to read card names and game info from screen captures.
final class OCRService {

    static let shared = OCRService()

    // MARK: – Layout constants (normalised to window size, tuned for 1920×1080)
    // These values work at any resolution because they're ratios.

    private struct Layout {
        // Shop slots: 7 possible positions in the bottom-centre of the screen
        // Slots are evenly spaced; each card name label is ~8% of screen width
        static let shopSlotCount = 7
        // Row of card name text labels sits roughly at 87–94% of screen height
        static let shopNameY: CGFloat      = 0.87
        static let shopNameHeight: CGFloat = 0.06
        // First slot X centre, last slot X centre
        static let shopFirstX: CGFloat     = 0.21
        static let shopLastX: CGFloat      = 0.79
        static let shopCardWidth: CGFloat  = 0.09

        // Board – player's minions occupy ~0.40–0.60 height, full width
        static let boardY: CGFloat      = 0.40
        static let boardHeight: CGFloat = 0.18

        // Tavern tier badge – top-left area
        static let tavernTierRegion = CGRect(x: 0.03, y: 0.06, width: 0.07, height: 0.07)

        // Gold counter – top-right area
        static let goldRegion = CGRect(x: 0.87, y: 0.06, width: 0.07, height: 0.06)
    }

    // MARK: – Public

    // Returns (slot index → card name) for currently visible shop cards
    func extractShopCardNames(from image: CGImage) async -> [Int: String] {
        var results: [Int: String] = [:]
        let slotXCentres = computeShopSlotCentres()

        await withTaskGroup(of: (Int, String?).self) { group in
            for (i, xCentre) in slotXCentres.enumerated() {
                let rect = CGRect(
                    x: xCentre - Layout.shopCardWidth / 2,
                    y: Layout.shopNameY,
                    width: Layout.shopCardWidth,
                    height: Layout.shopNameHeight
                )
                group.addTask { [weak self] in
                    guard let self else { return (i, nil) }
                    let text = await self.recogniseText(in: image, normalisedRegion: rect)
                    return (i, text.isEmpty ? nil : text)
                }
            }
            for await (i, name) in group {
                if let name { results[i] = name }
            }
        }
        return results
    }

    func extractTavernTier(from image: CGImage) async -> Int? {
        let raw = await recogniseText(in: image, normalisedRegion: Layout.tavernTierRegion)
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func extractGold(from image: CGImage) async -> Int? {
        let raw = await recogniseText(in: image, normalisedRegion: Layout.goldRegion)
        let digits = raw.filter(\.isNumber)
        return Int(digits)
    }

    // MARK: – Core OCR

    func recogniseText(in image: CGImage, normalisedRegion region: CGRect) async -> String {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)

        // Vision uses bottom-left origin; CGImage uses top-left
        let visionRect = CGRect(
            x: region.minX,
            y: 1 - region.maxY,
            width: region.width,
            height: region.height
        )

        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: " "))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hant"]
            request.regionOfInterest = visionRect
            _ = w; _ = h  // suppress unused warnings

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: – Helpers

    private func computeShopSlotCentres() -> [CGFloat] {
        guard Layout.shopSlotCount > 1 else { return [0.5] }
        let step = (Layout.shopLastX - Layout.shopFirstX) / CGFloat(Layout.shopSlotCount - 1)
        return (0..<Layout.shopSlotCount).map { Layout.shopFirstX + CGFloat($0) * step }
    }
}
