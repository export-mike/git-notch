import AppKit

// Git Notch — an agent app that lives around the MacBook notch and surfaces
// GitHub PRs that need your attention. No dock icon, no menu-bar item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
