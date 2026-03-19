import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            if let stock = appState.statusBarStock,
               let quote = appState.statusBarQuote {
                Text(quote.formattedPrice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(appState.quoteColor(for: quote))
                Text(quote.formattedPercent)
                    .font(.system(size: 11))
                    .foregroundColor(appState.quoteColor(for: quote))
                if appState.hasPnLData, appState.config.statusBarPnL != .none {
                    Text("|")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    pnlLabels
                }
                if appState.hasError {
                    Text("⚠").font(.system(size: 11)).foregroundColor(.yellow)
                }
            }
        }
    }

    @ViewBuilder
    private var pnlLabels: some View {
        let mode = appState.config.statusBarPnL
        if mode == .daily || mode == .both {
            let daily = appState.totalDailyPnL
            Text(daily >= 0
                 ? "日+\(String(format: "%.0f", daily))"
                 :  "日\(String(format: "%.0f", daily))")
                .font(.system(size: 11))
                .foregroundColor(appState.pnlColor(daily))
        }
        if mode == .total || mode == .both {
            let pnl = appState.totalPnL
            Text(pnl >= 0
                 ? "浮+\(String(format: "%.0f", pnl))"
                 :  "浮\(String(format: "%.0f", pnl))")
                .font(.system(size: 11))
                .foregroundColor(appState.pnlColor(pnl))
        }
    }
}
