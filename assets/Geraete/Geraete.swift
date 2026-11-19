import AppKit
import IOKit
import UserNotifications
import ServiceManagement

private func num(_ v: Any?) -> Int? {
    (v as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }
}

private func registryProperties(_ className: String) -> [String: Any]? {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
    return props?.takeRetainedValue() as? [String: Any]
}

func decodeBatteryDate(_ raw: Int?) -> Date? {
    guard let raw = raw, raw > 0 else { return nil }
    if raw < 65536 {
        var c = DateComponents()
        c.day = raw & 0x1F; c.month = (raw >> 5) & 0xF; c.year = 1980 + (raw >> 9)
        return Calendar.current.date(from: c)
    }
    var bytes: [UInt8] = []
    var v = UInt64(raw)
    while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
    let s = bytes.compactMap { (0x30...0x39).contains($0) ? Character(UnicodeScalar($0)) : nil }
    if s.count >= 6, let yy = Int(String(s[1...2])), let doy = Int(String(s[3...5])), (1...366).contains(doy) {
        var c = DateComponents(); c.year = 2000 + yy; c.day = doy
        if let d = Calendar.current.date(from: c), d <= Date() { return d }
    }
    guard s.count >= 5, let yDigit = Int(String(s[2])), let week = Int(String(s[3...4])), (1...53).contains(week) else { return nil }
    return dateFrom(yearDigit: yDigit, week: week)
}

func batteryDateFromSerial(_ s: String?) -> Date? {
    guard let s = s, s.count >= 6 else { return nil }
    let c = Array(s)
    guard let y = Int(String(c[3])), let w = Int(String(c[4...5])), (1...53).contains(w) else { return nil }
    return dateFrom(yearDigit: y, week: w)
}

private func dateFrom(yearDigit: Int, week: Int, weekday: Int = 1) -> Date? {
    let now = Calendar.current.component(.year, from: Date())
    var year = now - ((now - yearDigit) % 10 + 10) % 10
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = .current
    func make(_ y: Int) -> Date? {
        cal.date(from: DateComponents(weekday: weekday % 7 + 1, weekOfYear: week, yearForWeekOfYear: y))
    }
    if let d = make(year), d > Date() { year -= 10 }
    return make(year)
}

struct MacBattery {
    var percent = 0
    var currentCapacity = 0
    var fullChargeCapacity = 0
    var designCapacity = 0
    var cycleCount = 0
    var designCycleCount = 1000
    var temperature: Double?
    var voltage = 0.0
    var amperage = 0
    var isCharging = false
    var externalConnected = false
    var fullyCharged = false
    var timeRemaining: Int?
    var serial = "–"
    var deviceName = "–"
    var manufacturer = "–"
    var manufactureDate: Date?
    var adapterWatts: Int?
    var adapterName: String?
    var adapterManufacturer: String?
    var adapterVoltage: Double?
    var adapterCurrent: Double?
    var systemLoad: Double?
    var cellVoltages: [Int] = []

    var health: Double { designCapacity > 0 ? Double(fullChargeCapacity) / Double(designCapacity) : 0 }
    var power: Double { voltage * Double(amperage) / 1000 }
    var present: Bool { designCapacity > 0 }

    static func read() -> MacBattery? {
        guard let d = registryProperties("AppleSmartBattery") else { return nil }
        let pack = registryProperties("AppleSmartBatteryPack")?["BatteryData"] as? [String: Any] ?? [:]
        let bd = d["BatteryData"] as? [String: Any] ?? [:]
        func int(_ k: String) -> Int? { num(d[k]) ?? num(pack[k]) ?? num(bd[k]) }
        func str(_ k: String) -> String? {
            ((d[k] ?? pack[k]) as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }

        var b = MacBattery()
        b.fullChargeCapacity = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity") ?? 0
        b.currentCapacity = int("AppleRawCurrentCapacity") ?? 0
        b.designCapacity = int("DesignCapacity") ?? 0
        b.percent = int("CurrentCapacity") ?? 0
        if b.percent > 100, b.fullChargeCapacity > 0 {
            b.percent = Int((Double(b.percent) / Double(b.fullChargeCapacity) * 100).rounded())
        }
        b.cycleCount = int("CycleCount") ?? 0
        b.designCycleCount = int("DesignCycleCount9C") ?? 1000
        if let t = int("Temperature") ?? int("VirtualTemperature"), t > 0 { b.temperature = Double(t) / 100 }
        b.voltage = Double(int("Voltage") ?? 0) / 1000
        b.amperage = int("InstantAmperage") ?? int("Amperage") ?? 0
        b.isCharging = d["IsCharging"] as? Bool ?? false
        b.externalConnected = d["ExternalConnected"] as? Bool ?? false
        b.fullyCharged = d["FullyCharged"] as? Bool ?? false
        if let t = int(b.isCharging ? "AvgTimeToFull" : "AvgTimeToEmpty"), t > 0, t < 65535 { b.timeRemaining = t }
        b.serial = str("Serial") ?? "–"
        b.deviceName = str("DeviceName") ?? "–"
        b.manufacturer = str("Manufacturer") ?? Self.vendor(fromSerial: b.serial)
        b.manufactureDate = decodeBatteryDate(int("ManufactureDate")) ?? batteryDateFromSerial(b.serial)
        b.cellVoltages = (pack["CellVoltage"] as? [NSNumber] ?? bd["CellVoltage"] as? [NSNumber] ?? []).map(\.intValue)

        if let a = d["AdapterDetails"] as? [String: Any] {
            if let w = num(a["Watts"]), w > 0 { b.adapterWatts = w }
            b.adapterName = (a["Name"] as? String) ?? (a["Description"] as? String)
            b.adapterManufacturer = a["Manufacturer"] as? String
            if let v = num(a["AdapterVoltage"]), v > 0 { b.adapterVoltage = Double(v) / 1000 }
            if let c = num(a["Current"]), c > 0 { b.adapterCurrent = Double(c) / 1000 }
        }
        if let pt = d["PowerTelemetryData"] as? [String: Any], let l = num(pt["SystemLoad"]), l > 0 {
            b.systemLoad = Double(l) / 1000
        }
        return b
    }

    static func vendor(fromSerial s: String) -> String {
        let map = ["D86": "Desay", "F8Y": "Sunwoda", "C01": "Simplo", "W01": "Sunwoda", "SMP": "Simplo", "DYN": "Dynapack", "ATL": "ATL"]
        return map.first { s.hasPrefix($0.key) }?.value ?? String(localized: "Unbekannt")
    }
}

enum MacInfo {
    static func sysctl(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "–" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static let model = sysctl("hw.model")
    static let cpu = sysctl("machdep.cpu.brand_string")
    static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    static let name = Host.current().localizedName ?? "Mac"

    static let serial: String = {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(svc) }
        return (IORegistryEntryCreateCFProperty(svc, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String) ?? "–"
    }()

    static let marketingName: String = {
        let e = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if e != 0 {
            defer { IOObjectRelease(e) }
            if let data = IORegistryEntryCreateCFProperty(e, "product-name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data,
               let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
               !s.isEmpty { return s }
        }
        let p = "/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/en.lproj/SIMachineAttributes.plist"
        if let d = NSDictionary(contentsOfFile: p) as? [String: Any],
           let m = d[model] as? [String: Any], let l = m["_LOCALIZABLE_"] as? [String: Any],
           let n = l["marketingModel"] as? String { return n }
        if let d = UserDefaults(suiteName: "com.apple.SystemProfiler")?.dictionary(forKey: "CPU Names"),
           let n = d.first(where: { $0.key.hasPrefix(String(serial.suffix(4))) })?.value as? String { return n }
        return model
    }()

    static let boardSerial: String? = {
        guard let h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW), let s = dlsym(h, "MGCopyAnswer") else { return nil }
        typealias F = @convention(c) (CFString) -> Unmanaged<CFTypeRef>?
        return unsafeBitCast(s, to: F.self)("MLBSerialNumber" as CFString)?.takeRetainedValue() as? String
    }()

    static func manufactureDate(batteryDate: Date?) -> (Date?, String) {
        if let mlb = boardSerial, mlb.count == 17, let d = batteryDateFromSerial(mlb) {
            return (d, String(localized: "aus Hauptplatine"))
        }
        let s = Array(serial)
        if s.count == 12 {
            let halves = Array("CDFGHJKLMNPQRSTVWXYZ")
            let weeks = Array("123456789CDFGHJKLMNPQRTVWXY")
            if let hi = halves.firstIndex(of: s[3]), let wi = weeks.firstIndex(of: s[4]) {
                let year = 2010 + hi / 2
                let week = wi + 1 + (hi % 2 == 1 ? 26 : 0)
                var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
                let d = cal.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year))
                return (d, String(localized: "aus Seriennummer"))
            }
        }
        if let b = batteryDate { return (b, String(localized: "ca., aus Akku")) }
        return (nil, "")
    }
}

struct IOSDevice {
    var id: String
    var name = String(localized: "iOS-Gerät")
    var productType = "–"
    var modelNumber = "–"
    var osVersion = "–"
    var serial = "–"
    var wifi = false
    var batteryPercent: Int?
    var isCharging: Bool?
    var externalConnected: Bool?
    var cycleCount: Int?
    var designCapacity: Int?
    var fullChargeCapacity: Int?
    var currentCapacity: Int?
    var temperature: Double?
    var voltage: Double?
    var amperage: Int?
    var batterySerial: String?
    var manufactureDate: Date?
    var adapterWatts: Int?
    var diagnosticsError: String?

    var health: Double? {
        guard let d = designCapacity, let f = fullChargeCapacity, d > 0, f > 0 else { return nil }
        return Double(f) / Double(d)
    }
}

final class MobileDeviceManager {
    static let shared = MobileDeviceManager()

    private typealias NotifyCB = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias SubscribeFn = @convention(c) (NotifyCB, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    private typealias DevFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias CopyValueFn = @convention(c) (UnsafeMutableRawPointer, CFString?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias CopyIDFn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFString>?
    private typealias StartServiceFn = @convention(c) (UnsafeMutableRawPointer, CFString, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    private typealias SendFn = @convention(c) (UnsafeMutableRawPointer, CFPropertyList, UInt32) -> Int32
    private typealias RecvFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Unmanaged<CFPropertyList>?>, UnsafeMutablePointer<UInt32>?) -> Int32
    private typealias InvalidateFn = @convention(c) (UnsafeMutableRawPointer) -> Int32

    private var subscribe: SubscribeFn?
    private var connect: DevFn?, disconnect: DevFn?, startSession: DevFn?, stopSession: DevFn?
    private var validatePairing: DevFn?, retain: DevFn?, release: DevFn?, iface: DevFn?
    private var copyValue: CopyValueFn?
    private var copyID: CopyIDFn?
    private var startService: StartServiceFn?
    private var send: SendFn?
    private var recv: RecvFn?
    private var invalidate: InvalidateFn?
    private var notification: UnsafeMutableRawPointer?
    private typealias UnsubscribeFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private var unsubscribe: UnsubscribeFn?

    private var devices: [String: UnsafeMutableRawPointer] = [:]
    private let queue = DispatchQueue(label: "mobiledevice")
    var onChange: (() -> Void)?
    private(set) var available = false
    private(set) var info: [String: IOSDevice] = [:]

    private init() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW) else { return }
        func sym<T>(_ n: String, _ t: T.Type) -> T? { dlsym(h, n).map { unsafeBitCast($0, to: t) } }
        subscribe = sym("AMDeviceNotificationSubscribe", SubscribeFn.self)
        connect = sym("AMDeviceConnect", DevFn.self)
        disconnect = sym("AMDeviceDisconnect", DevFn.self)
        startSession = sym("AMDeviceStartSession", DevFn.self)
        stopSession = sym("AMDeviceStopSession", DevFn.self)
        validatePairing = sym("AMDeviceValidatePairing", DevFn.self)
        retain = sym("AMDeviceRetain", DevFn.self)
        release = sym("AMDeviceRelease", DevFn.self)
        unsubscribe = sym("AMDeviceNotificationUnsubscribe", UnsubscribeFn.self)
        iface = sym("AMDeviceGetInterfaceType", DevFn.self)
        copyValue = sym("AMDeviceCopyValue", CopyValueFn.self)
        copyID = sym("AMDeviceCopyDeviceIdentifier", CopyIDFn.self)
        startService = sym("AMDeviceSecureStartService", StartServiceFn.self)
        send = sym("AMDServiceConnectionSendMessage", SendFn.self)
        recv = sym("AMDServiceConnectionReceiveMessage", RecvFn.self)
        invalidate = sym("AMDServiceConnectionInvalidate", InvalidateFn.self)
        available = subscribe != nil && copyValue != nil
    }

    func start() {
        guard notification == nil else { return }
        subscribeNow()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.rescan() }
        startBonjour()
    }

    private func subscribeNow() {
        guard let sub = subscribe else { return }
        let cb: NotifyCB = { infoPtr, _ in
            guard let p = infoPtr, let dev = p.load(as: UnsafeMutableRawPointer?.self) else { return }
            let msg = p.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
            MobileDeviceManager.shared.handle(device: dev, message: msg)
        }
        var n: UnsafeMutableRawPointer?
        _ = sub(cb, 0, 0, nil, &n)
        notification = n
    }

    private var seenInScan: Set<String> = []
    private var scanning = false
    private var lastRescan: CFTimeInterval = 0

    func rescan() {
        let now = CACurrentMediaTime()
        guard !scanning, now - lastRescan > 5 else { return }
        lastRescan = now
        scanning = true
        seenInScan = []
        if let n = notification { _ = unsubscribe?(n) }
        notification = nil
        subscribeNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self else { return }
            self.scanning = false
            for (key, dev) in self.devices where !self.seenInScan.contains(key) {
                _ = self.release?(dev)
                self.devices[key] = nil
            }
            self.refresh()
        }
    }

    private var browser: NetServiceBrowser?
    private let browserDelegate = BonjourWatcher()
    private func startBonjour() {
        let b = NetServiceBrowser()
        b.delegate = browserDelegate
        browserDelegate.onFound = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.rescan() }
        }
        b.searchForServices(ofType: "_apple-mobdev2._tcp.", inDomain: "local.")
        browser = b
    }

    private func handle(device: UnsafeMutableRawPointer, message: UInt32) {
        guard let id = copyID?(device)?.takeRetainedValue() as String? else { return }
        let key = id + "#" + String(iface?(device) ?? 0)
        if message == 1 {
            seenInScan.insert(key)
            guard devices[key] == nil else { return }
            _ = retain?(device)
            devices[key] = device
            refresh()
        } else if message == 2 {
            if let old = devices.removeValue(forKey: key) { _ = release?(old) }
            refresh()
        }
    }

    func refresh() {
        let snapshot = devices
        queue.async {
            var byUDID: [String: IOSDevice] = [:]
            for (key, dev) in snapshot.sorted(by: { (self.iface?($0.value) ?? 0) < (self.iface?($1.value) ?? 0) }) {
                let udid = String(key.split(separator: "#").first ?? "")
                if byUDID[udid] != nil { continue }
                if let d = self.read(id: udid, dev: dev) { byUDID[udid] = d }
            }
            DispatchQueue.main.sync {
                let connected = Set(snapshot.keys.compactMap { $0.split(separator: "#").first.map(String.init) })
                for (udid, old) in self.info where byUDID[udid] == nil && connected.contains(udid) { byUDID[udid] = old }
            }
            DispatchQueue.main.async {
                self.info = byUDID
                self.onChange?()
            }
        }
    }

    private func read(id: String, dev: UnsafeMutableRawPointer) -> IOSDevice? {
        guard let connect = connect, let copy = copyValue, connect(dev) == 0 else { return nil }
        defer { _ = disconnect?(dev) }
        _ = validatePairing?(dev)
        let session = startSession?(dev) == 0
        defer { if session { _ = stopSession?(dev) } }

        func val(_ domain: String?, _ key: String) -> Any? {
            copy(dev, domain as CFString?, key as CFString)?.takeRetainedValue()
        }
        var d = IOSDevice(id: id)
        d.name = val(nil, "DeviceName") as? String ?? String(localized: "iOS-Gerät")
        d.productType = val(nil, "ProductType") as? String ?? "–"
        d.modelNumber = ((val(nil, "ModelNumber") as? String) ?? "") + ((val(nil, "RegionInfo") as? String) ?? "")
        d.osVersion = val(nil, "ProductVersion") as? String ?? "–"
        d.serial = val(nil, "SerialNumber") as? String ?? "–"
        d.wifi = (iface?(dev) ?? 1) == 2
        let battery = "com.apple.mobile.battery"
        d.batteryPercent = num(val(battery, "BatteryCurrentCapacity"))
        d.isCharging = val(battery, "BatteryIsCharging") as? Bool
        d.externalConnected = val(battery, "ExternalConnected") as? Bool

        if session, let reg = diagnostics(dev) {
            let bd = reg["BatteryData"] as? [String: Any] ?? [:]
            func int(_ k: String) -> Int? { num(reg[k]) ?? num(bd[k]) }
            d.cycleCount = int("CycleCount")
            d.designCapacity = int("DesignCapacity")
            d.fullChargeCapacity = int("AppleRawMaxCapacity") ?? int("FullChargeCapacity") ?? int("NominalChargeCapacity")
            d.currentCapacity = int("AppleRawCurrentCapacity") ?? int("TrueRemainingCapacity") ?? int("RemainingCapacity")
            if let t = int("Temperature"), t > 0 { d.temperature = Double(t) / 100 }
            if let v = int("Voltage"), v > 0 { d.voltage = Double(v) / 1000 }
            d.amperage = int("InstantAmperage") ?? int("Amperage")
            d.batterySerial = (reg["Serial"] ?? bd["Serial"]) as? String
            d.manufactureDate = decodeBatteryDate(int("ManufactureDate")) ?? batteryDateFromSerial(d.batterySerial)
            if let a = reg["AdapterDetails"] as? [String: Any], let w = num(a["Watts"]), w > 0 { d.adapterWatts = w }
            if d.batteryPercent == nil { d.batteryPercent = int("CurrentCapacity") }
        } else {
            d.diagnosticsError = String(localized: "Diagnosedienst nicht erreichbar")
        }
        return d
    }

    private func diagnostics(_ dev: UnsafeMutableRawPointer) -> [String: Any]? {
        guard let start = startService, let send = send, let recv = recv else { return nil }
        var conn: UnsafeMutableRawPointer?
        guard start(dev, "com.apple.mobile.diagnostics_relay" as CFString, nil, &conn) == 0, let c = conn else {
            return nil
        }
        defer { _ = invalidate?(c) }
        for req in [["Request": "IORegistry", "EntryName": "AppleSmartBattery"],
                    ["Request": "IORegistry", "EntryClass": "IOPMPowerSource"]] {
            guard send(c, req as CFDictionary, 100) == 0 else { continue }
            var out: Unmanaged<CFPropertyList>?
            guard recv(c, &out, nil) == 0, let o = out?.takeRetainedValue() as? [String: Any] else { continue }
            if let reg = (o["Diagnostics"] as? [String: Any])?["IORegistry"] as? [String: Any], !reg.isEmpty {
                _ = send(c, ["Request": "Goodbye"] as CFDictionary, 100)
                return reg
            }
        }
        return nil
    }
}

final class BonjourWatcher: NSObject, NetServiceBrowserDelegate {
    var onFound: (() -> Void)?
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if !moreComing { onFound?() }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if !moreComing { onFound?() }
    }
}
