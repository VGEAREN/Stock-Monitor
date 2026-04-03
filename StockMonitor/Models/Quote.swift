import Foundation

struct Quote {
    var code: String
    var name: String = ""
    var price: Double
    var change: Double          // 涨跌额
    var changePercent: Double   // 涨跌幅（如 5.12 表示 +5.12%）
    var updateTime: String      // 原始时间字符串，仅用于显示
    var extendedPrice: Double? = nil  // 盘前/盘后价（仅美股）

    var previousClose: Double { price - change }

    /// 相对于正盘收盘价的涨跌幅
    var extendedChangePercent: Double? {
        guard let ext = extendedPrice, price > 0 else { return nil }
        return (ext - price) / price * 100
    }

    var formattedExtendedPrice: String? {
        guard let p = extendedPrice else { return nil }
        if p >= 10 { return String(format: "%.2f", p) }
        return String(format: "%.3f", p)
    }

    var formattedExtendedPercent: String? {
        guard let pct = extendedChangePercent else { return nil }
        let sign = pct >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", pct)
    }

    var isUp:   Bool { change > 0 }
    var isDown: Bool { change < 0 }

    /// 数据是否为今天（通过 updateTime 中的日期判断）
    var isToday: Bool {
        // 匹配 yyyy-MM-dd 或 yyyy/MM/dd 格式
        let digits = updateTime.replacingOccurrences(of: "/", with: "-")
        guard digits.count >= 10 else { return false }
        let dateStr = String(digits.prefix(10))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let today = fmt.string(from: Date())
        return dateStr == today
    }

    var formattedPercent: String {
        let sign = changePercent >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", changePercent)
    }

    var formattedPrice: String {
        if price >= 10 { return String(format: "%.2f", price) }
        return String(format: "%.3f", price)
    }
}
