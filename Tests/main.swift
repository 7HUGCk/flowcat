import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}
let nettop = """
,bytes_in,bytes_out,
UURemote.29337,275271547,4816332,
Codex (Service).29890,3898336,4942778,
node.123,10,20,
node.124,30,40,
wrong,nope,nope,
"""
let parsed = Parsers.processes(nettop)
expect(parsed.count == 4, "nettop skips headers and malformed rows")
expect(parsed["UURemote.29337"]?.bytes.received == 275271547, "process byte counters")
expect(parsed["Codex (Service).29890"]?.name == "Codex (Service)", "process names containing spaces")
expect(parsed["node.123"] != nil && parsed["node.124"] != nil, "separate PID baselines")
let interfaces = """
Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
en0 1500 <Link#12> a0:78:17:00:00:00 100 0 5000000000 80 0 4000000000 0
en0 1500 192.168.1 192.168.1.2 100 - 5000000000 80 - 4000000000 -
lo0 16384 <Link#1> 00:00:00:00:00:00 50 0 200 50 0 200 0
utun4 1280 <Link#16> 00:00:00:00:00:00 10 0 50 10 0 60 0
en1 1500 <Link#13> 00:00:00:00:00:00 0 0 10 0 0 20 0
"""
let nets = Parsers.interfaces(interfaces)
expect(nets.count == 2, "exclude loopback, VPN and duplicate address rows")
expect(nets["en0"]?.total == 9000000000, "64-bit counters beyond 4 GB")
expect(Bytes(received: 120, sent: 70).difference(from: Bytes(received: 100, sent: 50)) == Bytes(received: 20, sent: 20), "interval deltas")
expect(Bytes(received: 1, sent: 2).difference(from: Bytes(received: 100, sent: 200)) == Bytes(), "counter reset does not create negative or gigantic traffic")
let formatter = ISO8601DateFormatter()
let date = formatter.date(from: "2026-10-10T12:00:00Z")!
var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
expect(DateKeys.keys(period: 0, now: date, available: [], calendar: calendar) == ["2026-10-10"], "today uses local calendar")
expect(DateKeys.keys(period: 1, now: date, available: [], calendar: calendar) == ["2026-10-09"], "yesterday date selection")
let monthStart = formatter.date(from: "2026-09-30T18:00:00Z")!
expect(DateKeys.keys(period: 1, now: monthStart, available: [], calendar: calendar) == ["2026-09-30"], "yesterday across month boundary")
var ledger = Ledger(firstStarted: date)
ledger.add(day: "2026-10-09", physical: Bytes(received: 100, sent: 20), processes: ["UU": Bytes(received: 100), "Tailscale": Bytes(received: 100)], seconds: 10)
ledger.add(day: "2026-10-10", physical: Bytes(received: 200, sent: 30), processes: ["UU": Bytes(received: 200)], seconds: 10)
ledger.add(day: "2026-09-30", physical: Bytes(received: 9999), processes: [:], seconds: 10)
let monthKeys = DateKeys.keys(period: 2, now: date, available: Array(ledger.days.keys), calendar: calendar)
let monthly = ledger.sum(keys: monthKeys)
expect(monthly.physical.total == 350, "month excludes previous month")
expect(monthly.processes["UU"]?.received == 300, "process monthly aggregate")
expect(monthly.physical.total != monthly.processes.values.reduce(0, { $0 + $1.total }), "physical total is independent of duplicated relay accounting")
expect(ledger.sum(keys: ["2026-10-08"]).physical.total == 0, "no fabricated pre-monitor history")
let data = try JSONEncoder().encode(ledger)
let restored = try JSONDecoder().decode(Ledger.self, from: data)
expect(restored.sum(keys: monthKeys).physical == monthly.physical, "history survives JSON round trip")
expect(volume(10000000000) == "10.00 GB", "decimal units match mobile data units")
var classified = Ledger(firstStarted: date)
classified.add(day: "2026-10-09", physical: Bytes(received: 1000), processes: ["UU": Bytes(received: 800)], seconds: 10,
    network: NetworkContext(key: "wifi:RMB", name: "RMB", identified: true))
classified.add(day: "2026-10-10", physical: Bytes(received: 2000), processes: ["UU": Bytes(received: 1800)], seconds: 20,
    network: NetworkContext(key: "wifi:Phone1", name: "Phone1", identified: true))
classified.add(day: "2026-10-10", physical: Bytes(received: 500), processes: ["SSH": Bytes(received: 500)], seconds: 5,
    network: NetworkContext(key: "wifi:Phone2", name: "Phone2", identified: true))
classified.add(day: "2026-10-10", physical: Bytes(received: 300), processes: ["UU": Bytes(received: 300)], seconds: 3,
    network: NetworkContext(key: "__all__", name: "全部网络", identified: false))
expect(classified.sum(keys: ["2026-10-09", "2026-10-10"], networkName: "RMB").physical.total == 1000, "RMB traffic remains separate")
expect(classified.sum(keys: ["2026-10-10"], networkName: "Phone1").physical.total == 2000, "actual SSIDs remain separate")
expect(classified.sum(keys: ["2026-10-10"], networkName: "Phone1").processes["UU"]?.total == 1800, "per-SSID process traffic")
expect(classified.sum(keys: ["2026-10-10"], networkName: "RMB").physical.total == 0, "network filter respects selected date")
expect(classified.sum(keys: ["2026-10-10"]).physical.total == 2800, "all networks total does not double-count classified storage")
let classifiedRestored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(classified))
expect(classifiedRestored.sum(keys: ["2026-10-10"], networkName: "Phone1").physical.total == 2000, "SSID history persists")
var legacyJSON = try JSONSerialization.jsonObject(with: data) as! [String: Any]
legacyJSON.removeValue(forKey: "networks"); legacyJSON["version"] = 1
let legacy = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
expect(legacy.sum(keys: monthKeys).physical.total == 350 && legacy.networks.isEmpty, "upgrade preserves old totals without adding a fake network")
expect(legacy.sum(keys: monthKeys, networkName: "Phone1").physical.total == 0, "upgrade does not fabricate historical network attribution")
let smallPanel = PanelLayout.size(screenWidth: 1024, availableHeight: 480)
expect(smallPanel.height == 452 && smallPanel.width == 460, "popup fits a short display")
let narrowPanel = PanelLayout.size(screenWidth: 400, availableHeight: 800)
expect(narrowPanel.width == 376 && narrowPanel.height == 640, "popup fits display width and caps height")
expect(classified.networks["__all__"] == nil, "unidentified traffic only updates all-network totals")
var aliasedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(classified)) as! [String: Any]
var oldNetworks = aliasedJSON["networks"] as! [String: Any]
var renamed = oldNetworks["wifi:Phone1"] as! [String: Any]; renamed["name"] = "Former manual label"
oldNetworks["wifi:Phone1"] = renamed
oldNetworks["legacy"] = renamed
aliasedJSON["networks"] = oldNetworks
let normalized = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: aliasedJSON))
expect(normalized.networks["wifi:Phone1"]?.name == "Phone1", "upgrade restores the exact stored SSID rather than manual labels")
expect(normalized.networks["legacy"] == nil && normalized.sum(keys: ["2026-10-10"]).physical.total == 2800, "legacy classification hidden with original totals intact")
func release(_ version: String, url: String? = nil, draft: Bool = false, prerelease: Bool = false) -> ReleaseInfo {
    let name = "FlowCat-\(version)-arm64.zip"
    return ReleaseInfo(tag_name: "v\(version)", body: nil, draft: draft, prerelease: prerelease,
        assets: [ReleaseInfo.Asset(name: name, browser_download_url: URL(string: url ?? "https://github.com/tab16360/flowcat/releases/download/v\(version)/\(name)")!)])
}
expect(release("1.3.10").isNewer(than: "1.3.9"), "updates compare numeric version components")
expect(!release("1.3.4").isNewer(than: "1.3.5"), "updates never offer a downgrade")
expect(!release("1.3.5").isNewer(than: "1.3.5"), "current version does not offer an update")
expect(release("1.3.5").downloadURL != nil, "updates select the matching arm64 asset")
expect(release("1.3.5", url: "https://example.com/package.zip").downloadURL == nil, "updates reject a foreign download host")
expect(release("1.3.5", url: "https://github.com/other/repo/releases/download/v1.3.5/FlowCat-1.3.5-arm64.zip").downloadURL == nil, "updates reject assets from another repository")
expect(release("1.3.5", prerelease: true).downloadURL == nil && !release("1.3.5", draft: true).isNewer(than: "1.3.4"), "updates exclude drafts and prereleases")
expect(!ReleaseInfo.validVersion("1.3.5-beta") && !ReleaseInfo.validVersion("1..5"), "updates reject malformed stable versions")
print("All 38 checks passed.")
