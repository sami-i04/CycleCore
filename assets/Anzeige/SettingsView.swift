import AppKit
import IOKit
import UserNotifications
import ServiceManagement

final class SettingsView: NSView {
    private let fullCheck = NSButton(checkboxWithTitle: String(localized: "Mitteilung, wenn geladen bis"), target: nil, action: nil)
    private let lowCheck = NSButton(checkboxWithTitle: String(localized: "Mitteilung, wenn Ladung fällt unter"), target: nil, action: nil)
    private let fullField = NSPopUpButton()
    private let lowField = NSPopUpButton()
    private let menuCheck = NSButton(checkboxWithTitle: String(localized: "Prozentwert in der Menüleiste anzeigen"), target: nil, action: nil)
    private let fCheck = NSButton(checkboxWithTitle: String(localized: "Temperatur in °F anzeigen"), target: nil, action: nil)
    private let histCheck = NSButton(checkboxWithTitle: String(localized: "Täglich automatisch im Verlauf speichern"), target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: String(localized: "Bei der Anmeldung starten"), target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        fullField.addItems(withTitles: stride(from: 50, through: 100, by: 5).map { "\($0) %" })
        lowField.addItems(withTitles: stride(from: 5, through: 50, by: 5).map { "\($0) %" })
        fullField.selectItem(withTitle: "\(Settings.notifyFullLevel) %")
        lowField.selectItem(withTitle: "\(Settings.notifyLowLevel) %")
        fullCheck.state = Settings.notifyFull ? .on : .off
        lowCheck.state = Settings.notifyLow ? .on : .off
        menuCheck.state = Settings.menuBarPercent ? .on : .off
        fCheck.state = Settings.fahrenheit ? .on : .off
        histCheck.state = Settings.autoHistory ? .on : .off
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for c in [fullCheck, lowCheck, menuCheck, fCheck, histCheck, fullField, lowField] as [NSControl] {
            c.target = self; c.action = #selector(changed)
        }
        loginCheck.target = self; loginCheck.action = #selector(toggleLogin)

        func card(_ title: String, _ symbol: String, _ views: [NSView]) -> NSView {
            let c = NSView()
            c.wantsLayer = true
            c.layer?.backgroundColor = Palette.card.cgColor
            c.layer?.cornerRadius = 12
            c.layer?.borderWidth = 1
            c.layer?.borderColor = Palette.border.cgColor
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))!)
            icon.contentTintColor = Palette.blue
            let head = NSStackView(views: [icon, label(title, size: 13, weight: .semibold)]); head.spacing = 6
            let s = NSStackView(views: [head] + views)
            s.orientation = .vertical; s.alignment = .leading; s.spacing = 10
            s.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(s)
            NSLayoutConstraint.activate([
                s.topAnchor.constraint(equalTo: c.topAnchor, constant: 14),
                s.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 16),
                s.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -16),
                s.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -14),
            ])
            return c
        }
        let title = label(String(localized: "Einstellungen"), size: 20, weight: .bold)
        let main = NSStackView(views: [
            title,
            card(String(localized: "Mitteilungen"), "bell.fill", [NSStackView(views: [fullCheck, fullField]), NSStackView(views: [lowCheck, lowField])]),
            card(String(localized: "Darstellung"), "paintbrush.fill", [menuCheck, fCheck]),
            card(String(localized: "Allgemein"), "gearshape.fill", [histCheck, loginCheck]),
        ])
        main.orientation = .vertical; main.alignment = .leading; main.spacing = 14
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        main.arrangedSubviews.dropFirst().forEach { $0.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            main.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            main.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() {
        Settings.notifyFull = fullCheck.state == .on
        Settings.notifyLow = lowCheck.state == .on
        Settings.notifyFullLevel = Int(fullField.titleOfSelectedItem?.split(separator: " ").first ?? "100") ?? 100
        Settings.notifyLowLevel = Int(lowField.titleOfSelectedItem?.split(separator: " ").first ?? "20") ?? 20
        Settings.menuBarPercent = menuCheck.state == .on
        Settings.fahrenheit = fCheck.state == .on
        Settings.autoHistory = histCheck.state == .on
        if Settings.notifyFull || Settings.notifyLow {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        (NSApp.delegate as? AppDelegate)?.refresh()
    }

    @objc private func toggleLogin() {
        do {
            if loginCheck.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}
