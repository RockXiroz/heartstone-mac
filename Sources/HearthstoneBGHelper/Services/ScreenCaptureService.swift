import Foundation
import CoreGraphics
import ScreenCaptureKit

// Periodically takes a full-display screenshot via SCScreenshotManager and feeds
// each frame to the OCR pipeline. Polling (vs. streaming) is far more reliable:
// captureImage returns a CGImage directly — no delegate callbacks, no IOSurface
// conversion, no actor-isolation bridging that can silently drop frames.
@MainActor
final class ScreenCaptureService: NSObject {

    static let shared = ScreenCaptureService()

    private var filter: SCContentFilter?
    private var config: SCStreamConfiguration?
    private var pollTimer: Timer?
    private var isCapturing = false

    private(set) var latestFrame: CGImage?
    private(set) var windowFrame: CGRect = .zero

    var onNewFrame: ((CGImage, CGRect) -> Void)?
    var onStreamError: ((Error) -> Void)?

    // MARK: – Setup

    func requestPermissionAndStart() async throws {
        // Triggers the Screen Recording permission dialog and gives us the display list.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Prefer the display where Hearthstone is running, else the largest display.
        guard let display = bestDisplay(from: content) else {
            throw CaptureError.noDisplayFound
        }

        windowFrame = display.frame

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width  = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        self.filter = filter
        self.config = config

        // Take one screenshot immediately to verify the pipeline, then poll.
        try await captureOnce()
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isCapturing = false
    }

    // MARK: – Polling

    private func startPolling() {
        pollTimer?.invalidate()
        // 0.4s ≈ 2.5 fps — plenty for shop recognition, light on CPU.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.captureTick() }
        }
    }

    private func captureTick() async {
        guard !isCapturing else { return }   // skip if a capture is still in flight
        isCapturing = true
        defer { isCapturing = false }
        try? await captureOnce()
    }

    private func captureOnce() async throws {
        // ScreenCaptureService is currently unused (card detection uses Power.log).
        // SCScreenshotManager requires macOS 14+; guard here to keep the project
        // targeting macOS 13.
        guard #available(macOS 14.0, *) else { return }
        guard let filter, let config else { return }
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
        latestFrame = image
        onNewFrame?(image, windowFrame)
    }

    // MARK: – Display selection

    private func bestDisplay(from content: SCShareableContent) -> SCDisplay? {
        if let app = content.applications.first(where: isHearthstoneApp),
           let window = content.windows.first(where: { $0.owningApplication?.processID == app.processID }),
           let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) {
            return display
        }
        return content.displays.max(by: { $0.frame.width < $1.frame.width })
    }

    private func isHearthstoneApp(_ app: SCRunningApplication) -> Bool {
        let bundle = app.bundleIdentifier.lowercased()
        let name   = app.applicationName.lowercased()
        return bundle.contains("hearthstone") || name.contains("hearthstone")
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
        case noDisplayFound
        var errorDescription: String? {
            "找不到可用的螢幕顯示器。請確認螢幕錄製權限已開啟。"
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
