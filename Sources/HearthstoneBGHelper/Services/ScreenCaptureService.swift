import Foundation
import ScreenCaptureKit
import CoreGraphics

// Captures frames from the Hearthstone game window using ScreenCaptureKit (macOS 12.3+).
@MainActor
final class ScreenCaptureService: NSObject, SCStreamDelegate, SCStreamOutput {

    static let shared = ScreenCaptureService()

    private var stream: SCStream?
    private var hearthstoneWindow: SCWindow?
    private(set) var latestFrame: CGImage?
    private(set) var windowFrame: CGRect = .zero

    var onNewFrame: ((CGImage, CGRect) -> Void)?

    // MARK: – Setup

    func requestPermissionAndStart() async throws {
        // Trigger the system permission prompt.
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let (window, app, display) = await findHearthstone() else {
            throw CaptureError.hearthstoneNotRunning
        }
        hearthstoneWindow = window
        windowFrame = display.frame          // use display frame for full-screen accuracy
        try await startStream(app: app, display: display)
    }

    func stop() {
        Task { try? await stream?.stopCapture() }
        stream = nil
    }

    // MARK: – Stream

    // Returns (window, app, display) for Hearthstone, or nil if not found.
    private func findHearthstone() async -> (SCWindow, SCRunningApplication, SCDisplay)? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else { return nil }

        // Identify the Hearthstone app first (works even when window list is incomplete
        // for full-screen apps).
        guard let app = content.applications.first(where: { isHearthstoneApp($0) }) else {
            return nil
        }

        // Find any window owned by that app (may have zero frame when full-screen – that's OK).
        let window = content.windows.first { $0.owningApplication?.processID == app.processID }

        // Find which display the app is on; default to main display.
        let display: SCDisplay
        if let w = window, let d = content.displays.first(where: { $0.frame.intersects(w.frame) }) {
            display = d
        } else if let d = content.displays.max(by: { $0.frame.width < $1.frame.width }) {
            display = d     // largest display – most likely where the game is
        } else {
            return nil
        }

        // The window value is only used to store a reference; the app filter drives capture.
        // Fall back to any available window when full-screen hides the real one.
        guard let resolvedWindow = window ?? content.windows.first else { return nil }

        return (resolvedWindow, app, display)
    }

    private func isHearthstoneApp(_ app: SCRunningApplication) -> Bool {
        let bundle = app.bundleIdentifier.lowercased()
        let name   = app.applicationName.lowercased()
        return bundle.contains("hearthstone") || name.contains("hearthstone")
    }

    // Capture the display filtered to only the Hearthstone process.
    // This is the most reliable method for both windowed and full-screen modes.
    private func startStream(app: SCRunningApplication, display: SCDisplay) async throws {
        let filter = SCContentFilter(
            display: display,
            includingApplications: [app],
            exceptingWindows: []
        )
        let config = SCStreamConfiguration()
        config.width  = Int(display.frame.width)
        config.height = Int(display.frame.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 4)   // 4 fps
        config.queueDepth = 2
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try await newStream.startCapture()
        stream = newStream
    }

    // MARK: – SCStreamOutput

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let width  = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        guard let base = CVPixelBufferGetBaseAddress(imageBuffer) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let context = CGContext(
            data: base,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ), let image = context.makeImage() else { return }

        Task { @MainActor in
            self.latestFrame = image
            self.onNewFrame?(image, self.windowFrame)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureService] Stream stopped: \(error)")
        Task { @MainActor in self.stream = nil }
    }

    // MARK: – Frame cropping helpers

    // Crop a normalised region [0,1] from the latest frame
    func crop(normalised rect: CGRect) -> CGImage? {
        guard let frame = latestFrame else { return nil }
        let w = CGFloat(frame.width)
        let h = CGFloat(frame.height)
        let pixelRect = CGRect(
            x: rect.minX * w, y: rect.minY * h,
            width: rect.width * w, height: rect.height * h
        )
        return frame.cropping(to: pixelRect)
    }

    enum CaptureError: LocalizedError {
        case hearthstoneNotRunning
        var errorDescription: String? {
            switch self {
            case .hearthstoneNotRunning:
                return "找不到爐石傳說視窗，請先啟動遊戲。"
            }
        }
    }
}
