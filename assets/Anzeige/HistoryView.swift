import AppKit
import IOKit
import UserNotifications
import ServiceManagement

final class HistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let titleLabel = label("", size: 20, weight: .bold)
    private let subtitleLabel = label("", size: 12, color: Palette.secondary)
    private let icon = NSImageView()
    private let table = NSTableView()
    private let summary = NSStackView()
    private var rows: [HistoryEntry] = []
    private var serial: String?
    var onChange: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.contentTintColor = NSColor(white: 0.3, alpha: 1)
        let titles = NSStackView(views: [titleLabel, subtitleLabel])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 2

        let export = NSButton(title: String(localized: "Exportieren …"), target: self, action: #selector(exportCSV))
        let del = NSButton(title: String(localized: "Eintrag löschen"), target: self, action: #selector(deleteSelected))
        let delAll = NSButton(title: String(localized: "Gerät entfernen"), target: self, action: #selector(deleteDevice))
        let header = NSStackView(views: [icon, titles, NSView(), del, delAll, export])
        header.spacing = 10
        header.setCustomSpacing(12, after: icon)

        summary.distribution = .fillEqually
        summary.spacing = 14

        let cols: [(String, String, CGFloat)] = [("date", String(localized: "Datum"), 150), ("percent", String(localized: "Ladung"), 70), ("full", String(localized: "Max. Kapazität"), 110),
                                                 ("design", String(localized: "Design-Kapazität"), 115), ("health", String(localized: "Gesundheit"), 90), ("cycles", String(localized: "Zyklen"), 70)]
        for (id, title, w) in cols {
            let c = NSTableColumn(identifier: .init(id)); c.title = title; c.width = w
            if id != "date" { c.headerCell.alignment = .right }
            table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowHeight = 22
        table.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = Palette.border.cgColor
        scroll.drawsBackground = true
        scroll.backgroundColor = .white

        let main = NSStackView(views: [header, summary, scroll])
        main.orientation = .vertical; main.alignment = .leading; main.spacing = 14
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        for v in [header, summary, scroll] { v.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            main.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            main.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            main.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func tile(_ title: String, _ value: String, _ sub: String) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = Palette.card.cgColor
        v.layer?.cornerRadius = 12
        v.layer?.borderWidth = 1
        v.layer?.borderColor = Palette.border.cgColor
        let s = NSStackView(views: [label(title.uppercased(), size: 10, weight: .semibold, color: Palette.secondary),
                                    label(value, size: 20, weight: .semibold),
                                    label(sub, size: 11, color: Palette.secondary)])
        s.orientation = .vertical; s.alignment = .leading; s.spacing = 3
        s.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(s)
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
            s.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            s.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -12),
            s.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -10),
        ])
        return v
    }

    func show(serial: String) {
        self.serial = serial
        rows = HistoryStore.shared.entries(forSerial: serial).reversed()
        let last = rows.first, first = rows.last
        titleLabel.stringValue = last?.device ?? String(localized: "Verlauf")
        subtitleLabel.stringValue = [last?.model, String(localized: "Seriennummer \(serial)"), String(localized: "\(rows.count) Einträge")].compactMap { $0 }.joined(separator: " · ")
        icon.image = NSImage(systemSymbolName: deviceSymbol(kind: last?.kind, model: last?.model), accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .light))

        summary.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let l = last, let f = first {
            let dh = (l.health - f.health) * 100
            summary.addArrangedSubview(tile(String(localized: "Gesundheit"), l.designCapacity > 0 ? String(format: "%.1f %%", l.health * 100) : "–",
                                            rows.count > 1 ? String(format: NSLocalizedString("%+.1f %% seit %@", comment: ""), dh, Fmt.date(f.date)) : String(localized: "erster Eintrag")))
            summary.addArrangedSubview(tile(String(localized: "Max. Kapazität"), Fmt.mah(l.fullCapacity), String(localized: "Design: \(Fmt.mah(l.designCapacity))")))
            summary.addArrangedSubview(tile(String(localized: "Ladezyklen"), "\(l.cycles)",
                                            rows.count > 1 ? String(localized: "+\(l.cycles - f.cycles) seit \(Fmt.date(f.date))") : String(localized: "erster Eintrag")))
            let days = max(1, Calendar.current.dateComponents([.day], from: f.date, to: l.date).day ?? 1)
            summary.addArrangedSubview(tile(String(localized: "Aufgezeichnet"), String(localized: "\(days) Tage"), String(localized: "seit \(Fmt.date(f.date))")))
        }
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = rows[row]
        let id = tableColumn?.identifier.rawValue ?? ""
        let s: String
        var color = NSColor.labelColor
        switch id {
        case "date": s = Fmt.dateTime(e.date)
        case "percent": s = "\(e.percent) %"
        case "full": s = Fmt.mah(e.fullCapacity)
        case "design": s = Fmt.mah(e.designCapacity)
        case "health":
            s = e.designCapacity > 0 ? String(format: "%.1f %%", e.health * 100) : "–"
            if e.designCapacity > 0 { color = Palette.health(e.health) }
        default: s = "\(e.cycles)"
        }
        let t = label(s, weight: id == "health" ? .semibold : .regular, color: color)
        t.alignment = id == "date" ? .left : .right
        return t
    }

    @objc private func deleteSelected() {
        let sel = table.selectedRowIndexes.map { rows[$0] }
        guard !sel.isEmpty else { return }
        sel.forEach { HistoryStore.shared.remove($0) }
        onChange?()
    }

    @objc private func deleteDevice() {
        guard let s = serial else { return }
        let a = NSAlert()
        a.messageText = String(localized: "Alle Einträge dieses Geräts löschen?")
        a.addButton(withTitle: String(localized: "Löschen")); a.addButton(withTitle: String(localized: "Abbrechen"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        HistoryStore.shared.removeDevice(serial: s)
        onChange?()
    }

    @objc private func exportCSV() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "\(titleLabel.stringValue)-Verlauf.csv"
        p.allowedContentTypes = [.commaSeparatedText]
        guard p.runModal() == .OK, let url = p.url else { return }
        try? HistoryStore.shared.csv(serial: serial).write(to: url, atomically: true, encoding: .utf8)
    }
}
