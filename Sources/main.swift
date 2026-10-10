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
            button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "流量喵")
            button.imagePosition = .imageLeading
            button.title = " ↓0 KB/s"
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.target = self; button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        configurePanel()
        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            self.item.button?.title = self.monitor.paused ? " 暂停" : " ↓\(volume(UInt64(max(0, self.monitor.download))))/s"
            self.item.button?.toolTip = "流量喵 · 今日 \(volume(self.monitor.ledger.days[DateKeys.day(Date())]?.physical.total ?? 0))"
        }
        started = true; monitor.start()
    }
    @objc func toggle() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else { openStatistics() }
    }
    @objc private func openStatistics() {
        monitor.refreshLoginStatus()
        if popover.isShown { return }
        if let button = item.button {
            configurePanel()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    private func showContextMenu() {
        guard let button = item.button else { return }
        popover.performClose(nil)
        monitor.refreshLoginStatus()
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, action: Selector) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
            return entry
        }
        _ = add("打开统计面板", action: #selector(openStatistics))
        _ = add(monitor.paused ? "继续记录" : "暂停记录", action: #selector(toggleRecording))
        menu.addItem(.separator())
        let login = add("登录时自动启动", action: #selector(toggleLogin))
        login.state = monitor.loginEnabled ? .on : .off
        _ = add("导出 CSV…", action: #selector(exportCSV))
        menu.addItem(.separator())
        _ = add("退出流量喵", action: #selector(quit))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }
    @objc private func toggleRecording() { monitor.togglePause() }
    @objc private func exportCSV() {
        NSApp.activate(ignoringOtherApps: true)
        monitor.export()
    }
    @objc private func toggleLogin() {
        do { try monitor.setLogin(!monitor.loginEnabled) }
        catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "无法设置登录启动"
            alert.informativeText = "请先把应用放入“应用程序”，再重试。\n\(error.localizedDescription)"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
    @objc private func quit() { monitor.save(); NSApp.terminate(nil) }
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
