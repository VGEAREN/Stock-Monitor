import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSettings: Bool

    @ObservedObject private var updater = UpdateChecker.shared

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var searchText    = ""
    @State private var searchResults = [SearchResult]()
    @State private var isSearching   = false
    @State private var editingStock: Stock?
    @State private var editCost      = ""
    @State private var editShares    = ""
    @State private var newWatchlistName = ""

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

                // 状态栏显示
                section("状态栏显示") {
                    Picker("", selection: Binding(
                        get: { appState.statusBarStockId },
                        set: { appState.statusBarStockId = $0 }
                    )) {
                        Text("不显示").tag("__none__")
                        Text("日盈亏").tag("__daily_pnl__")
                        Text("总盈亏").tag("__total_pnl__")
                        Text("日盈亏 + 总盈亏").tag("__both_pnl__")
                        Divider()
                        Text("（自动选第一只）").tag("")
                        ForEach(appState.stocks) { s in
                            Text("\(s.name)  \(s.id)").tag(s.id)
                        }
                    }.pickerStyle(.menu)
                }

                // 持仓股分组
                section("持仓股展示") {
                    Toggle("持仓股单独分组置顶", isOn: Binding(
                        get: { appState.config.groupHoldings },
                        set: { appState.config.groupHoldings = $0 }
                    ))
                    .padding(.leading, 8)
                }

                // 观察仓管理
                section("观察仓") {
                    // 当前选择
                    Picker("", selection: Binding(
                        get: { appState.config.activeWatchlistId ?? "__real__" },
                        set: { appState.config.activeWatchlistId = $0 == "__real__" ? nil : $0 }
                    )) {
                        Text("真实持仓").tag("__real__")
                        ForEach(appState.watchlists) { wl in
                            Text(wl.name).tag(wl.id)
                        }
                    }.pickerStyle(.menu)

                    // 新建
                    HStack(spacing: 6) {
                        TextField("新观察仓名称", text: $newWatchlistName)
                            .textFieldStyle(.roundedBorder)
                        Button("新建") {
                            let name = newWatchlistName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            appState.watchlists.append(Watchlist(name: name))
                            newWatchlistName = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.leading, 8)

                    // 列表（删除）
                    if !appState.watchlists.isEmpty {
                        ForEach(appState.watchlists) { wl in
                            HStack {
                                Text(wl.name).font(.system(size: 12))
                                Spacer()
                                if appState.config.activeWatchlistId == wl.id {
                                    Text("当前").font(.caption).foregroundColor(.accentColor)
                                }
                                Button {
                                    appState.watchlists.removeAll { $0.id == wl.id }
                                    if appState.config.activeWatchlistId == wl.id {
                                        appState.config.activeWatchlistId = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // 排序规则
                section("排序规则") {
                    Picker("", selection: Binding(
                        get: { appState.config.sortRule },
                        set: { appState.config.sortRule = $0 }
                    )) {
                        ForEach(SortRule.allCases, id: \.rawValue) { rule in
                            Text(rule.displayName).tag(rule)
                        }
                    }.pickerStyle(.segmented)
                }

                // 美股排序价格
                section("美股排序价格") {
                    Picker("", selection: Binding(
                        get: { appState.config.usPriceMode },
                        set: { appState.config.usPriceMode = $0 }
                    )) {
                        ForEach(USPriceMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }.pickerStyle(.segmented)
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
                            LaunchAtLogin.setEnabled(enabled)
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                }

                // 关于 & 更新
                section("关于") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stockbar")
                                .font(.system(size: 12, weight: .medium))
                            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if updater.isBusy {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.6)
                                Text(updater.status)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if !updater.status.isEmpty {
                            Text(updater.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Button("检查更新") {
                                updater.checkAndUpdate()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                // 添加股票
                section("添加股票") {
                    HStack {
                        TextField("代码 / 名称 / Samsung / 005930.ks", text: $searchText)
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

                // 已有股票：设置了持仓的排在前面，未设置持仓的在后
                if !appState.stocks.isEmpty {
                    section("我的股票") {
                        ForEach(sortedStocksForSettings) { s in stockRow(s) }
                    }
                }
                } // end else
            }
            .padding(8)
        }
        .scrollIndicators(.never)
        // 高度与列表模式（ProfitSummary + stockListView maxHeight 520 + Toolbar 等）相当，
        // 避免切换 list↔settings 时 NSPanel 大小不一致导致下方空白。
        .frame(width: 284, height: 620)
    }

    // MARK: - 排序辅助

    /// 设置页"我的股票"排序：有持仓（成本 + 股数都设置了）的排在前面，
    /// 其它的排在后面；组内保持原顺序。
    private var sortedStocksForSettings: [Stock] {
        let withHolding = appState.stocks.filter {
            appState.effectiveCostPrice(for: $0) != nil
                && appState.effectiveShares(for: $0) != nil
        }
        let withoutHolding = appState.stocks.filter {
            appState.effectiveCostPrice(for: $0) == nil
                || appState.effectiveShares(for: $0) == nil
        }
        return withHolding + withoutHolding
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
                if let c = appState.effectiveCostPrice(for: stock),
                   let sh = appState.effectiveShares(for: stock) {
                    Text("成本 \(String(format: "%.3f", c)) × \(String(format: "%.0f", sh)) 股")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("未设置持仓").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                editingStock = stock
                editCost     = appState.effectiveCostPrice(for: stock).map { String($0) } ?? ""
                editShares   = appState.effectiveShares(for: stock).map { String(Int($0)) } ?? ""
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("编辑 \(stock.name)").font(.headline)
                    Text(appState.activeWatchlistName)
                        .font(.caption).foregroundColor(.accentColor)
                }
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
                    let cost   = Double(editCost)
                    let shares = Double(editShares)
                    if let wlId = appState.config.activeWatchlistId,
                       let wlIdx = appState.watchlists.firstIndex(where: { $0.id == wlId }) {
                        // 写入观察仓
                        if let c = cost, let s = shares {
                            appState.watchlists[wlIdx].entries[stock.id] = WatchlistEntry(costPrice: c, holdingShares: s)
                        } else {
                            appState.watchlists[wlIdx].entries.removeValue(forKey: stock.id)
                        }
                    } else {
                        // 写入真实持仓
                        if let idx = appState.stocks.firstIndex(where: { $0.id == stock.id }) {
                            var updated = appState.stocks
                            updated[idx].costPrice     = cost
                            updated[idx].holdingShares = shares
                            appState.stocks = updated
                        }
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

    /// 主搜索：腾讯（A股/港股/美股）和 Yahoo（韩股）并行，结果合并。
    /// 用户输入 6 位数字 / 英文 / 韩文 时，A股 和 同号韩股 会同时显示。
    private func fetchSuggestions(_ keyword: String) async -> [SearchResult] {
        async let tencent = tencentSearch(keyword)
        async let korean  = shouldQueryKorean(keyword)
                            ? yahooKoreanSearch(keyword)
                            : [SearchResult]()
        let (t, k) = await (tencent, korean)

        // 合并：先腾讯结果（保持原有排序），再 Yahoo 韩股结果，去重
        var seen = Set<String>()
        var merged: [SearchResult] = []
        for r in t + k where !seen.contains(r.id) {
            seen.insert(r.id)
            merged.append(r)
        }

        if merged.isEmpty {
            // 全空：新浪兜底（覆盖某些美股 ticker）→ 直接代码兜底
            let sina = await sinaFetchSuggestions(keyword)
            return sina.isEmpty ? directResult(for: keyword) : sina
        }
        return merged
    }

    /// 腾讯搜索（A股/港股/美股），失败返回空。
    private func tencentSearch(_ keyword: String) async -> [SearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://proxy.finance.qq.com/ifzqgtimg/appstock/smartbox/search/get?q=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let stocks = dataObj["stock"] as? [[String]] else {
            return []
        }
        return stocks.compactMap { item -> SearchResult? in
            guard item.count >= 3 else { return nil }
            let mkt  = item[0].lowercased()
            let code = item[1].lowercased()
            let name = item[2]
            switch mkt {
            case "sh", "sz", "bj": return SearchResult(id: "\(mkt)\(code)", name: name, market: .aStock)
            case "hk":             return SearchResult(id: "hk\(code)",      name: name, market: .hkStock)
            case "us":
                let parts = code.components(separatedBy: ".")
                let ticker = (parts.count > 1 ? parts.dropLast().joined(separator: ".") : code).lowercased()
                return SearchResult(id: "usr_\(ticker)", name: name, market: .usStock)
            default: return nil
            }
        }
    }

    /// 是否同时跑一次 Yahoo 韩股搜索：
    /// - 含 Hangul / 带 .ks/.kq 后缀 / kr_ 前缀 → 一定
    /// - 6 位纯数字（韩股代码长度）→ 一定（即便腾讯能搜到 A 股，同号韩股也想看到）
    /// - 纯字母长度 ≥ 3 → 一定（公司名）
    /// 其它（短数字、特殊字符）跳过 Yahoo，省一次请求
    private func shouldQueryKorean(_ s: String) -> Bool {
        let k = s.trimmingCharacters(in: .whitespaces)
        let lower = k.lowercased()
        if lower.hasSuffix(".ks") || lower.hasSuffix(".kq") { return true }
        if lower.hasPrefix("kr_") { return true }
        if k.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7AF }) { return true }
        if k.count == 6, k.allSatisfy(\.isNumber) { return true }
        if k.count >= 3, k.allSatisfy({ $0.isLetter }) { return true }
        return false
    }

    /// Yahoo /v1/finance/search — 仅返回韩股（KSC / KOE 两种 exchange）
    private func yahooKoreanSearch(_ keyword: String) async -> [SearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=10") else {
            return []
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = root["quotes"] as? [[String: Any]] else { return [] }
        return quotes.compactMap { q -> SearchResult? in
            guard (q["quoteType"] as? String) == "EQUITY",
                  let symbol = q["symbol"] as? String else { return nil }
            // 韩股 symbol 以 .KS / .KQ 结尾
            let upper = symbol.uppercased()
            guard upper.hasSuffix(".KS") || upper.hasSuffix(".KQ") else { return nil }
            let id = KoreanStockID.fromYahooSymbol(symbol)
            let name = (q["shortname"] as? String) ?? (q["longname"] as? String) ?? symbol
            return SearchResult(id: id, name: name, market: .krStock)
        }
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
        // 韩股：kr_005930.ks / 005930.ks / 005930.kq 形式
        if k.hasPrefix("kr_") {
            return [SearchResult(id: k, name: k.uppercased(), market: .krStock)]
        }
        if k.hasSuffix(".ks") || k.hasSuffix(".kq") {
            return [SearchResult(id: "kr_\(k)", name: k.uppercased(), market: .krStock)]
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
