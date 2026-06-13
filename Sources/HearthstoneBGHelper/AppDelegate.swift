import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlayWindow: OverlayWindow?
    private var overlayVC: OverlayViewController?
    private var hudWindow: HUDWindow?
    private let tracker = GameStateTracker.shared
    private let logService = HearthstoneLogService.shared
    private let parser = PowerLogParser()
    private var statusItem: NSStatusItem?

    // MARK: – Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        tracker.screenSize = screen.frame.size
        setupOverlay(on: screen)
        startLogTracking()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    // MARK: – Log tracking pipeline

    private func startLogTracking() {
        // Power.log line → parser → shop card IDs → recommendation
        parser.onShopChanged = { [weak self] cardIDs in
            Task { @MainActor in self?.tracker.updateShop(cardIDs: cardIDs) }
        }
        parser.onDiagnostic = { msg in
            print("[Parser] \(msg)")
        }

        logService.onLine = { [weak self] line in
            Task { @MainActor in self?.parser.ingest(line) }
        }
        logService.onStatus = { [weak self] status in
            Task { @MainActor in self?.tracker.logStatus(status) }
        }
        logService.start()
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
