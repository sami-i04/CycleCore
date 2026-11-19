import AppKit
import IOKit
import UserNotifications
import ServiceManagement

enum Fmt {
    static func temp(_ c: Double?) -> String {
        guard let c = c else { return "–" }
        return Settings.fahrenheit ? String(format: "%.1f °F", c * 9 / 5 + 32) : String(format: "%.1f °C", c)
    }
    static func minutes(_ m: Int?) -> String {
        guard let m = m else { return String(localized: "Wird berechnet …") }
        return String(format: "%d:%02d h", m / 60, m % 60)
    }
    private static let dateF: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()
    private static let dateTimeF: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
    static func date(_ d: Date?) -> String { d.map(dateF.string(from:)) ?? String(localized: "Unbekannt") }
    static func dateTime(_ d: Date) -> String { dateTimeF.string(from: d) }
    static func age(_ d: Date?) -> String {
        guard let d = d else { return String(localized: "Unbekannt") }
        let c = Calendar.current.dateComponents([.year, .month], from: d, to: Date())
        let y = c.year ?? 0, m = c.month ?? 0
        if y == 0 { return m == 1 ? String(localized: "1 Monat") : String(localized: "\(m) Monate") }
        return (y == 1 ? String(localized: "1 Jahr") : String(localized: "\(y) Jahre")) + (m > 0 ? String(localized: ", \(m) Mon.") : "")
    }
    static func mah(_ v: Int?) -> String { v.map { String(localized: "\($0) mAh") } ?? "–" }
}
