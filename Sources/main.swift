import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let monitor = TrafficMonitor()
    let popover = NSPopover()
    var hosting: NSHostingController<LedgerView>?
    var started = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid two samplers double-counting the same computer after repeated clicks.
        let identifier = Bundle.main.bundleIdentifier ?? "local.gww.trafficledger"
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        if siblings.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "流量账本")
            button.imagePosition = .imageLeading
            button.title = " ↓0 KB/s"
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.target = self; button.action = #selector(toggle)
        }
        popover.behavior = .transient
        configurePanel()
        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            self.item.button?.title = self.monitor.paused ? " 暂停" : " ↓\(volume(UInt64(max(0, self.monitor.download))))/s"
            self.item.button?.toolTip = "流量账本 · 今日 \(volume(self.monitor.ledger.days[DateKeys.day(Date())]?.physical.total ?? 0))"
        }
        started = true; monitor.start()
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            configurePanel()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    private func configurePanel() {
        let screen = item.button?.window?.screen ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 800)
        let dimension = PanelLayout.size(screenWidth: frame.width, availableHeight: frame.height)
        let size = CGSize(width: dimension.width, height: dimension.height)
        if let hosting {
            hosting.rootView = LedgerView(monitor: monitor, panelSize: size)
            hosting.preferredContentSize = size
        } else {
            let controller = NSHostingController(rootView: LedgerView(monitor: monitor, panelSize: size))
            controller.sizingOptions = []
            controller.preferredContentSize = size
            hosting = controller; popover.contentViewController = controller
        }
        popover.contentSize = size
    }
    func applicationWillTerminate(_ notification: Notification) { if started { monitor.save() } }
}
let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let preview = TrafficMonitor(file: destination.deletingLastPathComponent().appendingPathComponent("preview-ledger-unused.json"))
    preview.ledger = Ledger(firstStarted: Date())
    preview.ledger.add(day: DateKeys.day(Date()), physical: Bytes(received: 2630000000, sent: 180000000),
        processes: ["UU远程": Bytes(received: 2400000000, sent: 21000000),
                    "Claude Code": Bytes(received: 56000000, sent: 27000000),
                    "ssh": Bytes(received: 24000000, sent: 6000000),
                    "verge-mihomo": Bytes(received: 78000000, sent: 80000000),
                    "Tailscale": Bytes(received: 33000000, sent: 8500000),
                    "ChatGPT": Bytes(received: 35000000, sent: 16000000)], seconds: 14400)
    preview.download = 219000; preview.upload = 2400
    preview.status = "界面预览 · 示例数据"
    let view = NSHostingView(rootView: LedgerView(monitor: preview))
    view.frame = NSRect(x: 0, y: 0, width: 460, height: 650)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: destination) }
    }
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
