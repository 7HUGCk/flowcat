import AppKit
import Foundation

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private var checking = false
    func check() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/tab16360/flowcat/releases/latest")!)
                request.timeoutInterval = 20
                request.setValue("FlowCat-update-check", forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForResource = 30
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw NSError(domain: "FlowCat.Update", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                        userInfo: [NSLocalizedDescriptionKey: "GitHub 暂时无法返回版本信息，请稍后重试。"])
                }
                let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                guard let url = release.downloadURL else {
                    throw NSError(domain: "FlowCat.Update", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "该版本尚无可用的 Apple Silicon 安装包，请稍后重试。"])
                }
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                if release.isNewer(than: current) {
                    alert.messageText = "流量喵 \(release.version) 可更新"
                    let notes = String((release.body ?? "").prefix(900))
                    alert.informativeText = "当前版本：\(current)\n\n\(notes)\n\n下载后退出旧版，将新应用拖入“应用程序”替换。历史记录保留。"
                    alert.addButton(withTitle: "下载更新")
                    alert.addButton(withTitle: "稍后")
                    if alert.runModal() == .alertFirstButtonReturn, !NSWorkspace.shared.open(url) {
                        showError("无法打开下载链接，请检查默认浏览器设置。")
                    }
                } else {
                    alert.messageText = "已是最新版本"
                    alert.informativeText = "当前版本：\(current)"
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                }
            } catch { showError(error.localizedDescription) }
        }
    }
    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
