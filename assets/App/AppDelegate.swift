import AppKit
import IOKit
import UserNotifications
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var main: MainController!
    private var statusItem: NSStatusItem!
    private var notifiedFull = false
    private var notifiedLow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        NSApp.appearance = NSAppearance(named: .aqua)
        setupMenu()
        main = MainController()
        main.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupStatusItem()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        MobileDeviceManager.shared.onChange = { [weak self] in
            self?.main.iosChanged()
            self?.autoSaveIOS()
        }
        MobileDeviceManager.shared.start()

        AccessoryManager.shared.onChange = { [weak self] in self?.main.accessoriesChanged() }
        AccessoryManager.shared.refresh()
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in AccessoryManager.shared.refresh() }

        refresh()
        saveMacSnapshot(manual: false)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MobileDeviceManager.shared.refresh()
            self?.saveMacSnapshot(manual: false)
        }
    }

    private func setupMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let m = NSMenu()
        m.addItem(withTitle: String(localized: "Über CycleCore"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: String(localized: "Einstellungen …"), action: #selector(openSettings), keyEquivalent: ",").target = self
        m.addItem(.separator())
        m.addItem(withTitle: String(localized: "CycleCore ausblenden"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        m.addItem(withTitle: String(localized: "CycleCore beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = m
        let winItem = NSMenuItem(); bar.addItem(winItem)
        let w = NSMenu(title: String(localized: "Fenster"))
        w.addItem(withTitle: String(localized: "Schließen"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        w.addItem(withTitle: String(localized: "Im Dock ablegen"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = w
        NSApp.mainMenu = bar
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "cycleCoreStatusItem"
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "CycleCore öffnen"), action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showWindow() {
        main.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() { showWindow(); main.select(.settings) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }

    func refresh() {
        let b = MacBattery.read()
        main.updateMac(b)
        updateStatusItem(b)
        checkNotifications(b)
    }

    private func updateStatusItem(_ b: MacBattery?) {
        guard let button = statusItem.button else { return }
        var sym = "powerplug"
        if let b = b, b.present {
            sym = b.isCharging ? "battery.100percent.bolt"
                : b.percent > 75 ? "battery.100percent" : b.percent > 50 ? "battery.75percent"
                : b.percent > 25 ? "battery.50percent" : b.percent > 10 ? "battery.25percent" : "battery.0percent"
            button.title = Settings.menuBarPercent ? " \(b.percent) %" : ""
            button.toolTip = String(format: NSLocalizedString(String(localized: "Ladung %d %% · Gesundheit %.1f %% · %d Zyklen"), comment: ""), b.percent, b.health * 100, b.cycleCount)
        } else { button.title = "" }
        let img = NSImage(systemSymbolName: sym, accessibilityDescription: String(localized: "Akku"))
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeft
    }

    private func checkNotifications(_ b: MacBattery?) {
        guard let b = b, b.present else { return }
        if Settings.notifyFull, b.externalConnected, b.percent >= Settings.notifyFullLevel {
            if !notifiedFull { notify(String(localized: "Akku geladen"), String(localized: "Der Akku ist zu \(b.percent) % geladen. Du kannst das Netzteil trennen.")) }
            notifiedFull = true
        } else if b.percent < Settings.notifyFullLevel - 2 || !b.externalConnected { notifiedFull = false }
        if Settings.notifyLow, !b.externalConnected, b.percent <= Settings.notifyLowLevel {
            if !notifiedLow { notify(String(localized: "Akku fast leer"), String(localized: "Nur noch \(b.percent) %. Bitte Netzteil anschließen.")) }
            notifiedLow = true
        } else if b.percent > Settings.notifyLowLevel + 2 || b.externalConnected { notifiedLow = false }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func saveMacSnapshot(manual: Bool) {
        guard let b = main.lastMac ?? MacBattery.read(), b.present else { return }
        let e = HistoryEntry(date: Date(), device: MacInfo.name, serial: MacInfo.serial, kind: "mac", model: MacInfo.marketingName,
                             percent: b.percent, fullCapacity: b.fullChargeCapacity, designCapacity: b.designCapacity, cycles: b.cycleCount)
        let before = HistoryStore.shared.entries.count
        if manual { HistoryStore.shared.add(e) } else if Settings.autoHistory { HistoryStore.shared.addDailyIfNeeded(e) }
        if HistoryStore.shared.entries.count != before { main.reloadSidebar() }
    }

    private func autoSaveIOS() {
        guard Settings.autoHistory else { return }
        let before = HistoryStore.shared.entries.count
        for d in MobileDeviceManager.shared.info.values where d.serial != "–" {
            HistoryStore.shared.addDailyIfNeeded(IOSEntry(d))
        }
        if HistoryStore.shared.entries.count != before { main.reloadSidebar() }
    }
}
