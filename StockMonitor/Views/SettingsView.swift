import SwiftUI
import ServiceManagement

@MainActor
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSettings: Bool

    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var searchText    = ""
    @State private var searchResults = [SearchResult]()
    @State private var isSearching   = false
    @State private var editingStock: Stock?
    @State private var editCost      = ""
    @State private var editShares    = ""

    struct SearchResult: Identifiable {
        let id: String; let name: String; let market: Market
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = editingStock {
                    inlineEditView(s)
                } else {
                // 标题栏
                HStack {
                    Button { showSettings = false } label: {
                        Image(systemName: "chevron.left")
                    }.buttonStyle(.plain)
                    Text("设置").font(.headline)
                }

                Divider()

                // 状态栏显示股票
                section("状态栏显示") {
                    Picker("", selection: Binding(
                        get: { appState.statusBarStockId },
                        set: { appState.statusBarStockId = $0 }
                    )) {
                        Text("不显示").tag("__none__")
                        Text("（自动选第一只）").tag("")
                        ForEach(appState.stocks) { s in
                            Text("\(s.name)  \(s.id)").tag(s.id)
                        }
                    }.pickerStyle(.menu)
                }

                // 刷新间隔
                section("刷新间隔") {
                    Picker("", selection: Binding(
                        get: { appState.refreshInterval },
                        set: { appState.refreshInterval = $0; appState.restartScheduler() }
                    )) {
                        ForEach(AppSettings.validRefreshIntervals, id: \.self) { i in
                            Text("\(i) 秒").tag(i)
                        }
                    }.pickerStyle(.segmented)
                }

                // 涨跌颜色
                section("涨跌颜色") {
                    HStack(spacing: 8) {
                        ForEach(ColorTheme.allCases, id: \.rawValue) { scheme in
                            colorCard(scheme)
                        }
                    }
                }

                // 持仓汇总货币
                section("持仓汇总货币") {
                    Picker("", selection: Binding(
                        get: { appState.displayCurrency },
                        set: { appState.displayCurrency = $0 }
                    )) {
                        ForEach(DisplayCurrency.allCases, id: \.rawValue) { c in
                            Text(c.displayName).tag(c)
                        }
                    }.pickerStyle(.segmented)
                }

                // 开机启动
                section("开机启动") {
                    Toggle("登录后自动启动", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { enabled in
                            if enabled {
                                try? SMAppService.mainApp.register()
                            } else {
                                try? SMAppService.mainApp.unregister()
                            }
                        }
                }

                // 添加股票
                section("添加股票") {
                    HStack {
                        TextField("代码或名称（回车搜索）", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { search() }
                        if isSearching {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Button("搜索") { search() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                    if !searchResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(searchResults) { r in
                                Button { addStock(r) } label: {
                                    HStack {
                                        Text(r.name).font(.system(size: 12))
                                        Spacer()
                                        Text(r.id).font(.caption).foregroundColor(.secondary)
                                        Text(r.market.rawValue).font(.caption).foregroundColor(.accentColor)
                                    }.padding(.vertical, 4)
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }

                // 已有股票
                if !appState.stocks.isEmpty {
                    section("我的股票") {
                        ForEach(appState.stocks) { s in stockRow(s) }
                    }
                }
                } // end else
            }
            .padding(8)
        }
        .frame(width: 284, height: 480)
    }

    // MARK: - 子视图

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func colorCard(_ scheme: ColorTheme) -> some View {
        let selected = appState.colorScheme == scheme
        Button { appState.colorScheme = scheme } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("涨").foregroundColor(scheme == .chinese ? .red : .green)
                    Text("跌").foregroundColor(scheme == .chinese ? .green : .red)
                }.font(.system(size: 12, weight: .medium))
                Text(scheme.displayName).font(.caption2).foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.15)
                                  : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func stockRow(_ stock: Stock) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.name).font(.system(size: 12))
                if let c = stock.costPrice, let sh = stock.holdingShares {
                    Text("成本 \(String(format: "%.3f", c)) × \(String(format: "%.0f", sh)) 股")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("未设置持仓").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                editingStock = stock
                editCost     = stock.costPrice.map    { String($0) } ?? ""
                editShares   = stock.holdingShares.map { String(Int($0)) } ?? ""
            } label: { Image(systemName: "pencil").font(.system(size: 11)) }
            .buttonStyle(.plain)

            Button {
                appState.stocks.removeAll { $0.id == stock.id }
                if appState.statusBarStockId == stock.id { appState.statusBarStockId = "" }
            } label: { Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.red) }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func inlineEditView(_ stock: Stock) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { editingStock = nil } label: {
                    Image(systemName: "chevron.left")
                }.buttonStyle(.plain)
                Text("编辑 \(stock.name)").font(.headline)
            }
            Divider()
            HStack {
                Text("成本价")
                TextField("如 10.50", text: $editCost).textFieldStyle(.roundedBorder).frame(width: 100)
            }
            HStack {
                Text("持仓股数")
                TextField("如 1000", text: $editShares).textFieldStyle(.roundedBorder).frame(width: 100)
            }
            HStack {
                Button("取消") { editingStock = nil }.buttonStyle(.bordered)
                Button("保存") {
                    if let idx = appState.stocks.firstIndex(where: { $0.id == stock.id }) {
                        var updated = appState.stocks
                        updated[idx].costPrice     = Double(editCost)
                        updated[idx].holdingShares = Double(editShares)
                        appState.stocks = updated
                    }
                    editingStock = nil
                }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 搜索逻辑

    private func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true; searchResults = []
        Task {
            let results = await fetchSuggestions(searchText)
            await MainActor.run { searchResults = results; isSearching = false }
        }
    }

    /// 腾讯代理搜索（JSON，直接返回中文名，A股+港股最可靠）
    private func fetchSuggestions(_ keyword: String) async -> [SearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://proxy.finance.qq.com/ifzqgtimg/appstock/smartbox/search/get?q=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let stocks = dataObj["stock"] as? [[String]] else {
            return await sinaFetchSuggestions(keyword)
        }
        let results = stocks.compactMap { item -> SearchResult? in
            guard item.count >= 3 else { return nil }
            let mkt  = item[0].lowercased()
            let code = item[1].lowercased()
            let name = item[2]
            switch mkt {
            case "sh", "sz", "bj": return SearchResult(id: "\(mkt)\(code)", name: name, market: .aStock)
            case "hk":             return SearchResult(id: "hk\(code)",      name: name, market: .hkStock)
            case "us":
                // Tencent 返回如 "AAPL.O" 或 "BRK.B.N"
                // 去掉末尾交易所后缀（.O/.N/.A），保留股票代码本身，转小写
                let parts = code.components(separatedBy: ".")
                let ticker = (parts.count > 1 ? parts.dropLast().joined(separator: ".") : code).lowercased()
                return SearchResult(id: "usr_\(ticker)", name: name, market: .usStock)
            default: return nil
            }
        }
        return results.isEmpty ? directResult(for: keyword) : results
    }

    /// 新浪 suggest 兜底（主要覆盖美股/期货等腾讯接口不返回的品种）
    private func sinaFetchSuggestions(_ keyword: String) async -> [SearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggest3.sinajs.cn/suggest/type=11,12,13,14&key=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return directResult(for: keyword)
        }
        let body = StringDecoding.decodeGBK(data)
        guard let s = body.range(of: "\""),
              let e = body.lastIndex(of: "\""),
              e > s.upperBound else { return directResult(for: keyword) }
        let results = String(body[body.index(after: s.lowerBound)..<e])
            .components(separatedBy: ";")
            .filter { !$0.isEmpty }
            .compactMap { item -> SearchResult? in
                let p = item.components(separatedBy: ",")
                guard p.count >= 5 else { return nil }
                let market: Market; let id: String
                switch p[0] {
                case "11", "14": market = .aStock;  id = p[3].lowercased()
                case "12":       market = .hkStock; id = "hk" + p[3].lowercased()
                case "13":       market = .usStock; id = p[3].lowercased()
                default: return nil
                }
                return SearchResult(id: id, name: p[4], market: market)
            }
        return results.isEmpty ? directResult(for: keyword) : results
    }

    /// 将纯数字/字母输入当作直接代码（兜底）：6位数→sh，其余→sz
    private func directResult(for keyword: String) -> [SearchResult] {
        let k = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
        // 已有前缀（sh/sz/bj/hk/usr_）直接使用
        if k.hasPrefix("sh") || k.hasPrefix("sz") || k.hasPrefix("bj") {
            let market: Market = k.hasPrefix("hk") ? .hkStock : .aStock
            return [SearchResult(id: k, name: k.uppercased(), market: market)]
        }
        if k.hasPrefix("hk") {
            return [SearchResult(id: k, name: k.uppercased(), market: .hkStock)]
        }
        if k.hasPrefix("usr_") {
            return [SearchResult(id: k, name: k.uppercased(), market: .usStock)]
        }
        // 港股：4-5位纯数字，补齐5位前导零
        if k.allSatisfy(\.isNumber), k.count >= 4, k.count <= 5 {
            let padded = String(repeating: "0", count: 5 - k.count) + k
            return [SearchResult(id: "hk\(padded)", name: k, market: .hkStock)]
        }
        // A股：6位纯数字，0/3开头 → sz（深交所），其余 → sh（沪市）
        if k.allSatisfy(\.isNumber), k.count == 6 {
            let prefix = (k.hasPrefix("0") || k.hasPrefix("3")) ? "sz" : "sh"
            return [SearchResult(id: "\(prefix)\(k)", name: k, market: .aStock)]
        }
        return []
    }

    private func addStock(_ r: SearchResult) {
        guard !appState.stocks.contains(where: { $0.id == r.id }) else { return }
        appState.stocks.append(Stock(id: r.id, name: r.name, market: r.market,
                                     costPrice: nil, holdingShares: nil))
        searchText = ""; searchResults = []
    }
}
