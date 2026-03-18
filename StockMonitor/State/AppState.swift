import SwiftUI
import Combine
import AppKit
import os

@MainActor
final class AppState: ObservableObject {

    // MARK: - 持久化（UserDefaults via @AppStorage）

    @AppStorage("statusBarStockId")    var statusBarStockId: String    = ""
    @AppStorage("refreshInterval")     var refreshInterval: Int        = 5
    @AppStorage("colorSchemeRaw")      var colorSchemeRaw: String      = ColorTheme.chinese.rawValue
    @AppStorage("displayCurrencyRaw")  var displayCurrencyRaw: String  = DisplayCurrency.cny.rawValue

    // MARK: - 实时状态

    @Published var quotes: [String: Quote]    = [:]
    @Published var exchangeRates: ExchangeRates = ExchangeRates()
    @Published var isLoading: Bool            = false
    @Published var lastUpdateTime: Date?      = nil
    @Published var hasError: Bool             = false

    // MARK: - 股票列表（持久化到 Application Support/StockMonitor/stocks.json）

    @Published var stocks: [Stock] = [] {
        didSet { saveStocks(stocks) }
    }

    private static var stocksFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("StockMonitor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stocks.json")
    }

    private static func loadStocks() -> [Stock] {
        guard let data = try? Data(contentsOf: stocksFileURL),
              let stocks = try? JSONDecoder().decode([Stock].self, from: data) else { return [] }
        return stocks
    }

    private func saveStocks(_ stocks: [Stock]) {
        // 防止把空数组覆盖掉磁盘上有内容的文件
        if stocks.isEmpty, !Self.loadStocks().isEmpty { return }
        guard let data = try? JSONEncoder().encode(stocks) else { return }
        Self.backupIfNeeded()
        try? data.write(to: Self.stocksFileURL, options: .atomic)
    }

    /// 保存前备份当前文件，最多保留 10 份（stocks.1.json … stocks.10.json）
    private static func backupIfNeeded() {
        let fm = FileManager.default
        let src = stocksFileURL
        guard fm.fileExists(atPath: src.path) else { return }
        let dir = src.deletingLastPathComponent()

        // 向后滚动：stocks.9.json → stocks.10.json … stocks.1.json → stocks.2.json
        for i in stride(from: 9, through: 1, by: -1) {
            let from = dir.appendingPathComponent("stocks.\(i).json")
            let to   = dir.appendingPathComponent("stocks.\(i + 1).json")
            if fm.fileExists(atPath: from.path) {
                try? fm.removeItem(at: to)
                try? fm.moveItem(at: from, to: to)
            }
        }
        // 当前文件 → stocks.1.json
        let backup = dir.appendingPathComponent("stocks.1.json")
        try? fm.removeItem(at: backup)
        try? fm.copyItem(at: src, to: backup)
    }

    var colorScheme: ColorTheme {
        get { ColorTheme(rawValue: colorSchemeRaw) ?? .chinese }
        set { colorSchemeRaw = newValue.rawValue }
    }

    var displayCurrency: DisplayCurrency {
        get { DisplayCurrency(rawValue: displayCurrencyRaw) ?? .cny }
        set { displayCurrencyRaw = newValue.rawValue }
    }

    // MARK: - 刷新调度

    private var scheduler: RefreshScheduler?

    init() {
        appLogger.info("AppState init start")
        logToFile("AppState init start")
        // 用 _stocks 直接赋值，绕过 didSet，避免加载失败时把空数组覆盖写回磁盘
        _stocks = Published(wrappedValue: Self.loadStocks())
        appLogger.info("AppState stocks loaded: \(self.stocks.count)")
        logToFile("AppState stocks loaded: \(self.stocks.count)")
        setupScheduler()
        appLogger.info("AppState init complete")
        logToFile("AppState init complete")
        // 监听系统唤醒，解锁/休眠恢复后重新启动刷新
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restartScheduler() }
        }
    }

    func setupScheduler() {
        scheduler = RefreshScheduler { [weak self] in await self?.refresh() }
        scheduler?.start(interval: TimeInterval(refreshInterval))
    }

    func restartScheduler() {
        scheduler?.stop()
        setupScheduler()
    }

    func forceRefresh() { scheduler?.forceRefresh() }

    // MARK: - 数据拉取

    func refresh() async {
        isLoading = true
        hasError  = false
        do {
            let all       = stocks.map(\.id)
            let sinaCodes = all.filter { !$0.hasPrefix("hk") }
            let hkCodes   = all.filter {  $0.hasPrefix("hk") }
            async let sinaResult  = DataService.fetchSinaQuotes(codes: sinaCodes)
            async let hkResult    = DataService.fetchTencentHKQuotes(codes: hkCodes)
            async let ratesResult = CurrencyService.fetchRates()
            let (s, h) = try await (sinaResult, hkResult)
            let rates  = await ratesResult
            quotes.merge(s) { $1 }
            quotes.merge(h) { $1 }
            exchangeRates  = rates
            lastUpdateTime = Date()
            syncStockNamesFromQuotes()
        } catch {
            hasError = true
        }
        isLoading = false
    }

    /// 将 API 返回的中文名称同步到 stocks，避免直接输入代码添加时显示代码而非中文名
    private func syncStockNamesFromQuotes() {
        var updated = stocks
        var changed = false
        for i in updated.indices {
            if let q = quotes[updated[i].id], !q.name.isEmpty, q.name != updated[i].name {
                updated[i].name = q.name
                changed = true
            }
        }
        if changed { stocks = updated }
    }

    // MARK: - 持仓汇总

    var totalPnL: Double {
        stocks.compactMap { s -> Double? in
            guard let q = quotes[s.id], let pnl = s.pnl(quote: q) else { return nil }
            return exchangeRates.convert(pnl, from: s.market, to: displayCurrency)
        }.reduce(0, +)
    }

    var totalDailyPnL: Double {
        stocks.compactMap { s -> Double? in
            guard let q = quotes[s.id], let pnl = s.dailyPnl(quote: q) else { return nil }
            return exchangeRates.convert(pnl, from: s.market, to: displayCurrency)
        }.reduce(0, +)
    }

    var hasPnLData: Bool {
        stocks.contains { $0.costPrice != nil && $0.holdingShares != nil }
    }

    // MARK: - 状态栏股票（含 fallback）

    /// fallback：statusBarStockId 被删除时自动取第一只；"__none__" 或列表为空返回 nil
    var statusBarStock: Stock? {
        if statusBarStockId == "__none__" { return nil }
        return stocks.first(where: { $0.id == statusBarStockId }) ?? stocks.first
    }

    var statusBarQuote: Quote? {
        guard let s = statusBarStock else { return nil }
        return quotes[s.id]
    }

    // MARK: - 设置 & 颜色辅助

    /// 当前 AppSettings 快照（用于颜色查找等只读场景）
    var settings: AppSettings {
        AppSettings(colorScheme: colorScheme, refreshInterval: refreshInterval,
                    statusBarStockId: statusBarStockId.isEmpty ? nil : statusBarStockId)
    }

    func quoteColor(for quote: Quote) -> Color {
        if quote.isUp   { return Color(settings.upColorName) }
        if quote.isDown { return Color(settings.downColorName) }
        return .secondary
    }

    func pnlColor(_ pnl: Double) -> Color {
        if pnl > 0 { return Color(settings.upColorName) }
        if pnl < 0 { return Color(settings.downColorName) }
        return .secondary
    }

    /// 当前美股交易时段（按 ET 时间）
    /// 盘前 04:00-09:30 | 盘中 09:30-16:00 | 盘后 16:00-20:00 | 夜盘 20:00-04:00
    static func usMarketSession() -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date()
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let weekday = comps.weekday ?? 1   // 1=Sun, 7=Sat
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        switch minutes {
        case 0..<240:    // 00:00-04:00 夜盘（属于前一交易日延续）
            // Tue-Sat（对应 Mon-Fri 夜盘延续）
            guard weekday >= 3, weekday <= 7 else { return nil }
            return "夜盘"
        case 240..<570:  // 04:00-09:30 盘前，Mon-Fri
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "盘前"
        case 570..<960:  // 09:30-16:00 盘中，Mon-Fri
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "盘中"
        case 960..<1200: // 16:00-20:00 盘后，Mon-Fri
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "盘后"
        case 1200..<1440: // 20:00-24:00 夜盘，Mon-Fri
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "夜盘"
        default:
            return nil
        }
    }
}
