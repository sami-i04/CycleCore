import AppKit
import IOKit
import UserNotifications
import ServiceManagement

enum Settings {
    private static let d = UserDefaults.standard
    static func register() {
        d.register(defaults: ["notifyFull": true, "notifyFullLevel": 100, "notifyLow": true, "notifyLowLevel": 20,
                              "menuBarPercent": true, "fahrenheit": false, "autoHistory": true])
    }
    static var notifyFull: Bool { get { d.bool(forKey: "notifyFull") } set { d.set(newValue, forKey: "notifyFull") } }
    static var notifyFullLevel: Int { get { d.integer(forKey: "notifyFullLevel") } set { d.set(newValue, forKey: "notifyFullLevel") } }
    static var notifyLow: Bool { get { d.bool(forKey: "notifyLow") } set { d.set(newValue, forKey: "notifyLow") } }
    static var notifyLowLevel: Int { get { d.integer(forKey: "notifyLowLevel") } set { d.set(newValue, forKey: "notifyLowLevel") } }
    static var menuBarPercent: Bool { get { d.bool(forKey: "menuBarPercent") } set { d.set(newValue, forKey: "menuBarPercent") } }
    static var fahrenheit: Bool { get { d.bool(forKey: "fahrenheit") } set { d.set(newValue, forKey: "fahrenheit") } }
    static var autoHistory: Bool { get { d.bool(forKey: "autoHistory") } set { d.set(newValue, forKey: "autoHistory") } }
}
