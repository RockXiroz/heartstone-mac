import Foundation
import ScreenCaptureKit
import CoreGraphics

// Captures frames from the primary display using ScreenCaptureKit (macOS 12.3+).
// Does NOT require Hearthstone to be detected — starts immediately and lets the OCR
// decide whether it sees a shop. This avoids false "not found" errors for full-screen games.
@MainActor
final class ScreenCaptureService: NSObject, SCStreamDelegate, SCStreamOutput {

    static let shared = ScreenCaptureService()

    private var stream: SCStream?
    private(set) var latestFrame: CGImage?
    private(set) var windowFrame: CGRect = .zero
    private(set) var captureDisplay: SCDisplay?

    var onNewFrame: ((CGImage, CGRect) -> Void)?
    var onStreamError: ((Error) -> Void)?

    // MARK: – Setup

    func requestPermissionAndStart() async throws {
        // This triggers the system Screen Recording permission prompt if not yet granted.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Pick the best display: prefer one with Hearthstone, fall back to largest.
        let display = bestDisplay(from: content)
        guard let display else {
            throw CaptureError.noDisplayFound
        }

        windowFrame     = display.frame
        captureDisplay  = display
        try await startStream(display: display)
    }

    func stop() {
        Task { try? await stream?.stopCapture() }
        stream = nil
    }

    // The NSScreen that corresponds to the display being captured.
    var captureScreen: NSScreen {
        let best = NSScreen.screens.max {
            $0.frame.intersection(windowFrame).area < $1.frame.intersection(windowFrame).area
        }
        return best ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: – Display selection

    private func bestDisplay(from content: SCShareableContent) -> SCDisplay? {
        // Try to find the display where Hearthstone is running.
        if let app = content.applications.first(where: isHearthstoneApp),
           let window = content.windows.first(where: { $0.owningApplication?.processID == app.processID }),
           let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) {
            return display
        }
        // Fall back to the largest display (most likely where the game is).
        return content.displays.max(by: { $0.frame.width < $1.frame.width })
    }

    private func isHearthstoneApp(_ app: SCRunningApplication) -> Bool {
        let bundle = app.bundleIdentifier.lowercased()
        let name   = app.applicationName.lowercased()
        return bundle.contains("hearthstone") || name.contains("hearthstone")
    }

    // MARK: – Stream

    private func startStream(display: SCDisplay) async throws {
        // Capture the entire display — most reliable for full-screen games.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Use pixel dimensions (NOT display.frame which is in logical points).
        config.width  = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 4)  // 4 fps
        config.queueDepth  = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try await newStream.startCapture()
        stream = newStream
    }

    // MARK: – SCStreamOutput

    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)

        let width       = CVPixelBufferGetWidth(imageBuffer)
        let height      = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)

        guard let base = CVPixelBufferGetBaseAddress(imageBuffer) else {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
            return
        }

        // Copy all pixel bytes into our own Data before unlocking the buffer.
        // CGDataProvider(data:) keeps a strong reference to this Data, so the
        // CGImage is valid indefinitely — no dangling pointer.
        let data = Data(bytes: base, count: bytesPerRow * height)
        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)

        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width, height: height,
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

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureService] Stream stopped: \(error)")
        Task { @MainActor in
            self.stream = nil
            self.onStreamError?(error)
        }
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
        case noDisplayFound
        var errorDescription: String? {
            "找不到可用的螢幕顯示器。"
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
