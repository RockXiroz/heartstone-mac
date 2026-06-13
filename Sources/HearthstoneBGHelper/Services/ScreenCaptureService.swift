import Foundation
import CoreGraphics
import IOSurface
import ScreenCaptureKit

// Captures frames from the primary display.
// Uses SCShareableContent only to trigger the Screen Recording permission prompt,
// then uses CGDisplayStream for actual frame delivery — it is lower-level, has no
// actor-isolation bridging issues, and reliably delivers IOSurface-backed frames.
@MainActor
final class ScreenCaptureService: NSObject {

    static let shared = ScreenCaptureService()

    private var displayStream: CGDisplayStream?
    private(set) var latestFrame: CGImage?
    private(set) var windowFrame: CGRect = .zero

    var onNewFrame: ((CGImage, CGRect) -> Void)?
    var onStreamError: ((Error) -> Void)?

    // MARK: – Setup

    func requestPermissionAndStart() async throws {
        // SCShareableContent triggers the Screen Recording permission dialog.
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        let displayID = CGMainDisplayID()
        windowFrame   = CGDisplayBounds(displayID)

        // Capture at half native resolution — enough for OCR, half the bandwidth.
        let pixW = CGDisplayPixelsWide(displayID)
        let pixH = CGDisplayPixelsHigh(displayID)
        let outW = max(1280, pixW / 2)
        let outH = max(720,  pixH / 2)

        let props: CFDictionary = [
            CGDisplayStream.minimumFrameTime: Double(1.0 / 4.0),  // 4 fps
            CGDisplayStream.showCursor:       false,
        ] as [String: Any] as CFDictionary

        let stream = CGDisplayStream(
            dispatchQueueDisplay: displayID,
            outputWidth:  outW,
            outputHeight: outH,
            pixelFormat:  Int32(kCVPixelFormatType_32BGRA),
            properties:   props,
            queue:        .global(qos: .userInitiated)
        ) { [weak self] status, _, surface, _ in
            guard status == .frameComplete, let surface else { return }
            self?.handleSurface(surface)
        }

        guard let stream else { throw CaptureError.streamCreateFailed }
        guard stream.start() == .success else { throw CaptureError.streamStartFailed }
        displayStream = stream
    }

    func stop() {
        displayStream?.stop()
        displayStream = nil
    }

    // MARK: – Frame handler

    private func handleSurface(_ surface: IOSurface) {
        // Lock → copy all bytes into owned Data → unlock.
        // CGDataProvider(data:) retains our Data, so the resulting CGImage
        // is safe to use after the surface is recycled.
        surface.lock(options: .readOnly, seed: nil)
        let w           = surface.width
        let h           = surface.height
        let bytesPerRow = surface.bytesPerRow
        let data        = Data(bytes: surface.baseAddress, count: bytesPerRow * h)
        surface.unlock(options: .readOnly, seed: nil)

        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: w, height: h,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue:
                    CGImageAlphaInfo.noneSkipFirst.rawValue |
                    CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return }

        Task { @MainActor in
            self.latestFrame = image
            self.onNewFrame?(image, self.windowFrame)
        }
    }

    // MARK: – Screen helper

    var captureScreen: NSScreen {
        let best = NSScreen.screens.max {
            $0.frame.intersection(windowFrame).area < $1.frame.intersection(windowFrame).area
        }
        return best ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: – Crop helper

    func crop(normalised rect: CGRect) -> CGImage? {
        guard let frame = latestFrame else { return nil }
        let w = CGFloat(frame.width)
        let h = CGFloat(frame.height)
        let pixelRect = CGRect(x: rect.minX * w, y: rect.minY * h,
                               width: rect.width * w, height: rect.height * h)
        return frame.cropping(to: pixelRect)
    }

    // MARK: – Errors

    enum CaptureError: LocalizedError {
        case streamCreateFailed, streamStartFailed
        var errorDescription: String? {
            switch self {
            case .streamCreateFailed: return "無法建立 CGDisplayStream。請確認螢幕錄製權限。"
            case .streamStartFailed:  return "CGDisplayStream 啟動失敗。"
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
