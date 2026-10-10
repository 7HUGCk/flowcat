import Foundation

struct Bytes: Codable, Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var total: UInt64 { received + sent }
    mutating func add(_ other: Bytes) { received += other.received; sent += other.sent }
    func difference(from old: Bytes) -> Bytes {
        Bytes(received: received >= old.received ? received - old.received : 0,
              sent: sent >= old.sent ? sent - old.sent : 0)
    }
}
struct ProcessCounter: Codable {
    var name: String
    var bytes: Bytes
}
struct DayRecord: Codable {
    var physical = Bytes()
    var processes: [String: Bytes] = [:]
    var monitoredSeconds: Double = 0
}
struct NetworkContext: Equatable {
    var key: String
    var name: String
    var identified: Bool
}
struct NetworkHistory: Codable {
    var name: String
    var days: [String: DayRecord] = [:]
}
struct Ledger: Codable {
    var version = 3
    var firstStarted: Date
    var days: [String: DayRecord] = [:]
    var networks: [String: NetworkHistory] = [:]
    init(firstStarted: Date = Date()) { self.firstStarted = firstStarted }
    enum CodingKeys: String, CodingKey { case version, firstStarted, days, networks }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstStarted = try container.decode(Date.self, forKey: .firstStarted)
        days = try container.decode([String: DayRecord].self, forKey: .days)
        networks = try container.decodeIfPresent([String: NetworkHistory].self, forKey: .networks) ?? [:]
        networks = networks.filter { $0.key.hasPrefix("wifi:") }
        for key in networks.keys {
            networks[key]?.name = String(key.dropFirst(5))
        }
    }
    mutating func add(day: String, physical: Bytes, processes: [String: Bytes], seconds: Double,
                      network: NetworkContext = NetworkContext(key: "__all__", name: "全部网络", identified: false)) {
        var record = days[day] ?? DayRecord()
        record.physical.add(physical)
        record.monitoredSeconds += seconds
        for (name, value) in processes {
            var bytes = record.processes[name] ?? Bytes()
            bytes.add(value)
            record.processes[name] = bytes
        }
        days[day] = record
        guard network.identified, network.key.hasPrefix("wifi:") else { return }
        var history = networks[network.key] ?? NetworkHistory(name: network.name)
        history.name = network.name
        var netDay = history.days[day] ?? DayRecord()
        netDay.physical.add(physical); netDay.monitoredSeconds += seconds
        for (name, value) in processes {
            var bytes = netDay.processes[name] ?? Bytes(); bytes.add(value); netDay.processes[name] = bytes
        }
        history.days[day] = netDay; networks[network.key] = history
    }
    func sum(keys: [String], networkName: String? = nil) -> DayRecord {
        var result = DayRecord()
        let sources: [[String: DayRecord]] = networkName.map { selected in
            networks.values.filter { $0.name == selected }.map(\.days)
        } ?? [days]
        for source in sources { for key in keys {
            guard let day = source[key] else { continue }
            result.physical.add(day.physical)
            result.monitoredSeconds += day.monitoredSeconds
            for (name, bytes) in day.processes {
                var value = result.processes[name] ?? Bytes()
                value.add(bytes)
                result.processes[name] = value
            }
        } }
        return result
    }
}
enum PanelLayout {
    static func size(screenWidth: Double, availableHeight: Double) -> (width: Double, height: Double) {
        (min(460, max(240, screenWidth - 24)), min(640, max(240, availableHeight - 28)))
    }
}
enum Parsers {
    static func processes(_ text: String) -> [String: ProcessCounter] {
        var result: [String: ProcessCounter] = [:]
        for line in text.split(separator: "\n") {
            let values = line.split(separator: ",", omittingEmptySubsequences: false)
            guard values.count >= 3,
                  let separator = values[0].lastIndex(of: "."),
                  Int(values[0][values[0].index(after: separator)...]) != nil,
                  let received = UInt64(values[1]), let sent = UInt64(values[2]) else { continue }
            result[String(values[0])] = ProcessCounter(name: String(values[0][..<separator]),
                bytes: Bytes(received: received, sent: sent))
        }
        return result
    }
    static func interfaces(_ text: String) -> [String: Bytes] {
        var result: [String: Bytes] = [:]
        for line in text.split(separator: "\n") {
            let values = line.split(whereSeparator: { $0.isWhitespace })
            guard values.count >= 10, values[0].hasPrefix("en"), values[2].hasPrefix("<Link#"),
                  let received = UInt64(values[6]), let sent = UInt64(values[9]) else { continue }
            result[String(values[0])] = Bytes(received: received, sent: sent)
        }
        return result
    }
}
enum DateKeys {
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    // Assign each short interval to its ending day. Midnight uncertainty is <= polling interval.
    static func keys(period: Int, now: Date, available: [String], calendar: Calendar = .current) -> [String] {
        switch period {
        case 1: return [day(calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)]
        case 2: return available.filter { $0.hasPrefix(String(day(now, calendar: calendar).prefix(7))) }
        default: return [day(now, calendar: calendar)]
        }
    }
}
func volume(_ bytes: UInt64) -> String {
    let value = Double(bytes)
    for (unit, divisor) in [("GB", 1e9), ("MB", 1e6), ("KB", 1e3)] {
        if value >= divisor { return String(format: "%.2f %@", value / divisor, unit) }
    }
    return "\(bytes) B"
}
