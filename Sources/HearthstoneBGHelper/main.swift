import AppKit

// main.swift top-level code is always called on the main thread.
// assumeIsolated makes the compiler aware of that so @MainActor types can be used here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // no Dock icon; lives in menu bar only
    app.run()
}
