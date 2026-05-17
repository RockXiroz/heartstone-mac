import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlayWindow: OverlayWindow?
    private var overlayVC: OverlayViewController?
    private var hudWindow: HUDWindow?
    private let capture = ScreenCaptureService.shared
    private let tracker = GameStateTracker.shared
    private var statusItem: NSStatusItem?

    // MARK: – Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        Task { await startCapture() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    // MARK: – Screen capture

    private func startCapture() async {
        do {
            try await capture.requestPermissionAndStart()
            setupOverlay(on: capture.captureScreen)

            capture.onNewFrame = { [weak self] image, frame in
                Task { @MainActor in
                    // frame here is the SCCapture display rect used only for OCR coordinate mapping.
                    // The overlay window stays pinned to the screen frame set at startup.
                    self?.tracker.processFrame(image, windowFrame: frame)
                }
            }
        } catch {
            showPermissionError(error)
        }
    }

    // MARK: – Overlay setup

    private func setupOverlay(on screen: NSScreen) {
        // HUD – always-visible recommendation panel in the top-right corner
        let hud = HUDWindow(screen: screen)
        hudWindow = hud

        // Transparent arrow overlay covering the full game screen
        let overlay = OverlayWindow(screen: screen)
        let vc = OverlayViewController()
        overlay.contentViewController = vc
        overlay.orderFrontRegardless()
        overlayWindow = overlay
        overlayVC = vc
    }

    // MARK: – Menu bar icon

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "BG Helper")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "爐石英雄戰場助手", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "關於", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "設定種族池…", action: #selector(showTribeConfig), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: – Menu actions

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "爐石英雄戰場助手"
        alert.informativeText = """
        即時分析英雄戰場商店，推薦最佳購買選擇。

        勝率計算考量因素：
        • HSReplay 真實勝率數據
        • 己方陣容的種族協同
        • 當前場次的可用種族
        • 後期成長性與搭配空間
        • 對手陣容的反制策略

        版本 1.0 · macOS 13+
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }

    @objc private func showTribeConfig() {
        TribeConfigWindow.show { [weak self] tribes in
            self?.tracker.setActiveTribePool(tribes)
        }
    }

    private func showPermissionError(_ error: Error) {
        // "Game not found" is retryable – don't quit, just show a notice and poll.
        if case ScreenCaptureService.CaptureError.hearthstoneNotRunning = error {
            let alert = NSAlert()
            alert.messageText = "找不到爐石傳說視窗"
            alert.informativeText = "請確認遊戲已開啟並進入英雄戰場。\n助手將每 5 秒自動重試。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "立即重試")
            alert.addButton(withTitle: "結束")
            if alert.runModal() == .alertFirstButtonReturn {
                Task { await self.startCapture() }
            } else {
                NSApp.terminate(nil)
            }
            return
        }

        // Actual SCStream / permission error – direct user to System Settings.
        let alert = NSAlert()
        alert.messageText = "無法啟動螢幕擷取"
        alert.informativeText = "請至「系統設定 → 隱私權與安全性 → 螢幕錄製」授予本程式權限，然後重新啟動。\n\n錯誤：\(error.localizedDescription)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "開啟系統設定")
        alert.addButton(withTitle: "結束")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        NSApp.terminate(nil)
    }
}

// MARK: – Tribe configuration window

final class TribeConfigWindow {

    static func show(completion: @escaping (Set<Tribe>) -> Void) {
        let panel = NSAlert()
        panel.messageText = "設定本場次種族池"
        panel.informativeText = "請選擇本場次包含的 5 個種族（遊戲開始時可在卡牌選擇界面確認）"

        let checkboxStack = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        checkboxStack.orientation = .vertical
        checkboxStack.alignment = .leading
        checkboxStack.spacing = 6

        let activatable: [Tribe] = [.beast, .demon, .dragon, .elemental, .mech,
                                    .murloc, .naga, .pirate, .quilboar, .undead, .titan]
        var checkboxes: [Tribe: NSButton] = [:]

        for tribe in activatable {
            let cb = NSButton(checkboxWithTitle: tribe.displayName, target: nil, action: nil)
            cb.state = .on
            checkboxStack.addArrangedSubview(cb)
            checkboxes[tribe] = cb
        }

        panel.accessoryView = checkboxStack
        panel.addButton(withTitle: "確認")
        panel.addButton(withTitle: "取消")

        if panel.runModal() == .alertFirstButtonReturn {
            let selected = Set(checkboxes.compactMap { tribe, cb in
                cb.state == .on ? tribe : nil
            })
            completion(selected)
        }
    }
}
