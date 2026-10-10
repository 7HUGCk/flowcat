import AppKit
import SwiftUI
import ServiceManagement

private struct Palette {
    let dark: Bool
    var background: Color { color(0xF5F7FA, 0x191D24) }
    var surface: Color { color(0xFFFFFF, 0x252B34) }
    var text: Color { color(0x1C2633, 0xF1F4F8) }
    var secondary: Color { color(0x526174, 0xB4BECC) }
    var border: Color { color(0xD6DDE7, 0x414B59) }
    var track: Color { color(0xE2E8F1, 0x394351) }
    var accent: Color { color(0x245CC4, 0x9DBEFF) }
    private func color(_ light: UInt32, _ darkValue: UInt32) -> Color {
        let rgb = dark ? darkValue : light
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

struct LedgerView: View {
    @ObservedObject var monitor: TrafficMonitor
    var panelSize = CGSize(width: 460, height: 640)
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    @State private var explanation = false
    @State private var order = 0
    @State private var loginError = ""
    private var palette: Palette { Palette(dark: scheme == .dark) }
    private var compact: Bool { panelSize.height < 540 }
    private var record: DayRecord { monitor.selected }
    private var periodName: String { ["今日", "昨日", "本月"][min(2, max(0, monitor.period))] }
    private var networkName: String { monitor.selectedNetwork == "__all__" ? "全部网络" : monitor.selectedNetwork }
    private var sortName: String { ["总流量", "下载量", "上传量"][order] }
    private func metric(_ b: Bytes) -> UInt64 { order == 1 ? b.received : order == 2 ? b.sent : b.total }
    private var rows: [(String, Bytes)] {
        monitor.rows.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }.sorted {
            metric($0.1) == metric($1.1) ? $0.0 < $1.0 : metric($0.1) > metric($1.1)
        }
    }
    private var hasError: Bool { monitor.status.contains("失败") || monitor.status.contains("不可用") }

    var body: some View {
        Group {
            if compact { ScrollView { content } }
            else { content }
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
        .foregroundStyle(palette.text)
        .background(palette.background)
    }
    private var content: some View {
        VStack(spacing: compact ? 12 : 16) {
            header
            filters
            summary
            if hasError { errorBanner }
            processSection
            footer
        }.padding(compact ? 14 : 18)
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.accent)
                .frame(width: 30, height: 30).background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
            Text("流量喵").font(.system(size: 14, weight: .semibold))
            Spacer()
            Label(monitor.paused ? "已暂停" : hasError ? "采集异常" : monitor.lastSample == nil ? "准备中" : "记录中",
                  systemImage: monitor.paused ? "pause.circle" : hasError ? "exclamationmark.circle" : "record.circle")
                .font(.system(size: 11)).foregroundStyle(palette.secondary)
            Button { monitor.togglePause() } label: {
                Image(systemName: monitor.paused ? "play.fill" : "pause.fill").font(.system(size: 11))
                    .frame(width: 27, height: 27).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).help(monitor.paused ? "继续记录" : "暂停记录")
                .accessibilityLabel(monitor.paused ? "继续记录" : "暂停记录")
            Menu {
                Toggle("登录时自动启动", isOn: Binding(get: { monitor.loginEnabled }, set: { setLogin($0) }))
                Button("导出 CSV…") { monitor.export() }
                Divider()
                Button("退出流量喵") { monitor.save(); NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).frame(width: 22, height: 26)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多操作")
                .accessibilityLabel("更多操作")
        }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Picker("统计时间", selection: $monitor.period) {
                    Text("今日").tag(0); Text("昨日").tag(1); Text("本月").tag(2)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.regular)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .accessibilityLabel("统计时间")
                Picker("统计网络", selection: $monitor.selectedNetwork) {
                    Text("全部网络").tag("__all__")
                    ForEach(monitor.networkNames, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().controlSize(.regular)
                    .frame(width: min(144, panelSize.width * 0.32), height: 28)
                    .help("按 Wi-Fi 名称筛选历史流量").accessibilityLabel("统计网络")
            }
            Label(monitor.currentNetwork.identified ? "当前连接 · \(monitor.currentNetwork.name)" : "正在按全部网络记录",
                  systemImage: monitor.currentNetwork.identified ? "wifi" : "network")
                .font(.system(size: 11)).foregroundStyle(palette.secondary)
                .lineLimit(1).truncationMode(.middle).help(monitor.currentNetwork.name)
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(periodName)累计").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
                Spacer()
                Text(String(format: "覆盖 %.1f 小时", record.monitoredSeconds / 3600))
                    .font(.system(size: 11)).foregroundStyle(palette.secondary).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                let parts = volume(record.physical.total).split(separator: " ", maxSplits: 1)
                Text(String(parts[0])).font(.system(size: compact ? 28 : 34, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(parts.count > 1 ? String(parts[1]) : "B").font(.system(size: 17, weight: .medium)).foregroundStyle(palette.secondary)
                Spacer()
            }.accessibilityElement(children: .ignore).accessibilityLabel("\(periodName) \(networkName) 总流量 \(volume(record.physical.total))")
            HStack(spacing: 18) {
                metricLabel("下载", bytes: record.physical.received, symbol: "arrow.down")
                metricLabel("上传", bytes: record.physical.sent, symbol: "arrow.up")
            }
            Rectangle().fill(palette.border).frame(height: 0.5)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("实时 · 整机").font(.system(size: 11)).foregroundStyle(palette.secondary)
                    Spacer()
                    liveRates
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("实时 · 整机").font(.system(size: 11)).foregroundStyle(palette.secondary)
                    liveRates
                }
            }
        }.padding(14).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func metricLabel(_ title: String, bytes: UInt64, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.secondary)
            Text(title).font(.system(size: 11)).foregroundStyle(palette.secondary)
            Text(volume(bytes)).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var liveRates: some View {
        HStack(spacing: 12) {
            Label("\(volume(UInt64(max(0, monitor.download))))/s", systemImage: "arrow.down")
            Label("\(volume(UInt64(max(0, monitor.upload))))/s", systemImage: "arrow.up")
        }.font(.system(size: 11, weight: .medium)).monospacedDigit()
    }
    private var processSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("进程排行").font(.system(size: 12, weight: .semibold))
                Text("\(rows.count)").font(.system(size: 11)).foregroundStyle(palette.secondary)
                Spacer()
                Menu {
                    Picker("排序方式", selection: $order) {
                        Text("总流量").tag(0); Text("下载量").tag(1); Text("上传量").tag(2)
                    }
                } label: { Label(sortName, systemImage: "arrow.down") }
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("排序方式")
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(palette.secondary)
                TextField("搜索进程", text: $search).font(.system(size: 12)).textFieldStyle(.plain).accessibilityLabel("搜索进程")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondary) }
                        .buttonStyle(.plain).help("清除搜索").accessibilityLabel("清除搜索")
                }
            }.padding(.horizontal, 10).frame(height: 30).background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            ScrollView {
                LazyVStack(spacing: 0) {
                    if rows.isEmpty { emptyState }
                    ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                        processRow(index: index, name: row.0, bytes: row.1)
                    }
                }
            }.frame(height: compact ? 210 : nil).frame(minHeight: 0, maxHeight: .infinity)
        }.frame(minHeight: 0, maxHeight: .infinity).layoutPriority(-1)
    }
    private func processRow(index: Int, name: String, bytes: Bytes) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(index + 1)).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.secondary)
                .frame(width: 14, height: 27).monospacedDigit().accessibilityHidden(true)
            processIcon(name).frame(width: 27, height: 27).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle).help(name)
                    Spacer(minLength: 10)
                    Text(volume(bytes.total)).font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.accent).frame(width: min(geometry.size.width, max(0, geometry.size.width * Double(metric(bytes)) / Double(max(1, rows.first.map { metric($0.1) } ?? 1)))))
                    }
                }.frame(height: 3).accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        rowRates(bytes)
                        Spacer(minLength: 4)
                        if isRelay(name) { relayBadge }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        rowRates(bytes)
                        if isRelay(name) { relayBadge }
                    }
                }
            }
        }.padding(.vertical, 10)
    }
    @ViewBuilder private func processIcon(_ name: String) -> some View {
        if isRelay(name) {
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 16)).foregroundStyle(palette.secondary)
        } else if ["ssh", "node", "java", "python", "codex", "claude"].contains(where: { name.lowercased().hasPrefix($0) }) {
            Image(systemName: "terminal").font(.system(size: 17)).foregroundStyle(palette.secondary)
        } else if let icon = monitor.icons[name] {
            Image(nsImage: icon).resizable().interpolation(.high).clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "app.dashed").font(.system(size: 18)).foregroundStyle(palette.secondary)
        }
    }
    private func rowRates(_ bytes: Bytes) -> some View {
        HStack(spacing: 12) {
            Label(volume(bytes.received), systemImage: "arrow.down")
            Label(volume(bytes.sent), systemImage: "arrow.up")
        }.font(.system(size: 11)).foregroundStyle(palette.secondary).monospacedDigit().fixedSize()
    }
    private var relayBadge: some View {
        Label("转发", systemImage: "arrow.left.arrow.right").font(.system(size: 10)).foregroundStyle(palette.secondary)
            .help("可能包含其他程序经代理或 VPN 转发的流量，不应与原程序相加")
    }
    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: search.isEmpty ? "chart.bar" : "magnifyingglass").font(.system(size: 23)).foregroundStyle(palette.secondary)
            Text(!search.isEmpty ? "没有匹配的进程" : monitor.paused ? "统计已暂停" : hasError ? "暂时无法读取流量" : monitor.lastSample == nil ? "正在建立统计基线" : "这个时段还没有记录")
                .font(.system(size: 12, weight: .medium))
            Text(!search.isEmpty ? "试试进程名称的一部分。" : "流量从工具运行后累计，未运行的历史无法补算。")
                .font(.system(size: 11)).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
            if !search.isEmpty { Button("清除搜索") { search = "" }.controlSize(.small) }
            else if monitor.paused { Button("继续记录") { monitor.togglePause() }.controlSize(.small) }
            else if hasError { Button("重新采集") { monitor.sample() }.controlSize(.small) }
            else if monitor.selectedNetwork != "__all__" { Button("查看全部网络") { monitor.selectedNetwork = "__all__" }.controlSize(.small) }
        }.frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 14)
    }
    private var errorBanner: some View {
        Label(monitor.status, systemImage: "exclamationmark.circle")
            .font(.system(size: 11)).lineLimit(2).help(monitor.status)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(palette.border).frame(height: 0.5)
            HStack {
                Button { explanation.toggle() } label: { Label("统计说明", systemImage: "info.circle") }
                    .buttonStyle(.borderless).accessibilityLabel("显示或隐藏统计说明")
                Spacer()
                Button { monitor.export() } label: { Label("导出 CSV", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
            }.font(.system(size: 11)).foregroundStyle(palette.secondary)
            if explanation {
                ScrollView {
                    Text("整机总量来自物理网卡，包含局域网流量，不等于运营商账单。进程排行包含代理与 VPN 转发，请勿相加。\n\n每 10 秒采样，每分钟保存。网络无法识别时只记录全部。\n\n开始记录：\(monitor.ledger.firstStarted.formatted(date: .numeric, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(height: 96).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
            }
            if !loginError.isEmpty {
                Text(loginError).font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
        }
    }
    private func isRelay(_ name: String) -> Bool {
        ["tailscale", "mihomo", "clash", "proxifier", "vpn"].contains { name.lowercased().contains($0) }
    }
    private func setLogin(_ enabled: Bool) {
        do {
            try monitor.setLogin(enabled)
            loginError = ""
        } catch {
            loginError = "请先把应用放入“应用程序”，再设置登录启动。"
        }
    }
}
