import AppKit

// Entry point of "Biblia Clásica" (AppKit, macOS 10.13+). No storyboards/xibs: everything is built in code.
// No Swift Concurrency here: it needs the 10.15 runtime. Use GCD / callbacks.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
