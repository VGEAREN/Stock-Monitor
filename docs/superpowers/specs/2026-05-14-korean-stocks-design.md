# 韩股接入设计稿

- **日期**：2026-05-14
- **范围**：Stockbar 新增韩股（KOSPI + KOSDAQ）完整支持：实时报价、分时图、KRW 货币换算、搜索、状态栏显示
- **方案**：Yahoo Finance 单一数据源

---

## 1. 背景

Stockbar 当前支持 A股（沪/深/北）、港股、美股，数据来自新浪 / 腾讯 / Pyth / Yahoo（仅美股分时）。用户希望增加韩股。

**前期调研**（2026-05-14）：

- 新浪 `hq.sinajs.cn` 韩股代码返回空（测试 `krx005930`、`kr005930` 均空）
- 腾讯 `qt.gtimg.cn` 韩股代码返回 `v_pv_none_match`
- **Yahoo Finance** 韩股完整支持：`005930.KS` 返回 KRW 价格、KST 时区、`hasPrePostMarketData: false`

结论：必须新增数据源，选 Yahoo（项目已用 Yahoo 抓美股分时，依赖与请求模式已存在）。

---

## 2. 设计目标

1. KOSPI（`.KS`）和 KOSDAQ（`.KQ`）实时报价
2. 分时图（KST 09:00–15:30，390 个分钟点）
3. KRW 货币换算到 CNY/HKD/USD，反向亦可
4. 股票搜索（支持英文 / 韩文 / 代码，不支持中文公司名）
5. 与现有 A股/港股/美股相同的 UI / 状态栏 / 菜单交互
6. 不引入新的崩溃路径，韩股网络失败不影响其它市场

**非目标**：

- 韩股 ETF / 期权 / 期货
- 中文公司名搜索（如"三星"映射到 005930.KS）
- 实时性优化（Yahoo 偶有 1–15 分钟延迟，本期不引入 Naver 抓取等本土源）

---

## 3. 架构与数据流

### 3.1 数据源拓扑

| 用途 | 接口 | 备注 |
|------|------|------|
| 实时报价 | `query1.finance.yahoo.com/v8/finance/chart/<symbol>?interval=1m&range=1d` | **每只股票一次请求并发**（v7 batch quote 已被 Yahoo 401 封禁，必须走 v8）；与 ChartService 美股复用同一端点 |
| 分时数据 | `query1.finance.yahoo.com/v8/finance/chart/<symbol>?interval=1m&range=1d` | 复用现有 `ChartService` 美股代码路径 |
| 股票搜索 | `query1.finance.yahoo.com/v1/finance/search?q=<query>&quotesCount=10` | 仅韩股使用 Yahoo 搜索 |
| KRW 汇率 | `hq.sinajs.cn/list=fx_susdkrw` | 新浪外汇，并入现有外汇批量请求 |

### 3.2 刷新链路

`AppState.refresh()` 当前并行四条支路：A股/港股（新浪+腾讯）、美股（新浪）、美股夜盘（Pyth）、外汇（新浪）。

**新增第五条**：韩股（Yahoo Quote）。任一支路失败不阻塞其它。

```swift
async let aQuotes  = …
async let hkQuotes = …
async let usQuotes = …
async let usOvernight = …
async let krQuotes = stocks.contains { $0.id.hasPrefix("kr_") }
    ? dataService.fetchKoreanQuotes(ids: krIds)
    : [:]
async let fx = currencyService.fetchRates()  // 增加 fx_susdkrw
```

### 3.3 与现有市场的关键差异

- 韩股**无盘前 / 盘后 / 夜盘**（Yahoo `hasPrePostMarketData: false`），单一交易时段
- 时区 KST 固定 UTC+9，**无夏令时**，比美股 ET 简单
- Yahoo `regularMarketPrice` 即唯一价格字段，无需新浪 field 21/22/23 这套盘外字段
- 报价响应是 JSON，无 GBK 解码问题

---

## 4. 数据模型与 ID 格式

### 4.1 Stock 模型

不增字段。`Stock.market` 当前是 `String`，新增取值 `"韩股"`。`market` 通过 ID 前缀解析推断：

| 市场 | ID 前缀 | 当前 |
|------|---------|------|
| 沪 / 深 / 北 | `sh` / `sz` / `bj` | 已有 |
| 港股 | `hk` | 已有 |
| 美股 | `usr_` | 已有 |
| **韩股** | `kr_` | **新增** |

### 4.2 ID 格式

| 交易所 | ID 格式 | 示例 | Yahoo symbol |
|--------|---------|------|--------------|
| KOSPI | `kr_<6位代码>.ks` | `kr_005930.ks`（三星电子）| `005930.KS` |
| KOSDAQ | `kr_<6位代码>.kq` | `kr_035720.kq`（Kakao） | `035720.KQ` |

**选择带后缀的理由**：韩国 6 位代码在 KOSPI 与 KOSDAQ 间历史上有过迁市重叠；Yahoo 调用必须带后缀。把后缀做进 ID 比另存映射表稳。

### 4.3 转换函数

```swift
// kr_005930.ks → 005930.KS
func krIDToYahooSymbol(_ id: String) -> String? {
    guard id.hasPrefix("kr_") else { return nil }
    return String(id.dropFirst(3)).uppercased()
}

// 005930.KS → kr_005930.ks
func yahooSymbolToKrID(_ symbol: String) -> String {
    return "kr_" + symbol.lowercased()
}
```

### 4.4 持久化兼容

`Stock` 是 Codable，`market` 是 String → 不破坏旧 `stocks.json`。`AppSettings` 加 `usdToKrw` 字段（`decodeIfPresent`），旧设置文件可直接加载。

---

## 5. 服务层

### 5.1 DataService

新增 `fetchKoreanQuotes(ids: [String]) async throws -> [String: Quote]`：

1. 把 `kr_005930.ks` 一批转成 `005930.KS` 等 Yahoo symbol
2. 用 `withTaskGroup` 并发请求 Yahoo `/v8/finance/chart/<symbol>?interval=1m&range=1d`，每只一次 HTTP；UA `Mozilla/5.0`（与 ChartService 美股调用一致）
3. 从响应 `chart.result[0].meta` 中解析：
   - `regularMarketPrice` → `Quote.price`
   - `chartPreviousClose`（fallback `previousClose`）→ 昨收，由此推 `change` 与 `changePercent`
   - 不使用 `regularMarketDayHigh`/`Low`（分时图打开时自己从点位算）
4. 返回 `[id: Quote]`，缺字段或单条解析失败跳过该条，不影响整批

**理由**：Yahoo v7 batch quote 端点 2024 起对未带 crumb token 的调用返回 HTTP 401，无法直接使用。v8 chart 端点公开可调，且响应 meta 即含报价所需字段。每只股票一次 HTTP 听起来重，但单次响应 ~30KB，对常规 <30 支韩股的 watchlist 完全够用，且并发执行不阻塞其它市场。

### 5.2 ChartService

新增 `fetchKoreanChart(id:) async throws -> [ChartPoint]`：

- 转 symbol 后调用现有 Yahoo `/v8/finance/chart` 逻辑
- x 轴以 KST 09:00 为 `index=0`，每分钟 +1，覆盖到 15:30（共 390 个 index：`[0, 389]`，与美股 09:30–16:00 同为 6.5 小时 / 390 点的现有约定一致）
- 背景色单一（同美股盘中 teal），无盘前 / 盘后分段
- `StockChartView` 按 `Stock.market == "韩股"` 分支选 x 轴标签 "09:00 / 12:00 / 15:30"

### 5.3 CurrencyService

`ExchangeRates` 加 `usdToKrw: Double`。

`fx_susdkrw` 加进新浪外汇批量请求 URL：
```
hq.sinajs.cn/list=fx_susdcny,fx_susdhkd,fx_susdkrw
```

`convert(amount:from:to:)` 扩到四币种 CNY / HKD / USD / KRW：
- `krwToUsd = 1 / usdToKrw`
- `krwToCny = (1 / usdToKrw) * usdToCny`
- `krwToHkd = (1 / usdToKrw) * usdToHkd`
- 反向同理

兜底机制：`ExchangeRates` 中 `usdToKrw` 的**初始默认值** = `1380.0`（2026 年初均值）。首次拉取成功后覆盖；拉取失败保留当前值（可能是默认值，也可能是上次成功值）。`convert()` 始终不需要判 0。拉取失败时日志 `warn`。

### 5.4 搜索

新增 `searchKoreanStock(query: String) async throws -> [SearchResult]`：

- 调 Yahoo `/v1/finance/search?q=<query>&quotesCount=10`
- 过滤 `quoteType == "EQUITY"` 且 exchange ∈ `{ "KSC" (KOSPI), "KOE" (KOSDAQ) }`（实测 2026-05-14）；symbol 后缀按 `.KS` / `.KQ` 区分
- 返回字段：`symbol` / `shortname` / `longname` / `exchange`
- 调用方根据 exchange 拼 `kr_<code>.ks` 或 `kr_<code>.kq`

支持查询：英文（`samsung`）、韩文（`삼성`）、代码（`005930`）。中文（`三星`）不支持，UI 文案提示。

A股 / 港股 / 美股搜索仍走腾讯 / 新浪，不动。

---

## 6. UI

### 6.1 StockGroupView

市场分组顺序：A股 → 港股 → 美股 → **韩股**（新，末位）。`marketOrder` 排序函数加一项。

### 6.2 添加股票面板

市场选择器加"韩股"。选中后：

- 搜索框 placeholder：`005930 / Samsung / 삼성`
- 结果列表展示：`代码 | 公司名 | 交易所(KOSPI/KOSDAQ)`
- 中文不命中时显示提示：「Yahoo 搜索不支持中文公司名，请试英文或代码」

### 6.3 StockRowView

不改。韩股复用美股的 `现价 / 涨跌% / 涨跌额 / 浮盈亏` 布局。**不显示盘外角标**（前缀 `kr_` 直接绕过现有 `usr_` 盘外判断逻辑）。

### 6.4 SettingsView

`displayCurrency` 选项从 CNY/HKD/USD 扩到 **CNY/HKD/USD/KRW**。状态栏 picker 与设置面板下拉同步加 KRW。

### 6.5 MenuBarLabel

`statusBarStockId == "kr_005930.ks"` 时显示对应韩股，与 A股/港股/美股展示逻辑一致。

---

## 7. 刷新调度与交易时段

### 7.1 koreanMarketSession()

新增 `AppState.koreanMarketSession() -> String?`：

```swift
// KST = UTC+9（固定无夏令时）
// 输入 now: Date
// 返回 "盘中" 或 nil（非交易时段 / 周末）
func koreanMarketSession(_ now: Date = Date()) -> String? {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let comps = cal.dateComponents([.weekday, .hour, .minute], from: now)
    guard let wd = comps.weekday, wd >= 2 && wd <= 6 else { return nil } // 周一-五
    let h = comps.hour ?? 0, m = comps.minute ?? 0
    let t = h * 60 + m
    if t >= 9 * 60 && t <= 15 * 60 + 30 { return "盘中" }
    return nil
}
```

### 7.2 北京时间对照

| KST | 北京时间 |
|-----|---------|
| 09:00–15:30 | 08:00–14:30 |

### 7.3 RefreshScheduler.isTradingHour()

加入韩股判断：北京时间工作日 08:00–14:30 视为韩股交易时段。

刷新频率沿用现有 `refreshInterval` 设置；非交易时段降频走现有逻辑。周末韩股不刷新（与其它市场一致）。

---

## 8. 错误处理

| 场景 | 处理 |
|------|------|
| Yahoo Quote 整体失败 | 保留上次 quotes，列表显示上次价格 + 灰色"过期"标记；日志 `error` |
| 单条 ID 不存在 | Yahoo 返回 `regularMarketPrice == nil`，跳过该条 |
| KRW 汇率拉取失败 | 保留上次 `usdToKrw`；首次启动失败用硬编码 `1380.0`，日志 `warn` |
| Yahoo 风控 403/429 | 捕获，本轮跳过；下一轮调度自然恢复 |
| JSON 解码失败 | 单条跳过，不让整批崩；`decodeIfPresent` |
| 搜索接口失败 | UI 显示"搜索失败，请重试"；不抛错到上层 |

---

## 9. 测试

### 9.1 单元测试（StockMonitorTests/）

| Suite | 范围 |
|------|------|
| `KoreanStockIDTests` | `krIDToYahooSymbol` / `yahooSymbolToKrID` 正反转换；边界：空串、错前缀、大小写 |
| `KoreanQuoteParseTests` | Yahoo v8 chart JSON fixture（meta 字段）：正常 KOSPI、正常 KOSDAQ、`regularMarketPrice == null`、缺 `chartPreviousClose`、HTTP 错误 |
| `KoreanMarketSessionTests` | 边界：09:00 / 09:01 / 15:29 / 15:30 / 15:31 / 周六 / 周日 / 跨年元旦 |
| `CurrencyKRWConversionTests` | KRW ↔ CNY/USD/HKD 双向；`usdToKrw == 0` 时走 fallback 不崩 |
| `KoreanChartParseTests` | Yahoo chart fixture：390 点序列、x 轴 index 计算（09:00→0，15:29→389）、缺失点位 |

所有 fixture 放 `StockMonitorTests/Fixtures/Korea/`。

### 9.2 不做的测试

- 端到端打通 Yahoo 的网络测试（脆弱、Yahoo 风控）
- UI snapshot（项目目前无 snapshot 基础设施）

### 9.3 手动回归清单

实施完成后必须人工跑一遍：

1. 添加 `005930.KS`（三星电子）→ 看到 KRW 实时价
2. 添加 `035720.KQ`（Kakao）→ KOSDAQ 分组正确
3. 设置 `displayCurrency = CNY` → 持仓盈亏数字合理（约 ÷ 200）
4. 韩股收盘后开 app → 显示收盘价，无报错
5. KST 09:00–15:30 期间开 app → 实时价更新正常
6. 状态栏选韩股 ID → 菜单栏正确显示
7. 打开分时图 → 390 点连续、x 轴标 09:00/12:00/15:30
8. 中文搜索"三星" → UI 提示不支持，建议改英文 / 代码
9. 拔网 / 弱网 → 上次价格保留，无崩溃

---

## 10. 已知风险

| 风险 | 缓解 |
|------|------|
| Yahoo 风控 / 改版 | UA 头与现有美股一致；失败优雅降级；预留 `Naver` 后备方案做日后扩展 |
| Yahoo 实时性 1–15 分钟延迟 | 文档说明 ; 用户可观察实际表现 ; 必要时再引入 Naver |
| 6 位代码 KOSPI/KOSDAQ 重叠 | ID 强制带 `.ks`/`.kq` 后缀 |
| 中文搜索缺失 | UI 提示 + 直接支持代码 / 英文 / 韩文 |
| `fx_susdkrw` 新浪外汇 | **已实测可用**（2026-05-14 返回 1490.9）|
| Yahoo 风控（v8 chart 偶发 429）| 单条失败保留上次价，不重试本轮；下一轮调度自然恢复 |

---

## 11. 版本号

预计发布版本 `v1.3.0`（KOSPI/KOSDAQ + KRW 是较大功能，跳次版本号）。
