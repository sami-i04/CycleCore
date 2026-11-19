import AppKit
import IOKit
import UserNotifications
import ServiceManagement

struct Accessory: Equatable {
    var id: String
    var name: String
    var productID: String?
    var minorType: String?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var main: Int?
    var firmware: String?
    var caseFirmware: String?
    var serial: String?
    var serialLeft: String?
    var serialRight: String?
    var rssi: Int?

    var model: String {
        let map = ["0x2002": String(localized: "AirPods (1. Gen.)"), "0x200F": String(localized: "AirPods (2. Gen.)"), "0x2013": String(localized: "AirPods (3. Gen.)"),
                   "0x2019": "AirPods 4", "0x201B": "AirPods 4 (ANC)",
                   "0x200E": String(localized: "AirPods Pro"), "0x2014": String(localized: "AirPods Pro (2. Gen.)"), "0x2024": String(localized: "AirPods Pro (2. Gen., USB-C)"),
                   "0x2027": String(localized: "AirPods Pro 3"),
                   "0x200A": String(localized: "AirPods Max"), "0x201F": String(localized: "AirPods Max (USB-C)"),
                   "0x2012": String(localized: "Beats Fit Pro"), "0x2011": String(localized: "Beats Studio Buds"), "0x200B": String(localized: "Powerbeats Pro"),
                   "0x0269": String(localized: "Magic Mouse"), "0x030D": String(localized: "Magic Mouse"), "0x0267": String(localized: "Magic Keyboard"), "0x029C": String(localized: "Magic Keyboard"),
                   "0x029A": String(localized: "Magic Keyboard mit Touch ID"), "0x0265": String(localized: "Magic Trackpad"), "0x0324": String(localized: "Magic Trackpad")]
        if let p = productID?.uppercased().replacingOccurrences(of: "0X", with: "0x"), let m = map[p] { return m }
        return minorType ?? String(localized: "Bluetooth-Gerät")
    }

    var symbol: String {
        let m = model.lowercased(), n = name.lowercased()
        if m.contains("airpods max") { return "airpodsmax" }
        if m.contains("airpods pro") || n.contains("airpods pro") { return "airpodspro" }
        if m.contains("airpods") || n.contains("airpods") { return "airpods" }
        if m.contains("beats") || n.contains("beats") { return "beats.earphones" }
        if m.contains("mouse") || minorType == "Mouse" { return "magicmouse" }
        if m.contains("keyboard") || minorType == "Keyboard" { return "keyboard" }
        if m.contains("trackpad") || minorType == "Trackpad" { return "rectangle.and.hand.point.up.left" }
        return "headphones"
    }

    var levels: [(String, Int)] {
        [(String(localized: "Links"), left), (String(localized: "Rechts"), right), (String(localized: "Case"), caseLevel), (String(localized: "Akku"), main)].compactMap { k, v in v.map { (k, $0) } }
    }

    var summary: String { levels.map { "\($0.0.prefix(1)) \($0.1) %" }.joined(separator: " · ") }
}

final class AccessoryManager {
    static let shared = AccessoryManager()
    private(set) var devices: [Accessory] = []
    var onChange: (() -> Void)?
    private var running = false

    func refresh() {
        guard !running else { return }
        running = true
        DispatchQueue.global(qos: .utility).async {
            var list = Self.read()
            DispatchQueue.main.async {
                self.running = false
                for i in list.indices where list[i].caseLevel == nil {
                    list[i].caseLevel = self.devices.first { $0.name == list[i].name }?.caseLevel
                }
                guard list != self.devices else { return }
                self.devices = list
                self.onChange?()
            }
        }
    }

    private static func read() -> [Accessory] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        func pct(_ v: Any?) -> Int? {
            guard let s = v as? String else { return nil }
            return Int(s.filter(\.isNumber))
        }
        var result: [String: Accessory] = [:]
        for section in sections {
            for group in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, raw) in group {
                    guard let d = raw as? [String: Any] else { continue }
                    var a = Accessory(id: d["device_address"] as? String ?? name, name: name)
                    a.productID = d["device_productID"] as? String
                    a.minorType = d["device_minorType"] as? String
                    a.left = pct(d["device_batteryLevelLeft"])
                    a.right = pct(d["device_batteryLevelRight"])
                    a.caseLevel = pct(d["device_batteryLevelCase"])
                    a.main = pct(d["device_batteryLevelMain"]) ?? pct(d["device_batteryLevel"])
                    a.firmware = d["device_firmwareVersion"] as? String
                    a.caseFirmware = d["device_caseVersion"] as? String
                    a.serial = d["device_serialNumber"] as? String
                    a.serialLeft = d["device_serialNumberLeft"] as? String
                    a.serialRight = d["device_serialNumberRight"] as? String
                    a.rssi = (d["device_rssi"] as? String).flatMap { Int($0) }
                    guard !a.levels.isEmpty else { continue }

                    if var e = result[name] {
                        if e.productID == nil, a.productID != nil { swap(&e, &a) }
                        e.left = e.left ?? a.left; e.right = e.right ?? a.right
                        e.caseLevel = e.caseLevel ?? a.caseLevel; e.main = e.main ?? a.main
                        e.serial = e.serial ?? a.serial; e.firmware = e.firmware ?? a.firmware
                        result[name] = e
                    } else {
                        result[name] = a
                    }
                }
            }
        }
        return result.values.sorted { $0.name < $1.name }
    }
}
