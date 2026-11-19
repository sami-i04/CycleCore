import AppKit
import IOKit
import UserNotifications
import ServiceManagement

final class MainController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let size = NSSize(width: 980, height: 660)
    let window: NSWindow
    private let sidebar = NSTableView()
    private let settingsButton = NSButton()
    private let content = NSView()
    private var items: [SidebarItem] = []
    private var selected: SidebarItem = .mac

    private let macView = DeviceView(icon: "laptopcomputer", cards: [(String(localized: "Akku"), "battery.75percent"), (String(localized: "Netzteil & Leistung"), "powerplug.fill"), (String(localized: "Mac"), "info.circle.fill")])
    private let iosView = DeviceView(icon: "iphone", cards: [(String(localized: "Akku"), "battery.75percent"), (String(localized: "Laden"), "bolt.fill"), (String(localized: "Gerät"), "info.circle.fill")])
    private let emptyIOS = NSView()
    private let historyView = HistoryView()
    private let settingsView = SettingsView()
    private let accessoryView = AccessoryView()

    override init() {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "CycleCore"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.background
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        let col = NSTableColumn(identifier: .init("c")); col.width = 210
        sidebar.addTableColumn(col)
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.backgroundColor = .clear
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.rowSizeStyle = .custom
        let scroll = NSScrollView()
        scroll.documentView = sidebar
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false

        let side = NSVisualEffectView()
        side.material = .sidebar
        side.blendingMode = .behindWindow
        side.state = .active
        let brand = label("CycleCore", size: 15, weight: .bold)
        let brandIcon = NSImageView(image: NSImage(systemSymbolName: "battery.100percent.bolt", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))!)
        brandIcon.contentTintColor = Palette.green
        let brandRow = NSStackView(views: [brandIcon, brand]); brandRow.spacing = 6

        settingsButton.title = "  " + String(localized: "Einstellungen")
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        settingsButton.imagePosition = .imageLeft
        settingsButton.bezelStyle = .recessed
        settingsButton.setButtonType(.pushOnPushOff)
        settingsButton.showsBorderOnlyWhileMouseInside = true
        settingsButton.alignment = .left
        settingsButton.contentTintColor = NSColor(white: 0.3, alpha: 1)
        settingsButton.target = self
        settingsButton.action = #selector(settingsClicked)
        let bottomSep = NSBox(); bottomSep.boxType = .separator

        for v in [brandRow, scroll, bottomSep, settingsButton] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; side.addSubview(v) }
        NSLayoutConstraint.activate([
            settingsButton.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -12),
            settingsButton.bottomAnchor.constraint(equalTo: side.bottomAnchor, constant: -12),
            settingsButton.heightAnchor.constraint(equalToConstant: 30),
            bottomSep.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 12),
            bottomSep.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -12),
            bottomSep.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -8),
        ])

        let root = NSView()
        let divider = NSBox(); divider.boxType = .separator
        for v in [side, divider, content] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.background.cgColor

        NSLayoutConstraint.activate([
            side.topAnchor.constraint(equalTo: root.topAnchor),
            side.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            side.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            side.widthAnchor.constraint(equalToConstant: 230),
            brandRow.topAnchor.constraint(equalTo: side.topAnchor, constant: 40),
            brandRow.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 20),
            scroll.topAnchor.constraint(equalTo: brandRow.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: side.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: side.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomSep.topAnchor, constant: -6),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: side.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        window.contentView = root
        window.setContentSize(Self.size)
        window.minSize = window.frame.size
        window.maxSize = window.frame.size

        let e1 = NSImageView(image: NSImage(systemSymbolName: "iphone.slash", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 48, weight: .ultraLight))!)
        e1.contentTintColor = Palette.secondary
        let e2 = label(String(localized: "Kein iPhone oder iPad verbunden"), size: 15, weight: .semibold)
        let e3 = label(String(localized: "Per USB anschließen und „Diesem Computer vertrauen“ bestätigen.\nIm WLAN: Gerät im Finder unter „Dieses Gerät im WLAN anzeigen“ freigeben."),
                       size: 12, color: Palette.secondary)
        e3.alignment = .center; e3.maximumNumberOfLines = 3; e3.lineBreakMode = .byWordWrapping
        let es = NSStackView(views: [e1, e2, e3]); es.orientation = .vertical; es.spacing = 10
        es.translatesAutoresizingMaskIntoConstraints = false
        emptyIOS.addSubview(es)
        NSLayoutConstraint.activate([es.centerXAnchor.constraint(equalTo: emptyIOS.centerXAnchor),
                                     es.centerYAnchor.constraint(equalTo: emptyIOS.centerYAnchor, constant: -30)])

        macView.actionButton.target = self; macView.actionButton.action = #selector(saveMac)
        iosView.actionButton.target = self; iosView.actionButton.action = #selector(saveIOS)
        historyView.onChange = { [weak self] in self?.reloadSidebar(); self?.showSelected() }

        reloadSidebar()
        select(.mac)
        window.center()
    }

    func reloadSidebar() {
        var list: [SidebarItem] = [.header(String(localized: "GERÄTE")), .mac]
        for d in MobileDeviceManager.shared.info.values.sorted(by: { $0.name < $1.name }) { list.append(.ios(d.id)) }
        let acc = AccessoryManager.shared.devices
        if !acc.isEmpty {
            list.append(.header(String(localized: "ZUBEHÖR")))
            list += acc.map { .accessory($0.id) }
        }
        let hist = HistoryStore.shared.devices
        if !hist.isEmpty {
            list.append(.header(String(localized: "VERLAUF")))
            list += hist.map { .history($0.serial) }
        }
        items = list
        sidebar.reloadData()
        if selected != .settings, !items.contains(selected) { selected = .mac }
        if let i = items.firstIndex(of: selected) { sidebar.selectRowIndexes([i], byExtendingSelection: false) }
        else { sidebar.deselectAll(nil) }
        settingsButton.state = selected == .settings ? .on : .off
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = items[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = items[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = items[row] { return 26 }
        return 36
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch items[row] {
        case .header(let t):
            let l = label(t, size: 10, weight: .semibold, color: Palette.secondary)
            let v = NSView(); l.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(l)
            NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
                                         l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4)])
            return v
        case .mac:
            return cell("laptopcomputer", MacInfo.name, lastMac.map { "\($0.percent) % · " + String(format: NSLocalizedString("%.0f %% Gesundheit", comment: ""), $0.health * 100) } ?? String(localized: "Dieser Mac"), Palette.blue)
        case .ios(let id):
            let d = MobileDeviceManager.shared.info[id]
            let sub = [d?.batteryPercent.map { "\($0) %" }, d?.wifi == true ? "WLAN" : "USB"].compactMap { $0 }.joined(separator: " · ")
            return cell(deviceSymbol(kind: "ios", model: d?.productType), d?.name ?? String(localized: "iOS-Gerät"), sub, Palette.blue)
        case .accessory(let id):
            let a = AccessoryManager.shared.devices.first { $0.id == id }
            return cell(a?.symbol ?? "headphones", a?.name ?? String(localized: "Zubehör"), a?.summary ?? "", Palette.blue)
        case .history(let serial):
            let e = HistoryStore.shared.entries(forSerial: serial).last
            let n = HistoryStore.shared.entries(forSerial: serial).count
            return cell(deviceSymbol(kind: e?.kind, model: e?.model), e?.device ?? serial, String(localized: "\(n) Einträge"), NSColor(white: 0.4, alpha: 1))
        case .settings:
            return cell("gearshape", String(localized: "Einstellungen"), "", NSColor(white: 0.4, alpha: 1))
        }
    }

    private func cell(_ symbol: String, _ title: String, _ sub: String, _ tint: NSColor) -> NSView {
        let c = SidebarCell()
        c.icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        c.icon.contentTintColor = tint
        c.title.stringValue = title
        c.sub.stringValue = sub
        c.sub.isHidden = sub.isEmpty
        return c
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let r = sidebar.selectedRow
        guard r >= 0, r < items.count else { return }
        selected = items[r]
        settingsButton.state = .off
        showSelected()
    }

    @objc private func settingsClicked() { select(.settings) }

    func select(_ item: SidebarItem) {
        selected = item
        if let i = items.firstIndex(of: item) { sidebar.selectRowIndexes([i], byExtendingSelection: false) }
        else { sidebar.deselectAll(nil) }
        settingsButton.state = item == .settings ? .on : .off
        showSelected()
    }

    private func setContent(_ v: NSView) {
        guard v.superview !== content else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        v.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: content.topAnchor), v.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: content.leadingAnchor), v.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
    }

    func showSelected() {
        switch selected {
        case .mac: setContent(macView); updateMac(lastMac)
        case .ios(let id):
            if let d = MobileDeviceManager.shared.info[id] { setContent(iosView); updateIOS(d) } else { setContent(emptyIOS) }
        case .history(let s): setContent(historyView); historyView.show(serial: s)
        case .accessory(let id):
            if let a = AccessoryManager.shared.devices.first(where: { $0.id == id }) { setContent(accessoryView); accessoryView.show(a) }
            else { select(.mac) }
        case .settings: setContent(settingsView)
        case .header: break
        }
    }

    private(set) var lastMac: MacBattery?

    func updateMac(_ b: MacBattery?) {
        lastMac = b
        if let i = items.firstIndex(of: .mac) { sidebar.reloadData(forRowIndexes: [i], columnIndexes: [0]) }
        guard selected == .mac else { return }
        let v = macView
        v.titleLabel.stringValue = MacInfo.name
        v.subtitleLabel.stringValue = "\(MacInfo.marketingName) · \(MacInfo.model)"
        let (macDate, macDateSource) = MacInfo.manufactureDate(batteryDate: b?.manufactureDate)
        v.bottomCard.setRows([
            (String(localized: "Modell"), MacInfo.marketingName),
            (String(localized: "Kennung"), MacInfo.model),
            (String(localized: "Chip"), MacInfo.cpu),
            ("macOS", MacInfo.osVersion.replacingOccurrences(of: "Version ", with: "")),
            (String(localized: "Seriennummer"), MacInfo.serial),
            (String(localized: "Hauptplatine"), MacInfo.boardSerial ?? "–"),
            (String(localized: "Herstellungsdatum"), Fmt.date(macDate) + (macDateSource.isEmpty ? "" : " (\(macDateSource))")),
            (String(localized: "Alter"), Fmt.age(macDate)),
        ])
        guard let b = b, b.present else {
            v.setCharge(nil, mah: nil, charging: false)
            v.setHealth(nil, full: nil, design: nil)
            v.setStatus(String(localized: "Kein Akku"), color: Palette.secondary)
            v.leftCard.setRows([(String(localized: "Akku"), String(localized: "Dieser Mac hat keinen internen Akku"))])
            v.rightCard.setRows([(String(localized: "Netzteil"), "–")])
            return
        }
        v.setCharge(b.percent, mah: b.currentCapacity, charging: b.isCharging)
        v.setHealth(b.health, full: b.fullChargeCapacity, design: b.designCapacity)
        if b.fullyCharged { v.setStatus(String(localized: "Vollständig geladen"), color: Palette.green) }
        else if b.isCharging { v.setStatus(String(localized: "Wird geladen · noch \(Fmt.minutes(b.timeRemaining))"), color: Palette.green) }
        else if b.externalConnected { v.setStatus(String(localized: "Am Netzteil, lädt nicht"), color: Palette.orange) }
        else { v.setStatus(String(localized: "Akkubetrieb · noch \(Fmt.minutes(b.timeRemaining))"), color: Palette.blue) }

        v.leftCard.setRows([
            (String(localized: "Ladezyklen"), String(localized: "\(b.cycleCount) von \(b.designCycleCount)")),
            (String(localized: "Maximale Kapazität"), Fmt.mah(b.fullChargeCapacity)),
            (String(localized: "Design-Kapazität"), Fmt.mah(b.designCapacity)),
            (String(localized: "Temperatur"), Fmt.temp(b.temperature)),
            (String(localized: "Hersteller"), b.manufacturer),
            (String(localized: "Seriennummer"), b.serial),
            (String(localized: "Herstellungsdatum"), Fmt.date(b.manufactureDate)),
            (String(localized: "Akku-Alter"), Fmt.age(b.manufactureDate)),
        ])
        var power: [(String, String)] = []
        if b.externalConnected {
            power.append((String(localized: "Netzteil"), [b.adapterWatts.map { "\($0) W" }, b.adapterName].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? String(localized: "Angeschlossen")))
            if let m = b.adapterManufacturer { power.append((String(localized: "Hersteller"), m)) }
            if let av = b.adapterVoltage, let ac = b.adapterCurrent { power.append((String(localized: "Netzteil-Ausgang"), String(format: "%.1f V · %.2f A", av, ac))) }
        } else {
            power.append((String(localized: "Netzteil"), String(localized: "Nicht angeschlossen")))
        }
        power.append((b.amperage >= 0 ? String(localized: "Ladeleistung") : String(localized: "Entladeleistung"), String(format: "%.1f W", abs(b.power))))
        power.append((String(localized: "Spannung"), String(format: "%.2f V", b.voltage)))
        power.append((String(localized: "Stromstärke"), String(localized: "\(b.amperage) mA")))
        if let l = b.systemLoad { power.append((String(localized: "Systemverbrauch"), String(format: "%.1f W", l))) }
        if !b.cellVoltages.isEmpty { power.append((String(localized: "Zellspannungen"), b.cellVoltages.map { String(format: "%.2f", Double($0) / 1000) }.joined(separator: " / ") + " V")) }
        v.rightCard.setRows(power)
        v.hintLabel.stringValue = ""
    }

    func updateIOS(_ d: IOSDevice) {
        let v = iosView
        v.titleLabel.stringValue = d.name
        v.subtitleLabel.stringValue = String(localized: "\(d.productType) · iOS \(d.osVersion) · \(d.wifi ? String(localized: "WLAN") : "USB")")
        v.icon.image = NSImage(systemSymbolName: deviceSymbol(kind: "ios", model: d.productType), accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .light))
        v.setCharge(d.batteryPercent, mah: d.currentCapacity, charging: d.isCharging == true)
        v.setHealth(d.health, full: d.fullChargeCapacity, design: d.designCapacity)
        if d.isCharging == true { v.setStatus(String(localized: "Wird geladen"), color: Palette.green) }
        else if d.externalConnected == true { v.setStatus(String(localized: "Angeschlossen"), color: Palette.orange) }
        else { v.setStatus(String(localized: "Akkubetrieb"), color: Palette.blue) }

        v.leftCard.setRows([
            (String(localized: "Ladezyklen"), d.cycleCount.map(String.init) ?? "–"),
            (String(localized: "Maximale Kapazität"), Fmt.mah(d.fullChargeCapacity)),
            (String(localized: "Design-Kapazität"), Fmt.mah(d.designCapacity)),
            (String(localized: "Temperatur"), Fmt.temp(d.temperature)),
            (String(localized: "Akku-Seriennummer"), d.batterySerial ?? "–"),
            (String(localized: "Herstellungsdatum"), Fmt.date(d.manufactureDate)),
            (String(localized: "Akku-Alter"), Fmt.age(d.manufactureDate)),
        ])
        v.rightCard.setRows([
            (String(localized: "Status"), d.isCharging == true ? String(localized: "Lädt") : (d.externalConnected == true ? String(localized: "Angeschlossen") : String(localized: "Nicht angeschlossen"))),
            (String(localized: "Ladegerät"), d.adapterWatts.map { "\($0) W" } ?? "–"),
            (String(localized: "Spannung"), d.voltage.map { String(format: "%.2f V", $0) } ?? "–"),
            (String(localized: "Stromstärke"), d.amperage.map { String(localized: "\($0) mA") } ?? "–"),
            (String(localized: "Leistung"), (d.voltage != nil && d.amperage != nil) ? String(format: "%.1f W", abs(d.voltage! * Double(d.amperage!) / 1000)) : "–"),
        ])
        v.bottomCard.setRows([
            (String(localized: "Name"), d.name),
            (String(localized: "Modell"), d.productType),
            (String(localized: "Modellnummer"), d.modelNumber.isEmpty ? "–" : d.modelNumber),
            ("iOS-Version", d.osVersion),
            (String(localized: "Seriennummer"), d.serial),
            (String(localized: "Verbindung"), d.wifi ? "WLAN" : "USB"),
        ])
        v.hintLabel.stringValue = d.diagnosticsError.map {
            String(localized: "\($0): Gerät entsperren und per USB verbinden, damit Zyklen und Kapazität gelesen werden können.")
        } ?? ""
    }

    func accessoriesChanged() {
        reloadSidebar()
        if case .accessory = selected { showSelected() }
    }

    func iosChanged() {
        reloadSidebar()
        if case .ios = selected { showSelected() }
    }

    @objc private func saveMac() { (NSApp.delegate as? AppDelegate)?.saveMacSnapshot(manual: true) }

    @objc private func saveIOS() {
        guard case .ios(let id) = selected, let d = MobileDeviceManager.shared.info[id], d.serial != "–" else { return }
        HistoryStore.shared.add(IOSEntry(d))
        reloadSidebar()
    }
}
