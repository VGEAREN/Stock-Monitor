import Foundation
import ServiceManagement

/// 开机自启管理：SMAppService 优先，LaunchAgent plist 兜底
enum LaunchAtLogin {

    private static let bundleId  = Bundle.main.bundleIdentifier ?? "com.vgearen.Stockbar"
    private static let plistName = "\(bundleId).plist"
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(plistName)
    }

    // MARK: - 公开接口

    static var isEnabled: Bool {
        // 先查 SMAppService
        if SMAppService.mainApp.status == .enabled { return true }
        // 再查 LaunchAgent plist 是否存在
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    // MARK: - 启用

    private static func enable() {
        // 尝试 SMAppService
        do {
            try SMAppService.mainApp.register()
            logToFile("LaunchAtLogin: SMAppService register OK")
        } catch {
            logToFile("LaunchAtLogin: SMAppService register failed: \(error), falling back to LaunchAgent")
        }
        // 同时写 LaunchAgent plist 兜底
        writeLaunchAgent()
    }

    // MARK: - 禁用

    private static func disable() {
        // 清除 SMAppService
        do {
            try SMAppService.mainApp.unregister()
            logToFile("LaunchAtLogin: SMAppService unregister OK")
        } catch {
            logToFile("LaunchAtLogin: SMAppService unregister failed: \(error)")
        }
        // 清除 LaunchAgent plist
        removeLaunchAgent()
    }

    // MARK: - LaunchAgent plist

    private static func writeLaunchAgent() {
        guard let appPath = Bundle.main.executablePath else {
            logToFile("LaunchAtLogin: cannot get executable path")
            return
        }
        let plist: [String: Any] = [
            "Label": bundleId,
            "ProgramArguments": [appPath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        if let data = data {
            do {
                try data.write(to: plistURL, options: .atomic)
                logToFile("LaunchAtLogin: wrote LaunchAgent plist to \(plistURL.path)")
            } catch {
                logToFile("LaunchAtLogin: failed to write plist: \(error)")
            }
        }
    }

    private static func removeLaunchAgent() {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try? FileManager.default.removeItem(at: plistURL)
            logToFile("LaunchAtLogin: removed LaunchAgent plist")
        }
    }
}
