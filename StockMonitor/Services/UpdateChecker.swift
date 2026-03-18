import Foundation
import AppKit
import Combine

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}

@MainActor
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()
    private init() {}

    @Published var isChecking = false

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        Task { await run() }
    }

    private func run() async {
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/VGEAREN/Stockbar/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            alert(title: "检查失败", body: "无法获取版本信息，请检查网络连接。")
            return
        }

        let latestTag = release.tagName
        let latest  = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        if isNewer(latest, than: current) {
            let a = NSAlert()
            a.messageText    = "发现新版本 \(latest)"
            a.informativeText = "当前版本 \(current)。下载 DMG 后将旧版本替换即可完成更新。"
            a.addButton(withTitle: "前往下载")
            a.addButton(withTitle: "暂不更新")
            if a.runModal() == .alertFirstButtonReturn,
               let releaseURL = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(releaseURL)
            }
        } else {
            alert(title: "已是最新版本", body: "当前版本 \(current) 已是最新。")
        }
    }

    /// 逐段比较语义版本，"1.0" 与 "1.0.0" 视为相等，不误报
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap  { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private func alert(title: String, body: String) {
        let a = NSAlert()
        a.messageText     = title
        a.informativeText = body
        a.addButton(withTitle: "好")
        a.runModal()
    }
}
