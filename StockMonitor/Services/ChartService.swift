import Foundation

struct MinutePoint: Identifiable {
    let id: Int       // 分钟偏移量（用作 x 轴坐标，美股以前日 20:00 ET 为 0）
    let time: String  // "09:30"
    let price: Double
}

final class ChartService {

    /// 获取当日分时数据
    static func fetchIntraday(stock: Stock) async throws -> (points: [MinutePoint], preClose: Double) {
        if stock.market == .usStock {
            return try await fetchUSIntraday(stockId: stock.id)
        }
        if stock.market == .krStock {
            return try await fetchKoreanIntraday(stockId: stock.id)
        }
        return try await fetchTencentIntraday(stock: stock)
    }

    // MARK: - 腾讯 API（A股 / 港股）

    private static func fetchTencentIntraday(stock: Stock) async throws -> (points: [MinutePoint], preClose: Double) {
        let code = stock.id
        let urlStr = "https://web.ifzq.gtimg.cn/appstock/app/minute/query?_var=min_data_\(code)&code=\(code)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let body = String(data: data, encoding: .utf8) ?? ""

        guard let eqIdx = body.firstIndex(of: "=") else { throw URLError(.cannotParseResponse) }
        let jsonStr = String(body[body.index(after: eqIdx)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: ";\n "))

        guard let jsonData = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let stockData = dataObj[code] as? [String: Any],
              let innerData = stockData["data"] as? [String: Any],
              let lines = innerData["data"] as? [String]
        else { throw URLError(.cannotParseResponse) }

        let preCloseStr = (innerData["preclose"] as? String) ?? "0"
        let preClose = Double(preCloseStr) ?? 0

        var points: [MinutePoint] = []
        for (i, line) in lines.enumerated() {
            let parts = line.components(separatedBy: " ")
            guard parts.count >= 2,
                  let price = Double(parts[1]), price > 0 else { continue }
            points.append(MinutePoint(id: i, time: parts[0], price: price))
        }

        guard !points.isEmpty else { throw URLError(.cannotParseResponse) }
        return (points, preClose)
    }

    // MARK: - Yahoo Finance API（美股，盘前→盘中→盘后，04:00-20:00 ET）
    // x 轴以 04:00 ET 为 index=0，最大 index=959

    private static func fetchUSIntraday(stockId: String) async throws -> (points: [MinutePoint], preClose: Double) {
        let ticker = stockId
            .replacingOccurrences(of: "usr_", with: "")
            .replacingOccurrences(of: "$", with: "-")
            .uppercased()

        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1m&range=1d&includePrePost=true"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first else { throw URLError(.cannotParseResponse) }

        let meta = result["meta"] as? [String: Any] ?? [:]
        let preClose = (meta["chartPreviousClose"] as? Double)
                    ?? (meta["previousClose"] as? Double)
                    ?? 0

        guard let timestamps = result["timestamp"] as? [Double],
              let indicators = result["indicators"] as? [String: Any],
              let quoteArr = indicators["quote"] as? [[String: Any]],
              let rawCloses = quoteArr.first?["close"] as? [Any]
        else { throw URLError(.cannotParseResponse) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let fmt = DateFormatter()
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "HH:mm"

        var points: [MinutePoint] = []
        for (i, ts) in timestamps.enumerated() {
            guard i < rawCloses.count,
                  let price = rawCloses[i] as? Double, price > 0 else { continue }
            let date = Date(timeIntervalSince1970: ts)
            let comps = cal.dateComponents([.hour, .minute], from: date)
            let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let idx = minuteOfDay - (4 * 60)   // 距 04:00 的分钟数
            guard idx >= 0, idx <= 959 else { continue }
            points.append(MinutePoint(id: idx, time: fmt.string(from: date), price: price))
        }

        guard !points.isEmpty else { throw URLError(.cannotParseResponse) }
        return (points, preClose)
    }

    // MARK: - Yahoo Finance API（韩股，KST 09:00-15:30）
    // x 轴以 09:00 KST 为 index=0，最大 index=389（15:29）

    private static func fetchKoreanIntraday(stockId: String) async throws -> (points: [MinutePoint], preClose: Double) {
        guard let symbol = KoreanStockID.toYahooSymbol(stockId) else {
            throw URLError(.badURL)
        }
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1m&range=1d"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let result = parseKoreanChartPoints(data) else { throw URLError(.cannotParseResponse) }
        return result
    }

    /// 解析 Yahoo v8 chart 响应为韩股 MinutePoint 列表 + 昨收。
    /// 抽出供单元测试使用；失败返回 nil。
    static func parseKoreanChartPoints(_ data: Data) -> (points: [MinutePoint], preClose: Double)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first else { return nil }

        let meta = result["meta"] as? [String: Any] ?? [:]
        let preClose = (meta["chartPreviousClose"] as? Double)
                    ?? (meta["previousClose"] as? Double)
                    ?? 0
        guard let timestamps = result["timestamp"] as? [Double],
              let indicators = result["indicators"] as? [String: Any],
              let quoteArr = indicators["quote"] as? [[String: Any]],
              let rawCloses = quoteArr.first?["close"] as? [Any] else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let fmt = DateFormatter()
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "HH:mm"

        var points: [MinutePoint] = []
        for (i, ts) in timestamps.enumerated() {
            guard i < rawCloses.count,
                  let price = rawCloses[i] as? Double, price > 0 else { continue }
            let date = Date(timeIntervalSince1970: ts)
            let comps = cal.dateComponents([.hour, .minute], from: date)
            let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let idx = minuteOfDay - (9 * 60)  // 距 09:00 的分钟数
            guard idx >= 0, idx <= 389 else { continue }
            points.append(MinutePoint(id: idx, time: fmt.string(from: date), price: price))
        }
        guard !points.isEmpty else { return nil }
        return (points, preClose)
    }
}
