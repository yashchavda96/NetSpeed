import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem?.saveUsage()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
