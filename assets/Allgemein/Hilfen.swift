import AppKit
import IOKit
import UserNotifications
import ServiceManagement

func IOSEntry(_ d: IOSDevice) -> HistoryEntry {
    HistoryEntry(date: Date(), device: d.name, serial: d.serial, kind: "ios", model: d.productType,
                 percent: d.batteryPercent ?? 0, fullCapacity: d.fullChargeCapacity ?? 0,
                 designCapacity: d.designCapacity ?? 0, cycles: d.cycleCount ?? 0)
}

func deviceSymbol(kind: String?, model: String?) -> String {
    if kind == "mac" { return "laptopcomputer" }
    return (model ?? "").hasPrefix("iPad") ? "ipad" : "iphone"
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }
