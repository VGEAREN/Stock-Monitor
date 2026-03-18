import SwiftUI

struct ProfitSummaryView: View {
    @EnvironmentObject var appState: AppState

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        if appState.hasPnLData {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("持仓盈亏").font(.system(size: 10)).foregroundColor(.secondary)
                    if let t = appState.lastUpdateTime {
                        Text("更新：\(Self.timeFmt.string(from: t))\(appState.hasError ? " ⚠" : "")")
                            .font(.system(size: 9))
                            .foregroundColor(appState.hasError ? .yellow : .secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    let sym   = appState.displayCurrency.symbol
                    let daily = appState.totalDailyPnL
                    let sign1 = daily >= 0 ? "+" : "-"
                    Text("日\(sign1)\(sym)\(String(format: "%.2f", abs(daily)))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.pnlColor(daily))
                    let pnl   = appState.totalPnL
                    let sign2 = pnl >= 0 ? "+" : "-"
                    Text("浮\(sign2)\(sym)\(String(format: "%.2f", abs(pnl)))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.pnlColor(pnl))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
        }
    }
}
