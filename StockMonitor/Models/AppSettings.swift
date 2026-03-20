import Foundation

enum DisplayCurrency: String, Codable, CaseIterable {
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

enum SortRule: String, Codable, CaseIterable {
    case changeDesc = "changeDesc"
    case changeAsc  = "changeAsc"

    var displayName: String {
        switch self {
        case .changeDesc: return "涨跌幅降序"
        case .changeAsc:  return "涨跌幅升序"
        }
    }
}

enum USPriceMode: String, Codable, CaseIterable {
    case sessionPrice = "session"
    case regularPrice = "regular"

    var displayName: String {
        switch self {
        case .sessionPrice: return "当前价（时段价格）"
        case .regularPrice: return "盘中价"
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
    var statusBarStockId: String         = ""
    var refreshInterval: Int             = 5
    var colorScheme: ColorTheme          = .chinese
    var displayCurrency: DisplayCurrency = .cny
    var sortRule: SortRule               = .changeDesc
    var usPriceMode: USPriceMode         = .sessionPrice

    static let validRefreshIntervals = [3, 5, 10, 30]

    var upColorName: String   { colorScheme == .chinese ? "upRed"   : "upGreen" }
    var downColorName: String { colorScheme == .chinese ? "downGreen" : "downRed" }
}

// MARK: - Codable（容错：缺失字段使用默认值）
extension AppSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case statusBarStockId, refreshInterval, colorScheme, displayCurrency, sortRule, usPriceMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusBarStockId = (try? c.decodeIfPresent(String.self,          forKey: .statusBarStockId))  ?? ""
        refreshInterval  = (try? c.decodeIfPresent(Int.self,             forKey: .refreshInterval))   ?? 5
        colorScheme      = (try? c.decodeIfPresent(ColorTheme.self,      forKey: .colorScheme))       ?? .chinese
        displayCurrency  = (try? c.decodeIfPresent(DisplayCurrency.self, forKey: .displayCurrency))   ?? .cny
        sortRule         = (try? c.decodeIfPresent(SortRule.self,         forKey: .sortRule))           ?? .changeDesc
        usPriceMode      = (try? c.decodeIfPresent(USPriceMode.self,     forKey: .usPriceMode))        ?? .sessionPrice
    }
}
