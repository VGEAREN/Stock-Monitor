import SwiftUI
import Combine
import AppKit
import os

@MainActor
final class AppState: ObservableObject {

    // MARK: - 持久化（settings.json）

    @Published var config: AppSettings = AppSettings() {
        didSet { saveSettings(config) }
    }

    // MARK: - 持久化（stocks.json）

    @Published var stocks: [Stock] = [] {
        didSet { saveStocks(stocks) }
    }

    // MARK: - 实时状态

    @Published var quotes: [String: Quote]      = [:]
    @Published var exchangeRates: ExchangeRates = ExchangeRates()
    @Published var isLoading: Bool              = false
    @Published var lastUpdateTime: Date?        = nil
    @Published var hasError: Bool               = false

    // MARK: - 文件路径

    private static var appSupportDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Stockbar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var stocksFileURL:   URL { appSupportDir.appendingPathComponent("stocks.json")   }
    private static var settingsFileURL: URL { appSupportDir.appendingPathComponent("settings.json") }

    // MARK: - 加载

    private static func loadStocks() -> [Stock] {
        guard let data = try? Data(contentsOf: stocksFileURL),
              let val  = try? JSONDecoder().decode([Stock].self, from: data) else { return [] }
        return val
    }

    private static func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsFileURL),
              let val  = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return val
    }

    // MARK: - 保存

    private func saveStocks(_ stocks: [Stock]) {
        if stocks.isEmpty, !Self.loadStocks().isEmpty { return }
        guard let data = try? JSONEncoder().encode(stocks) else { return }
        Self.backupIfNeeded()
        try? data.write(to: Self.stocksFileURL, options: .atomic)
    }

    private func saveSettings(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: Self.settingsFileURL, options: .atomic)
    }

    /// 滚动备份 stocks.json，最多保留 10 份
    private static func backupIfNeeded() {
        let fm  = FileManager.default
        let src = stocksFileURL
        guard fm.fileExists(atPath: src.path) else { return }
        let dir = src.deletingLastPathComponent()
        for i in stride(from: 9, through: 1, by: -1) {
            let from = dir.appendingPathComponent("stocks.\(i).json")
            let to   = dir.appendingPathComponent("stocks.\(i + 1).json")
            if fm.fileExists(atPath: from.path) {
                try? fm.removeItem(at: to)
                try? fm.moveItem(at: from, to: to)
            }
        }
        let backup = dir.appendingPathComponent("stocks.1.json")
        try? fm.removeItem(at: backup)
        try? fm.copyItem(at: src, to: backup)
    }

    // MARK: - 设置快捷访问（视图直接绑定这些属性）

    var statusBarStockId: String {
        get { config.statusBarStockId }
        set { config.statusBarStockId = newValue }
    }

    var refreshInterval: Int {
        get { config.refreshInterval }
        set { config.refreshInterval = newValue }
    }

    var colorScheme: ColorTheme {
        get { config.colorScheme }
        set { config.colorScheme = newValue }
    }

    var displayCurrency: DisplayCurrency {
        get { config.displayCurrency }
        set { config.displayCurrency = newValue }
    }

    // MARK: - 刷新调度

    private var scheduler: RefreshScheduler?

    init() {
        appLogger.info("AppState init start")
        logToFile("AppState init start")
        _stocks = Published(wrappedValue: Self.loadStocks())
        _config = Published(wrappedValue: Self.loadSettings())
        appLogger.info("AppState stocks loaded: \(self.stocks.count)")
        logToFile("AppState stocks loaded: \(self.stocks.count)")
        setupScheduler()
        appLogger.info("AppState init complete")
        logToFile("AppState init complete")
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

    // MARK: - 状态栏

    var statusBarStock: Stock? {
        if statusBarStockId == "__none__" { return nil }
        return stocks.first(where: { $0.id == statusBarStockId }) ?? stocks.first
    }

    var statusBarQuote: Quote? {
        guard let s = statusBarStock else { return nil }
        return quotes[s.id]
    }

    // MARK: - 颜色辅助

    func quoteColor(for quote: Quote) -> Color {
        if quote.isUp   { return Color(config.upColorName) }
        if quote.isDown { return Color(config.downColorName) }
        return .secondary
    }

    func pnlColor(_ pnl: Double) -> Color {
        if pnl > 0 { return Color(config.upColorName) }
        if pnl < 0 { return Color(config.downColorName) }
        return .secondary
    }

    // MARK: - 美股交易时段

    static func usMarketSession() -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now   = Date()
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let weekday = comps.weekday ?? 1
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        switch minutes {
        case 0..<240:
            guard weekday >= 3, weekday <= 7 else { return nil }
            return "夜盘"
        case 240..<570:
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "盘前"
        case 570..<960:
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "盘中"
        case 960..<1200:
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "盘后"
        case 1200..<1440:
            guard weekday >= 2, weekday <= 6 else { return nil }
            return "夜盘"
        default:
            return nil
        }
    }
}
