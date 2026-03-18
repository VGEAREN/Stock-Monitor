import Foundation

enum DisplayCurrency: String, CaseIterable {
    case cny = "CNY"
    case hkd = "HKD"
    case usd = "USD"

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .hkd: return "HK$"
        case .usd: return "$"
        }
    }

    var displayName: String {
        switch self {
        case .cny: return "人民币 ¥"
        case .hkd: return "港币 HK$"
        case .usd: return "美元 $"
        }
    }
}

enum ColorTheme: String, Codable, CaseIterable {
    case chinese = "chinese"  // 红涨绿跌
    case western = "western"  // 绿涨红跌

    var displayName: String {
        switch self {
        case .chinese: return "红涨绿跌"
        case .western: return "绿涨红跌"
        }
    }
}

struct AppSettings {
    var colorScheme: ColorTheme
    var refreshInterval: Int        // 秒，合法值见 validRefreshIntervals
    var statusBarStockId: String?

    static let validRefreshIntervals = [3, 5, 10, 30]

    /// 上涨颜色 Asset 名称（在 Assets.xcassets 中定义）
    var upColorName: String   { colorScheme == .chinese ? "upRed"   : "upGreen" }
    /// 下跌颜色 Asset 名称
    var downColorName: String { colorScheme == .chinese ? "downGreen" : "downRed" }
}
