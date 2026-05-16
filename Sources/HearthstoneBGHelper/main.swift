import AppKit

// Entry point – must not use @main because Package.swift uses executableTarget
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon; lives in menu bar only
app.run()
