import AppKit
import IOKit
import UserNotifications
import ServiceManagement

enum Palette {
    static let background = NSColor(srgbRed: 0.965, green: 0.965, blue: 0.975, alpha: 1)
    static let card = NSColor.white
    static let border = NSColor(white: 0, alpha: 0.08)
    static let sidebar = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.945, alpha: 1)
    static let secondary = NSColor(white: 0.45, alpha: 1)
    static let track = NSColor(white: 0, alpha: 0.07)
    static let green = NSColor(srgbRed: 0.20, green: 0.74, blue: 0.40, alpha: 1)
    static let orange = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.10, alpha: 1)
    static let red = NSColor(srgbRed: 0.93, green: 0.27, blue: 0.25, alpha: 1)
    static let blue = NSColor(srgbRed: 0.04, green: 0.48, blue: 1.00, alpha: 1)

    static func health(_ h: Double) -> NSColor { h >= 0.8 ? green : (h >= 0.6 ? orange : red) }
    static func charge(_ p: Int, charging: Bool) -> NSColor { charging ? green : (p <= 10 ? red : (p <= 20 ? orange : green)) }
}
