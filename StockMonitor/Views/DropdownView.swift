import SwiftUI

struct DropdownView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var sortByChange = false
    @State private var selectedStock: Stock? = nil

    /// 分组数据：(market, stocks, customTitle?)
    private var groupedStocks: [(Market, [Stock], String?)] {
        let rule = appState.config.sortRule
        let usMode = appState.config.usPriceMode
        let doSort = sortByChange

        func sorted(_ stocks: [Stock], market: Market) -> [Stock] {
            guard doSort else { return stocks }
            return stocks.sorted { a, b in
                let va = sortValue(quote: appState.quotes[a.id], market: market, mode: usMode)
                let vb = sortValue(quote: appState.quotes[b.id], market: market, mode: usMode)
                return rule == .changeDesc ? va > vb : va < vb
            }
        }

        var result: [(Market, [Stock], String?)] = []

        // 持仓股单独分组
        if appState.config.groupHoldings {
            let holdings = appState.stocks.filter { appState.effectiveShares(for: $0) != nil }
            if !holdings.isEmpty {
                // 持仓组内按第一只股票的市场类型排序（混合市场）
                let sortedHoldings = doSort ? holdings.sorted { a, b in
                    let va = sortValue(quote: appState.quotes[a.id], market: a.market, mode: usMode)
                    let vb = sortValue(quote: appState.quotes[b.id], market: b.market, mode: usMode)
                    return rule == .changeDesc ? va > vb : va < vb
                } : holdings
                result.append((.aStock, sortedHoldings, "持仓"))
            }
            let holdingIds = Set(holdings.map(\.id))
            for market in [Market.aStock, .hkStock, .usStock, .krStock] {
                let s = appState.stocks.filter { $0.market == market && !holdingIds.contains($0.id) }
                if !s.isEmpty { result.append((market, sorted(s, market: market), nil)) }
            }
        } else {
            for market in [Market.aStock, .hkStock, .usStock, .krStock] {
                let s = appState.stocks.filter { $0.market == market }
                if !s.isEmpty { result.append((market, sorted(s, market: market), nil)) }
            }
        }

        return result
    }

    private var stockListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(groupedStocks.enumerated()), id: \.offset) { _, group in
                    StockGroupView(market: group.0, stocks: group.1,
                                   title: group.2,
                                   onSelect: { selectedStock = $0 })
                }
            }
            .padding(.horizontal, 6)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 520)
    }

    private func sortValue(quote: Quote?, market: Market, mode: USPriceMode) -> Double {
        guard let q = quote else { return -Double.infinity }
        if market == .usStock && mode == .sessionPrice, let ext = q.extendedPrice {
            // 用时段价格算涨跌幅：(盘外价 - 正盘价) / 正盘价
            return q.price > 0 ? (ext - q.price) / q.price * 100 : q.changePercent
        }
        return q.changePercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSettings {
                SettingsView(showSettings: $showSettings)
            } else {
                ProfitSummaryView()

                if appState.stocks.isEmpty {
                    Text("暂无股票，点击设置添加")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ZStack {
                        stockListView
                            .opacity(selectedStock == nil ? 1 : 0)
                        if let stock = selectedStock {
                            StockChartView(stock: stock, onClose: { selectedStock = nil })
                        }
                    }
                }

                Divider()
                ToolbarView(showSettings: $showSettings, sortByChange: $sortByChange)
            }
        }
        .padding(6)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
