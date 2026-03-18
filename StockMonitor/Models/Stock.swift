import Foundation

enum Market: String, Codable, CaseIterable {
    case aStock  = "A股"
    case hkStock = "港股"
    case usStock = "美股"

    static func from(code: String) -> Market {
        if code.hasPrefix("hk")   { return .hkStock }
        if code.hasPrefix("usr_") { return .usStock }
        return .aStock
    }
}

struct Stock: Identifiable, Equatable {
    var id: String              // 股票代码，如 "sh600000"、"usr_aapl"、"hk00700"
    var name: String
    var market: Market
    var costPrice: Double?      // 持仓成本价（nil = 未设置）
    var holdingShares: Double?  // 持仓股数（nil = 未设置）

    /// 持仓浮盈亏 = (当前价 - 成本价) × 股数；未设置持仓则返回 nil
    func pnl(quote: Quote) -> Double? {
        guard let cost = costPrice, let shares = holdingShares else { return nil }
        return (quote.price - cost) * shares
    }

    /// 当日盈亏 = 涨跌额 × 股数；未设置股数则返回 nil
    func dailyPnl(quote: Quote) -> Double? {
        guard let shares = holdingShares else { return nil }
        return quote.change * shares
    }
}

// MARK: - Codable（容错：未知字段用默认值，避免新版本解码老数据时整条失败）
extension Stock: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, market, costPrice, holdingShares
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self,  forKey: .id)
        name         = try c.decode(String.self,  forKey: .name)
        market       = try c.decode(Market.self,  forKey: .market)
        costPrice    = try c.decodeIfPresent(Double.self, forKey: .costPrice)
        holdingShares = try c.decodeIfPresent(Double.self, forKey: .holdingShares)
    }
}
