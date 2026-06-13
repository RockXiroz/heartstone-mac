import Foundation

// Locates Hearthstone's log directory, installs the log.config that enables
// Power/Zone logging, and tails Power.log line-by-line. This is the same
// mechanism Hearthstone Deck Tracker and Firestone use — far more reliable than
// screen OCR because it reports exact card IDs in real time.
//
// IMPORTANT: log.config only takes effect when Hearthstone (re)starts. The first
// time the helper runs it installs the config and asks the user to restart the game.
@MainActor
final class HearthstoneLogService {

    static let shared = HearthstoneLogService()

    /// Emits each new line appended to Power.log.
    var onLine: ((String) -> Void)?
    /// Emits diagnostic status (config installed, waiting for log, tailing…).
    var onStatus: ((String) -> Void)?

    private var handle: FileHandle?
    private var offset: UInt64 = 0
    private var pollTimer: Timer?
    private var currentLogURL: URL?

    private let fm = FileManager.default

    // MARK: – Paths

    private var home: URL { fm.homeDirectoryForCurrentUser }

    // Mac log output directory (FilePrinting=true writes here).
    private var logDirCandidates: [URL] {
        [
            home.appendingPathComponent("Library/Logs/Hearthstone"),
            // Older installs wrote alongside the app bundle.
            URL(fileURLWithPath: "/Applications/Hearthstone/Logs")
        ]
    }

    private var logConfigURL: URL {
        home.appendingPathComponent("Library/Preferences/Blizzard/Hearthstone/log.config")
    }

    // MARK: – Public

    func start() {
        installLogConfigIfNeeded()
        onStatus?("🔍 搜尋 Hearthstone 紀錄檔…")
        // Power.log may not exist until the next game launch; poll until it appears.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        tick()
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        try? handle?.close(); handle = nil
        currentLogURL = nil
    }

    // MARK: – Config install

    private func installLogConfigIfNeeded() {
        let dir = logConfigURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Categories required for Battlegrounds state tracking.
        let required = ["Power", "Zone", "LoadingScreen", "Bob", "Asset"]
        let existing = (try? String(contentsOf: logConfigURL, encoding: .utf8)) ?? ""

        // Only rewrite if a required section is missing (avoid clobbering user tweaks).
        let missing = required.filter { !existing.contains("[\($0)]") }
        guard !missing.isEmpty else { return }

        var config = existing
        for section in missing {
            config += """

            [\(section)]
            LogLevel=1
            FilePrinting=true
            ConsolePrinting=false
            ScreenPrinting=false
            Verbose=true

            """
        }
        try? config.write(to: logConfigURL, atomically: true, encoding: .utf8)
        onStatus?("⚙️ 已安裝紀錄設定，請重新啟動 Hearthstone 以套用。")
    }

    // MARK: – Tail loop

    private func tick() {
        if handle == nil {
            guard let url = locatePowerLog() else {
                onStatus?("⏳ 等待 Hearthstone 產生 Power.log（請確認已重新啟動遊戲）…")
                return
            }
            openTail(at: url)
        }
        readAppended()
    }

    private func locatePowerLog() -> URL? {
        for dir in logDirCandidates {
            let direct = dir.appendingPathComponent("Power.log")
            if fm.fileExists(atPath: direct.path) { return direct }

            // Some versions write per-session subfolders (e.g. Hearthstone_<timestamp>/Power.log).
            if let subs = try? fm.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) {
                let powerLogs = subs.map { $0.appendingPathComponent("Power.log") }
                                    .filter { fm.fileExists(atPath: $0.path) }
                if let newest = powerLogs.max(by: { modDate($0) < modDate($1) }) {
                    return newest
                }
            }
        }
        return nil
    }

    private func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func openTail(at url: URL) {
        try? handle?.close()
        guard let h = try? FileHandle(forReadingFrom: url) else { return }
        handle = h
        currentLogURL = url
        // Start from the end — we only care about the current/upcoming game.
        let end = (try? h.seekToEnd()) ?? 0
        offset = end
        onStatus?("📖 正在讀取 \(url.lastPathComponent)（即時追蹤中）")
    }

    private func readAppended() {
        guard let h = handle, let url = currentLogURL else { return }

        // Detect rotation/truncation: if the file shrank, reopen from start.
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        if let size = (attrs?[.size] as? NSNumber)?.uint64Value, size < offset {
            offset = 0
            try? h.seek(toOffset: 0)
        }

        try? h.seek(toOffset: offset)
        let data = h.readDataToEndOfFile()
        offset = (try? h.offset()) ?? offset
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

        for line in chunk.split(separator: "\n", omittingEmptySubsequences: true) {
            onLine?(String(line))
        }
    }
}
