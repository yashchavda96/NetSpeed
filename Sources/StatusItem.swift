import AppKit
import Network
import ServiceManagement

/// The menu bar item: draws the current speeds once a second and owns the dropdown menu.
final class StatusItem: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let meter = TrafficMeter()
    private let usage = Usage()
    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private var isOnline = true
    private var isTestingSpeed = false
    private var lastSpeedTest: (result: SpeedTest.Result?, date: Date)?
    private var isMenuOpen = false
    private var drawnReadout: Readout?

    private let todayItem = NSMenuItem()
    private let monthItem = NSMenuItem()
    private let sessionItem = NSMenuItem()
    private let speedTestResultItem = NSMenuItem()
    private lazy var speedTestItem = menuItem("Run Speed Test", #selector(runSpeedTest))
    private var displayModeItems: [NSMenuItem] = []
    private lazy var bitsItem = menuItem("Show Speed in Bits (Mbps)", #selector(toggleBits))
    private lazy var loginItem = menuItem("Launch at Login", #selector(toggleLaunchAtLogin))

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowsNonnumericFormatting = false  // "0 bytes", not "Zero KB"
        return formatter
    }()

    /// Lines the values up in a column after the labels ("Today", "This Month", ...).
    private let infoAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 90)]
        return [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: style]
    }()

    override init() {
        super.init()
        item.menu = makeMenu()
        refreshReadout()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            usage.add(meter.sample())
            refreshReadout()
            if isMenuOpen { refreshMenu() }
        }
        timer.tolerance = 0.1
        // Common modes keep it firing while the menu is open, so the numbers stay live.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = path.status == .satisfied
            self?.updateSpeedTestTitle()
        }
        pathMonitor.start(queue: .main)
    }

    func saveUsage() {
        usage.save()
    }

    private func refreshReadout() {
        let unit = Preferences.speedUnit
        let readout = makeReadout(unit: unit)
        // Redrawing the menu bar item is most of this app's CPU cost, so skip it when
        // nothing visible has changed (e.g. while idle).
        if readout != drawnReadout {
            item.button?.image = image(for: readout)
            drawnReadout = readout
        }

        let toolTip = "Upload \(unit.format(meter.uploadRate)) · Download \(unit.format(meter.downloadRate))"
        if item.button?.toolTip != toolTip {
            item.button?.toolTip = toolTip
        }
    }

    private func refreshMenu() {
        let unit = Preferences.speedUnit
        setInfo(todayItem, "Today", usageText(usage.today))
        setInfo(monthItem, "This Month", usageText(usage.thisMonth))
        setInfo(sessionItem, "Since Launch", usageText(meter.total))

        if let (result, date) = lastSpeedTest {
            if let result {
                setInfo(speedTestResultItem, "Last Test", "↓ \(unit.format(result.download))   ↑ \(unit.format(result.upload))")
                speedTestResultItem.toolTip = "Tested at \(date.formatted(date: .omitted, time: .shortened))"
            } else {
                setInfo(speedTestResultItem, "Last Test", "Failed. Check your connection and try again.")
            }
        }
    }

    private func usageText(_ counts: ByteCounts) -> String {
        let received = byteFormatter.string(fromByteCount: Int64(clamping: counts.received))
        let sent = byteFormatter.string(fromByteCount: Int64(clamping: counts.sent))
        return "↓ \(received)   ↑ \(sent)"
    }

    private func setInfo(_ menuItem: NSMenuItem, _ label: String, _ value: String) {
        menuItem.attributedTitle = NSAttributedString(string: "\(label)\t\(value)", attributes: infoAttributes)
    }

    // MARK: - Drawing

    /// Everything that determines what the menu bar item looks like.
    private struct Readout: Equatable {
        let lines: [String]
        let mode: DisplayMode
        let unit: SpeedUnit
        let height: CGFloat
    }

    private func makeReadout(unit: SpeedUnit) -> Readout {
        let mode = Preferences.displayMode
        let readings: [(arrow: String, rate: Double)]
        switch mode {
        case .stacked: readings = [("↑", meter.uploadRate), ("↓", meter.downloadRate)]
        case .singleLine: readings = [("↓", meter.downloadRate), ("↑", meter.uploadRate)]
        case .downloadOnly: readings = [("↓", meter.downloadRate)]
        case .uploadOnly: readings = [("↑", meter.uploadRate)]
        }

        // Under 1 KB/s is just background chatter. When nothing shown is transferring, say
        // "idle" once instead of listing near-zero speeds.
        let lines = readings.allSatisfy { $0.rate < 1000 }
            ? ["idle"]
            : readings.map { "\($0.arrow) \(unit.format($0.rate))" }
        return Readout(lines: lines, mode: mode, unit: unit, height: NSStatusBar.system.thickness)
    }

    /// A template image, so macOS tints it to match light and dark menu bars.
    private func image(for readout: Readout) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: readout.mode == .stacked ? 9 : 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let isIdle = readout.lines == ["idle"]
        // "idle" is drawn faded (a template image keeps partial opacity).
        let lines = readout.lines.map {
            NSAttributedString(string: $0, attributes: isIdle
                ? attributes.merging([.foregroundColor: NSColor.black.withAlphaComponent(0.45)]) { $1 }
                : attributes)
        }

        // Reserve room for the widest possible reading, so the item keeps the same width
        // as the numbers change and neighbouring menu bar icons don't shift.
        let column = readout.unit.labels
            .map { NSAttributedString(string: "↑ 99.9 \($0)", attributes: attributes).size().width }
            .max()
            .map(ceil) ?? 0
        let gap: CGFloat = 8
        let width = readout.mode == .singleLine ? column * 2 + gap : column
        let height = readout.height

        return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if readout.mode == .stacked && !isIdle {
                // Two 9pt lines fill a 22pt bar; centre them on taller bars (notched Macs).
                let bottom = (height - 22) / 2
                lines[0].draw(at: NSPoint(x: 0, y: bottom + 11))
                lines[1].draw(at: NSPoint(x: 0, y: bottom + 0.5))
            } else {
                for (index, line) in lines.enumerated() {
                    let size = line.size()
                    let x = isIdle ? ((width - size.width) / 2).rounded() : CGFloat(index) * (column + gap)
                    line.draw(at: NSPoint(x: x, y: ((height - size.height) / 2).rounded()))
                }
            }
            return true
        }.asTemplate()
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        for info in [todayItem, monthItem, sessionItem] {
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(menuItem("Reset Usage…", #selector(resetUsage)))
        menu.addItem(.separator())

        menu.addItem(speedTestItem)
        speedTestResultItem.isEnabled = false
        speedTestResultItem.isHidden = true
        menu.addItem(speedTestResultItem)
        menu.addItem(.separator())

        let displayMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let modeItem = menuItem(mode.title, #selector(selectDisplayMode))
            modeItem.representedObject = mode.rawValue
            displayMenu.addItem(modeItem)
            displayModeItems.append(modeItem)
        }
        displayMenu.addItem(.separator())
        displayMenu.addItem(bitsItem)
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit NetSpeed", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // Update the menu whenever it opens. Launch at Login in particular can be turned off
    // from System Settings while the app is running.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
        for modeItem in displayModeItems {
            modeItem.state = modeItem.representedObject as? String == Preferences.displayMode.rawValue ? .on : .off
        }
        bitsItem.state = Preferences.speedUnit == .bits ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem === speedTestItem ? isOnline && !isTestingSpeed : true
    }

    private func updateSpeedTestTitle() {
        speedTestItem.title = isTestingSpeed ? "Testing Speed…"
            : isOnline ? "Run Speed Test"
            : "Run Speed Test (Offline)"
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let mode = (sender.representedObject as? String).flatMap(DisplayMode.init) else { return }
        Preferences.displayMode = mode
        refreshReadout()
    }

    @objc private func toggleBits() {
        Preferences.speedUnit = Preferences.speedUnit == .bits ? .bytes : .bits
        refreshReadout()
    }

    @objc private func resetUsage() {
        let alert = NSAlert()
        alert.messageText = "Reset today's and this month's usage?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)  // otherwise the alert opens behind other windows
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        usage.reset()
    }

    @objc private func runSpeedTest() {
        isTestingSpeed = true
        updateSpeedTestTitle()
        SpeedTest.run { [weak self] result in
            guard let self else { return }
            isTestingSpeed = false
            updateSpeedTestTitle()
            lastSpeedTest = (result, Date())
            speedTestResultItem.isHidden = false
            refreshMenu()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

private extension NSImage {
    func asTemplate() -> NSImage {
        isTemplate = true
        return self
    }
}
