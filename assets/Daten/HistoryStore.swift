import AppKit
import IOKit
import UserNotifications
import ServiceManagement

struct HistoryEntry: Codable {
    var date: Date
    var device: String
    var serial: String
    var kind: String?
    var model: String?
    var percent: Int
    var fullCapacity: Int
    var designCapacity: Int
    var cycles: Int
    var health: Double { designCapacity > 0 ? Double(fullCapacity) / Double(designCapacity) : 0 }
}

final class HistoryStore {
    static let shared = HistoryStore()
    private(set) var entries: [HistoryEntry] = []
    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CycleCore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            entries = (try? dec.decode([HistoryEntry].self, from: data)) ?? []
        }
        if entries.contains(where: { $0.kind == nil && $0.device == "Mac" }) {
            for i in entries.indices where entries[i].kind == nil && entries[i].device == "Mac" {
                entries[i].kind = "mac"; entries[i].device = MacInfo.name
                entries[i].serial = MacInfo.serial; entries[i].model = MacInfo.marketingName
            }
            save()
        }
    }

    func add(_ e: HistoryEntry) { entries.append(e); entries.sort { $0.date < $1.date }; save() }

    func addDailyIfNeeded(_ e: HistoryEntry) {
        let today = Calendar.current.startOfDay(for: Date())
        if entries.contains(where: { $0.serial == e.serial && $0.date >= today }) { return }
        add(e)
    }

    func entries(forSerial s: String) -> [HistoryEntry] { entries.filter { $0.serial == s } }

    func remove(_ e: HistoryEntry) {
        entries.removeAll { $0.serial == e.serial && $0.date == e.date }
        save()
    }

    func removeDevice(serial: String) { entries.removeAll { $0.serial == serial }; save() }

    var devices: [HistoryEntry] {
        var latest: [String: HistoryEntry] = [:]
        for e in entries { latest[e.serial] = e }
        return latest.values.sorted { ($0.kind == "mac" ? 0 : 1, $0.device) < ($1.kind == "mac" ? 0 : 1, $1.device) }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .prettyPrinted
        try? enc.encode(entries).write(to: url)
    }

    func csv(serial: String?) -> String {
        let f = ISO8601DateFormatter()
        var s = String(localized: "Datum;Gerät;Modell;Seriennummer;Ladung %;Max. Kapazität mAh;Design-Kapazität mAh;Gesundheit %;Ladezyklen\n")
        for e in entries where serial == nil || e.serial == serial {
            s += "\(f.string(from: e.date));\(e.device);\(e.model ?? "");\(e.serial);\(e.percent);\(e.fullCapacity);\(e.designCapacity);"
            s += String(format: "%.1f", e.health * 100) + ";\(e.cycles)\n"
        }
        return s
    }
}
