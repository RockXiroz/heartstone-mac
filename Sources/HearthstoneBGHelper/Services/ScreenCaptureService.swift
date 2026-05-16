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
        // iOS-style permission check; on macOS this prompts the user in System Settings
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let window = await findHearthstoneWindow() else {
            throw CaptureError.hearthstoneNotRunning
        }
        hearthstoneWindow = window
        windowFrame = window.frame
        try await startStream(for: window)
    }

    func stop() {
        Task { try? await stream?.stopCapture() }
        stream = nil
    }

    // MARK: – Stream

    private func findHearthstoneWindow() async -> SCWindow? {
        // Try on-screen windows first, then all windows (catches full-screen / other Spaces).
        for onScreenOnly in [true, false] {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: onScreenOnly
            ) else { continue }

            if let w = content.windows.first(where: { isHearthstone($0) }) {
                return w
            }
        }
        return nil
    }

    private func isHearthstone(_ w: SCWindow) -> Bool {
        let app = w.owningApplication
        // Match by bundle ID (most reliable) or by display name / window title.
        let bundleMatch = app?.bundleIdentifier.lowercased().contains("hearthstone") == true
        let nameMatch   = app?.applicationName.lowercased().contains("hearthstone") == true
        let titleMatch  = w.title?.lowercased().contains("hearthstone") == true
        return bundleMatch || nameMatch || titleMatch
    }

    private func startStream(for window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width  = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 4)  // 4 fps – enough for UI
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
