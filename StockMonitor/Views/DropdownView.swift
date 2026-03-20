import SwiftUI

struct DropdownView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var sortByChange = false
    @State private var selectedStock: Stock? = nil

    private var groupedStocks: [(Market, [Stock])] {
        [Market.aStock, .hkStock, .usStock].compactMap { market in
            var s = appState.stocks.filter { $0.market == market }
            if sortByChange {
                let rule = appState.config.sortRule
                let usMode = appState.config.usPriceMode
                s.sort { a, b in
                    let qa = appState.quotes[a.id]
                    let qb = appState.quotes[b.id]
                    let va = sortValue(quote: qa, market: market, mode: usMode)
                    let vb = sortValue(quote: qb, market: market, mode: usMode)
                    return rule == .changeDesc ? va > vb : va < vb
                }
            }
            return s.isEmpty ? nil : (market, s)
        }
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

                if let stock = selectedStock {
                    StockChartView(stock: stock, onClose: { selectedStock = nil })
                } else if appState.stocks.isEmpty {
                    Text("暂无股票，点击设置添加")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(groupedStocks, id: \.0) { market, stocks in
                                StockGroupView(market: market, stocks: stocks,
                                               onSelect: { selectedStock = $0 })
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .scrollIndicators(.never)
                    .frame(maxHeight: 520)
                }

                Divider()
                ToolbarView(showSettings: $showSettings, sortByChange: $sortByChange)
            }
        }
        .padding(6)
        .frame(width: 320)
    }
}
