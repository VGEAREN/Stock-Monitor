import SwiftUI
import Charts

struct StockChartView: View {
    let stock: Stock
    let onClose: () -> Void
    @EnvironmentObject var appState: AppState

    @State private var points: [MinutePoint] = []
    @State private var preClose: Double = 0
    @State private var isLoading = true
    @State private var loadFailed = false

    private var quote: Quote? { appState.quotes[stock.id] }

    // MARK: - 全天 x 轴范围（按市场）
    // A股：09:30-11:30 + 13:00-15:00 = 240 分钟
    // 港股：09:30-12:00 + 13:00-16:00 = 330 分钟
    // 美股：04:00-20:00 = 960 分钟（含盘前+正常+盘后）
    private var fullDayRange: ClosedRange<Int> {
        switch stock.market {
        case .aStock:  return 0...239
        case .hkStock: return 0...329
        case .usStock: return 0...959
        }
    }

    // 对应各市场的时间标签（index → 时间字符串）
    private var xAxisLabels: [(Int, String)] {
        switch stock.market {
        case .aStock:
            return [(0, "09:30"), (60, "10:30"), (120, "13:00"), (180, "14:00"), (239, "15:00")]
        case .hkStock:
            return [(0, "09:30"), (75, "10:45"), (150, "13:00"), (240, "15:00"), (329, "16:00")]
        case .usStock:
            // 基准 04:00 ET；330=09:30；720=16:00；959=19:59
            return [(0, "04:00"), (330, "09:30"), (570, "13:30"), (720, "16:00"), (959, "20:00")]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            chartAreaView
                .frame(height: 200)
            if !isLoading && !loadFailed && !points.isEmpty {
                statsRow
            }
        }
        .task { await load() }
    }

    // MARK: - 顶部信息栏

    private var headerView: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(stock.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(stock.id)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let q = quote {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(q.formattedPrice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(appState.quoteColor(for: q))
                    Text(q.formattedPercent)
                        .font(.system(size: 10))
                        .foregroundColor(appState.quoteColor(for: q))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - 图表区域

    @ViewBuilder
    private var chartAreaView: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed || points.isEmpty {
            Text("暂无分时数据")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            lineChart
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    // 美股时段定义：x 轴 index（基准 04:00 ET，每分钟 +1）
    private let usSessions: [(name: String, start: Int, end: Int, color: Color)] = [
        ("盘前", 0,   329, Color.indigo),
        ("盘中", 330, 719, Color.teal),
        ("盘后", 720, 959, Color.orange),
    ]

    private var lineChart: some View {
        let prices = points.map(\.price)
        let minP = prices.min() ?? preClose
        let maxP = prices.max() ?? preClose
        let maxDev = max(abs(maxP - preClose), abs(preClose - minP), preClose * 0.005)
        let yMin = preClose - maxDev * 1.15
        let yMax = preClose + maxDev * 1.15

        let lastPrice = prices.last ?? preClose
        let lineColor: Color = lastPrice >= preClose
            ? Color(appState.config.upColorName)
            : Color(appState.config.downColorName)

        let labelPositions = xAxisLabels.map(\.0)
        let isUS = stock.market == .usStock
        let labelY = yMin + (yMax - yMin) * 0.88

        return Chart {
            // 美股时段背景色块
            if isUS {
                ForEach(usSessions, id: \.name) { s in
                    RectangleMark(
                        xStart: .value("xs", s.start),
                        xEnd:   .value("xe", s.end),
                        yStart: .value("ys", yMin),
                        yEnd:   .value("ye", yMax)
                    )
                    .foregroundStyle(s.color.opacity(0.07))
                }
                // 美股时段文字标注
                ForEach(usSessions, id: \.name) { s in
                    PointMark(
                        x: .value("t", (s.start + s.end) / 2),
                        y: .value("price", labelY)
                    )
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        Text(s.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(s.color.opacity(0.65))
                    }
                }
            }

            // 昨收参考线
            RuleMark(y: .value("昨收", preClose))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                .foregroundStyle(Color.secondary.opacity(0.5))

            // 价格折线
            ForEach(points) { p in
                LineMark(
                    x: .value("t", p.id),
                    y: .value("price", p.price)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            // 面积填充
            ForEach(points) { p in
                AreaMark(
                    x: .value("t", p.id),
                    yStart: .value("base", yMin),
                    yEnd: .value("price", p.price)
                )
                .foregroundStyle(lineColor.opacity(0.12))
            }
        }
        .chartXScale(domain: fullDayRange)
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: labelPositions) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let i = value.as(Int.self),
                       let label = xAxisLabels.first(where: { $0.0 == i })?.1 {
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    // MARK: - 底部统计
    // 今开：分时第一个点的价格；昨收：API 返回的 preclose

    private var statsRow: some View {
        let prices = points.map(\.price)
        return HStack(spacing: 0) {
            statItem(label: "昨收", value: fmt(preClose))
            Spacer()
            statItem(label: "今开", value: fmt(points.first?.price ?? 0))
            Spacer()
            statItem(label: "最高", value: fmt(prices.max() ?? 0))
            Spacer()
            statItem(label: "最低", value: fmt(prices.min() ?? 0))
            Spacer()
            statItem(label: "现价", value: fmt(quote?.price ?? 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value).font(.system(size: 10, weight: .medium))
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

    // MARK: - 数据加载

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            let (pts, pc) = try await ChartService.fetchIntraday(stock: stock)
            self.points = pts
            self.preClose = pc > 0 ? pc : (quote?.previousClose ?? 0)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}
