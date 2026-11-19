import AppKit
import IOKit
import UserNotifications
import ServiceManagement

func label(_ s: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    t.font = .systemFont(ofSize: size, weight: weight)
    t.textColor = color
    t.lineBreakMode = .byTruncatingTail
    return t
}

final class RingView: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var value = "–" { didSet { needsDisplay = true } }
    var caption = "" { didSet { needsDisplay = true } }
    var detail = "" { didSet { needsDisplay = true } }
    var color = Palette.green { didSet { needsDisplay = true } }
    var symbol: String? { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 150) }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let lw: CGFloat = 11
        let rect = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side).insetBy(dx: lw / 2 + 1, dy: lw / 2 + 1)
        let c = NSPoint(x: rect.midX, y: rect.midY), r = rect.width / 2

        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lw
        Palette.track.setStroke()
        track.stroke()

        let f = min(1, max(0, fraction))
        if f > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
            arc.lineWidth = lw
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }

        let v = NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor.labelColor])
        let cap = NSAttributedString(string: caption, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: Palette.secondary])
        let det = NSAttributedString(string: detail, attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: Palette.secondary])
        let vs = v.size(), cs = cap.size(), ds = det.size()
        v.draw(at: NSPoint(x: c.x - vs.width / 2, y: c.y - vs.height / 2 + 4))
        cap.draw(at: NSPoint(x: c.x - cs.width / 2, y: c.y + vs.height / 2 + 2))
        det.draw(at: NSPoint(x: c.x - ds.width / 2, y: c.y - vs.height / 2 - ds.height + 2))

        if let s = symbol, let img = NSImage(systemSymbolName: s, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .bold)) {
            let tinted = NSImage(size: img.size, flipped: false) { rr in
                img.draw(in: rr); self.color.set(); rr.fill(using: .sourceAtop); return true
            }
            tinted.draw(at: NSPoint(x: c.x - img.size.width / 2, y: rect.minY + lw + 10), from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

final class CardView: NSView {
    private let stack = NSStackView()
    private var values: [String: NSTextField] = [:]
    private(set) var keys: [String] = []

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Palette.card.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))!)
        icon.contentTintColor = Palette.blue
        let head = NSStackView(views: [icon, label(title, size: 13, weight: .semibold)])
        head.spacing = 6

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.addArrangedSubview(head)
        stack.setCustomSpacing(10, after: head)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setRows(_ rows: [(String, String)]) {
        if rows.map(\.0) != keys {
            stack.arrangedSubviews.dropFirst().forEach { $0.removeFromSuperview() }
            values.removeAll()
            keys = rows.map(\.0)
            for (i, (k, _)) in rows.enumerated() {
                let l = label(k, color: Palette.secondary)
                let v = label("", weight: .medium)
                v.alignment = .right
                v.isSelectable = true
                let row = NSStackView(views: [l, NSView(), v])
                row.translatesAutoresizingMaskIntoConstraints = false
                row.edgeInsets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                values[k] = v
                if i < rows.count - 1 {
                    let sep = NSBox(); sep.boxType = .separator
                    stack.addArrangedSubview(sep)
                    sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                }
            }
        }
        for (k, v) in rows { values[k]?.stringValue = v }
    }
}

final class DeviceView: NSView {
    let titleLabel = label("", size: 20, weight: .bold)
    let subtitleLabel = label("", size: 12, color: Palette.secondary)
    let statusLabel = label("", size: 12, weight: .medium)
    let statusDot = NSView()
    let icon = NSImageView()
    let chargeRing = RingView()
    let healthRing = RingView()
    let leftCard: CardView
    let rightCard: CardView
    let bottomCard: CardView
    let hintLabel = label("", size: 11, color: Palette.secondary)
    let actionButton = NSButton(title: String(localized: "Im Verlauf speichern"), target: nil, action: nil)

    init(icon symbol: String, cards: [(String, String)]) {
        leftCard = CardView(title: cards[0].0, symbol: cards[0].1)
        rightCard = CardView(title: cards[1].0, symbol: cards[1].1)
        bottomCard = CardView(title: cards[2].0, symbol: cards[2].1)
        super.init(frame: .zero)

        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .light))
        icon.contentTintColor = NSColor(white: 0.3, alpha: 1)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2

        let titles = NSStackView(views: [titleLabel, subtitleLabel])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 2
        let status = NSStackView(views: [statusDot, statusLabel]); status.spacing = 6
        let header = NSStackView(views: [icon, titles, NSView(), status, actionButton])
        header.spacing = 12
        header.setCustomSpacing(18, after: status)

        let rings = NSStackView(views: [chargeRing, healthRing])
        rings.spacing = 26
        for r in [chargeRing, healthRing] {
            r.translatesAutoresizingMaskIntoConstraints = false
            r.widthAnchor.constraint(equalToConstant: 148).isActive = true
            r.heightAnchor.constraint(equalToConstant: 148).isActive = true
        }
        let ringPanel = NSView()
        ringPanel.wantsLayer = true
        ringPanel.layer?.backgroundColor = Palette.card.cgColor
        ringPanel.layer?.cornerRadius = 12
        ringPanel.layer?.borderWidth = 1
        ringPanel.layer?.borderColor = Palette.border.cgColor
        rings.translatesAutoresizingMaskIntoConstraints = false
        ringPanel.addSubview(rings)
        NSLayoutConstraint.activate([
            rings.centerXAnchor.constraint(equalTo: ringPanel.centerXAnchor),
            rings.centerYAnchor.constraint(equalTo: ringPanel.centerYAnchor),
        ])

        let topRow = NSStackView(views: [ringPanel, leftCard])
        topRow.distribution = .fillEqually; topRow.spacing = 14; topRow.alignment = .top
        let bottomRow = NSStackView(views: [rightCard, bottomCard])
        bottomRow.distribution = .fillEqually; bottomRow.spacing = 14; bottomRow.alignment = .top

        let main = NSStackView(views: [header, topRow, bottomRow, hintLabel])
        main.orientation = .vertical; main.alignment = .leading; main.spacing = 14
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        for v in [header, topRow, bottomRow, hintLabel] { v.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            main.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            main.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            ringPanel.heightAnchor.constraint(equalTo: leftCard.heightAnchor),
            ringPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),
            rightCard.heightAnchor.constraint(equalTo: bottomCard.heightAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusDot.layer?.backgroundColor = color.cgColor
    }

    func setCharge(_ percent: Int?, mah: Int?, charging: Bool) {
        let p = percent ?? 0
        chargeRing.caption = String(localized: "LADUNG")
        chargeRing.value = percent.map { "\($0) %" } ?? "–"
        chargeRing.detail = mah.map { String(localized: "\($0) mAh") } ?? ""
        chargeRing.fraction = CGFloat(p) / 100
        chargeRing.color = Palette.charge(p, charging: charging)
        chargeRing.symbol = charging ? "bolt.fill" : nil
    }

    func setHealth(_ h: Double?, full: Int?, design: Int?) {
        healthRing.caption = String(localized: "GESUNDHEIT")
        if let h = h {
            healthRing.value = String(format: "%.1f %%", h * 100)
            healthRing.detail = String(localized: "\(full ?? 0) / \(design ?? 0) mAh")
            healthRing.fraction = CGFloat(min(1, h))
            healthRing.color = Palette.health(h)
        } else {
            healthRing.value = "–"; healthRing.detail = String(localized: "nicht verfügbar"); healthRing.fraction = 0
        }
    }
}
