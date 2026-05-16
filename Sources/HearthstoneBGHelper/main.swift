import AppKit

// Top-level code runs on the main actor so it can safely create @MainActor types.
MainApp.run()

@MainActor
enum MainApp {
    static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon; lives in menu bar only
        app.run()
    }
}
