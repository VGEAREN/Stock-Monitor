import SwiftUI

struct StockRowView: View {
    let stock: Stock
    let quote: Quote?
    var onTap: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 左侧：名称 + 代码
            VStack(alignment: .leading, spacing: 1) {
                Text(stock.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(stock.id)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            // 右侧：行情 + 盈亏
            if let q = quote {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(q.formattedPrice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(appState.quoteColor(for: q))
                        Text(q.formattedPercent)
                            .font(.system(size: 11))
                            .foregroundColor(appState.quoteColor(for: q))
                    }
                    if stock.market == .usStock,
                       let session = AppState.usMarketSession(),
                       let extPrice = q.formattedExtendedPrice,
                       let extPct = q.formattedExtendedPercent {
                        Text("\(session) \(extPrice)  \(extPct)")
                            .font(.system(size: 9))
                            .foregroundColor(
                                (q.extendedChangePercent ?? 0) >= 0
                                    ? Color(appState.config.upColorName)
                                    : Color(appState.config.downColorName)
                            )
                    }
                    if stock.holdingShares == nil {
                        Text("未持仓")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            if let daily = stock.dailyPnl(quote: q) {
                                Text(daily >= 0
                                     ? "日+\(String(format: "%.2f", daily))"
                                     :  "日\(String(format: "%.2f", daily))")
                                    .font(.system(size: 10))
                                    .foregroundColor(appState.pnlColor(daily))
                            }
                            if let pnl = stock.pnl(quote: q) {
                                Text(pnl >= 0
                                     ? "浮+\(String(format: "%.2f", pnl))"
                                     :  "浮\(String(format: "%.2f", pnl))")
                                    .font(.system(size: 10))
                                    .foregroundColor(appState.pnlColor(pnl))
                            }
                        }
                    }
                }
            } else {
                Text("--")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}
