import AppKit
import IOKit
import UserNotifications
import ServiceManagement

final class AccessoryView: NSView {
    private let titleLabel = label("", size: 20, weight: .bold)
    private let subtitleLabel = label("", size: 12, color: Palette.secondary)
    private let icon = NSImageView()
    private let rings = NSStackView()
    private let ringPanel = NSView()
    private let info = CardView(title: String(localized: "Gerät"), symbol: "info.circle.fill")
    private let hint = label("", size: 11, color: Palette.secondary)
    private var ringViews: [RingView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.contentTintColor = NSColor(white: 0.3, alpha: 1)
        let titles = NSStackView(views: [titleLabel, subtitleLabel])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 2
        let header = NSStackView(views: [icon, titles, NSView()])
        header.spacing = 12

        ringPanel.wantsLayer = true
        ringPanel.layer?.backgroundColor = Palette.card.cgColor
        ringPanel.layer?.cornerRadius = 12
        ringPanel.layer?.borderWidth = 1
        ringPanel.layer?.borderColor = Palette.border.cgColor
        rings.spacing = 30
        rings.translatesAutoresizingMaskIntoConstraints = false
        ringPanel.addSubview(rings)
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping

        let main = NSStackView(views: [header, ringPanel, info, hint])
        main.orientation = .vertical; main.alignment = .leading; main.spacing = 14
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        for v in [header, ringPanel, info, hint] { v.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            main.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            main.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            ringPanel.heightAnchor.constraint(equalToConstant: 190),
            rings.centerXAnchor.constraint(equalTo: ringPanel.centerXAnchor),
            rings.centerYAnchor.constraint(equalTo: ringPanel.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ a: Accessory) {
        titleLabel.stringValue = a.name
        subtitleLabel.stringValue = [a.model, String(localized: "Bluetooth")].joined(separator: " · ")
        icon.image = NSImage(systemSymbolName: a.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .light))

        let levels = a.levels
        if ringViews.count != levels.count {
            ringViews.forEach { $0.removeFromSuperview() }
            ringViews = levels.map { _ in
                let r = RingView()
                r.translatesAutoresizingMaskIntoConstraints = false
                r.widthAnchor.constraint(equalToConstant: 148).isActive = true
                r.heightAnchor.constraint(equalToConstant: 148).isActive = true
                rings.addArrangedSubview(r)
                return r
            }
        }
        for (r, (k, v)) in zip(ringViews, levels) {
            r.caption = k.uppercased()
            r.value = "\(v) %"
            r.detail = ""
            r.fraction = CGFloat(v) / 100
            r.color = Palette.charge(v, charging: false)
        }

        var rows: [(String, String)] = [(String(localized: "Modell"), a.model)]
        if let s = a.serial { rows.append((String(localized: "Seriennummer"), s)) }
        if let s = a.serialLeft { rows.append((String(localized: "Seriennummer links"), s)) }
        if let s = a.serialRight { rows.append((String(localized: "Seriennummer rechts"), s)) }
        if let f = a.firmware { rows.append((String(localized: "Firmware"), f)) }
        if let f = a.caseFirmware, f != a.firmware { rows.append((String(localized: "Firmware Case"), f)) }
        rows.append((String(localized: "Bluetooth-Adresse"), a.id))
        if let r = a.rssi { rows.append((String(localized: "Signalstärke"), String(localized: "\(r) dBm"))) }
        info.setRows(rows)

        hint.stringValue = a.left != nil || a.right != nil
            ? String(localized: "Akkustand kommt über Bluetooth. Der Case-Wert aktualisiert sich, wenn ein Ohrhörer im Case liegt und es kurz geöffnet wird. Gesundheit und Ladezyklen geben AirPods nicht heraus.")
            : String(localized: "Akkustand kommt über Bluetooth. Gesundheit und Ladezyklen gibt dieses Zubehör nicht heraus.")
    }
}
