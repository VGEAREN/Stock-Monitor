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
                s.sort {
                    let a = appState.quotes[$0.id]?.changePercent ?? -Double.infinity
                    let b = appState.quotes[$1.id]?.changePercent ?? -Double.infinity
                    return a > b
                }
            }
            return s.isEmpty ? nil : (market, s)
        }
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
