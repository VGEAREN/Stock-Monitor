# 韩股接入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stockbar 新增 KOSPI + KOSDAQ 韩股完整支持：实时报价、分时图、KRW 货币换算、搜索、状态栏。

**Architecture:** Yahoo Finance v8 chart endpoint 同时供应报价（meta 字段）和分时（timestamp/close 数组）；新浪 `fx_susdkrw` 提供 USD/KRW 汇率；搜索走 Yahoo `/v1/finance/search`。`Market` 枚举加 `krStock`，ID 前缀 `kr_<6位代码>.<ks|kq>`。

**Tech Stack:** Swift 5.9 / SwiftUI / Swift Charts / XCTest（与项目其余部分一致）。

**Spec:** `docs/superpowers/specs/2026-05-14-korean-stocks-design.md`

**Test invocation pattern:**
```bash
cd StockMonitor/StockMonitor  # project root (contains StockMonitor.xcodeproj)
xcodebuild test \
  -project StockMonitor.xcodeproj \
  -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/<TestClass>/<testMethod> \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -30
```

**Adding new files to Xcode project:**
After creating each new `.swift` source or test file, register it with the project file:
```bash
cd StockMonitor/StockMonitor
ruby add_files.rb StockMonitor/<path>.swift            # for app target
ruby add_files.rb StockMonitorTests/<path>.swift       # for test target
```
Module is `Stockbar`, so test files use `@testable import Stockbar`.

---

## File Structure

**New files:**
- `StockMonitor/Utils/KoreanStockID.swift` — ID format helpers (krIDToYahooSymbol, yahooSymbolToKrID, isKoreanID)
- `StockMonitorTests/Utils/KoreanStockIDTests.swift`
- `StockMonitorTests/Services/KoreanQuoteParseTests.swift`
- `StockMonitorTests/Services/KoreanChartParseTests.swift`
- `StockMonitorTests/Services/CurrencyKRWTests.swift`
- `StockMonitorTests/State/KoreanMarketSessionTests.swift`
- `StockMonitorTests/Fixtures/Korea/quote_005930_ks.json` — Yahoo v8 chart response for KOSPI sample
- `StockMonitorTests/Fixtures/Korea/quote_293490_kq.json` — Yahoo v8 chart response for KOSDAQ sample
- `StockMonitorTests/Fixtures/Korea/quote_empty.json` — `regularMarketPrice == null` edge case
- `StockMonitorTests/Fixtures/Korea/chart_005930_ks.json` — 1-minute chart fixture

**Modified files:**
- `StockMonitor/Models/Stock.swift` — `Market` enum: add `krStock`; `Market.from` handles `kr_` prefix
- `StockMonitor/Models/AppSettings.swift` — `DisplayCurrency` adds `krw`
- `StockMonitor/Services/CurrencyService.swift` — `ExchangeRates.usdToKrw` + KRW conversion paths; fetch `fx_susdkrw`
- `StockMonitor/Services/DataService.swift` — new static `fetchKoreanQuotes(ids:) async throws -> [String: Quote]` + `parseKoreanChartMeta(_ data:Data, id:) -> Quote?` helper
- `StockMonitor/Services/ChartService.swift` — new private `fetchKoreanIntraday(stockId:)`; `fetchIntraday` dispatches `.krStock` here
- `StockMonitor/Services/RefreshScheduler.swift` — `isTradingHour` includes KR session window
- `StockMonitor/State/AppState.swift` — `refresh()` adds KR branch; new static `koreanMarketSession() -> String?`
- `StockMonitor/Views/StockChartView.swift` — `fullDayRange` and `xAxisLabels` add `.krStock` case
- `StockMonitor/Views/DropdownView.swift` — market list iteration includes `.krStock`
- `StockMonitor/Views/SettingsView.swift` — search supports KR via Yahoo; search-result Picker iterates over enum cases

---

## Self-Contained Code Reference Bundle

These constants and snippets are referenced by multiple tasks. Read once, then refer to.

**KR session boundaries (KST, no DST):**
- Trading: 09:00–15:30 local (Mon–Fri)
- KST is fixed UTC+9
- In Beijing time (UTC+8): 08:00–14:30

**Stock ID examples:**
- `kr_005930.ks` — Samsung Electronics (KOSPI) → Yahoo symbol `005930.KS`
- `kr_293490.kq` — Pearl Abyss (KOSDAQ) → Yahoo symbol `293490.KQ`
- (Note: Kakao `035720` was originally KOSDAQ but migrated to KOSPI in 2017, so it's now `kr_035720.ks`. Test fixtures use 005930 for KOSPI and 293490 for KOSDAQ to avoid migration confusion.)

**Yahoo v8 chart meta sample (verified 2026-05-14):**
```json
{
  "chart": {
    "result": [{
      "meta": {
        "symbol": "005930.KS",
        "regularMarketPrice": 296750.0,
        "chartPreviousClose": 284000.0,
        "previousClose": 284000.0,
        "currency": "KRW",
        "exchangeName": "KSC",
        "timezone": "KST",
        "gmtoffset": 32400,
        "hasPrePostMarketData": false,
        "regularMarketTime": 1778719736
      },
      "timestamp": [1778695200, 1778695260, ...],
      "indicators": {
        "quote": [{
          "close": [283500.0, 283800.0, ...]
        }]
      }
    }],
    "error": null
  }
}
```

---

## Phase 1: ID Format Helpers

Foundation utilities — every other phase depends on these.

### Task 1: Korean stock ID conversion helpers

**Files:**
- Create: `StockMonitor/Utils/KoreanStockID.swift`
- Create: `StockMonitorTests/Utils/KoreanStockIDTests.swift`

- [ ] **Step 1: Write failing tests**

Create `StockMonitorTests/Utils/KoreanStockIDTests.swift`:

```swift
import XCTest
@testable import Stockbar

final class KoreanStockIDTests: XCTestCase {

    // MARK: - isKoreanID

    func test_isKoreanID_kospi() {
        XCTAssertTrue(KoreanStockID.isKorean("kr_005930.ks"))
    }

    func test_isKoreanID_kosdaq() {
        XCTAssertTrue(KoreanStockID.isKorean("kr_293490.kq"))
    }

    func test_isKoreanID_rejects_other_markets() {
        XCTAssertFalse(KoreanStockID.isKorean("sh600000"))
        XCTAssertFalse(KoreanStockID.isKorean("hk00700"))
        XCTAssertFalse(KoreanStockID.isKorean("usr_aapl"))
    }

    func test_isKoreanID_rejects_empty_and_garbage() {
        XCTAssertFalse(KoreanStockID.isKorean(""))
        XCTAssertFalse(KoreanStockID.isKorean("kr"))
        XCTAssertFalse(KoreanStockID.isKorean("kr_"))
    }

    // MARK: - krIDToYahooSymbol

    func test_krIDToYahooSymbol_kospi() {
        XCTAssertEqual(KoreanStockID.toYahooSymbol("kr_005930.ks"), "005930.KS")
    }

    func test_krIDToYahooSymbol_kosdaq() {
        XCTAssertEqual(KoreanStockID.toYahooSymbol("kr_293490.kq"), "293490.KQ")
    }

    func test_krIDToYahooSymbol_handles_mixed_case_input() {
        XCTAssertEqual(KoreanStockID.toYahooSymbol("kr_005930.KS"), "005930.KS")
        XCTAssertEqual(KoreanStockID.toYahooSymbol("KR_005930.ks"), "005930.KS")
    }

    func test_krIDToYahooSymbol_rejects_non_korean() {
        XCTAssertNil(KoreanStockID.toYahooSymbol("sh600000"))
        XCTAssertNil(KoreanStockID.toYahooSymbol(""))
    }

    // MARK: - yahooSymbolToKrID

    func test_yahooSymbolToKrID_kospi() {
        XCTAssertEqual(KoreanStockID.fromYahooSymbol("005930.KS"), "kr_005930.ks")
    }

    func test_yahooSymbolToKrID_kosdaq() {
        XCTAssertEqual(KoreanStockID.fromYahooSymbol("293490.KQ"), "kr_293490.kq")
    }

    func test_yahooSymbolToKrID_handles_lowercase_input() {
        XCTAssertEqual(KoreanStockID.fromYahooSymbol("005930.ks"), "kr_005930.ks")
    }
}
```

- [ ] **Step 2: Register test file with Xcode project**

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb StockMonitorTests/Utils/KoreanStockIDTests.swift
```
Expected: `Added: StockMonitorTests/Utils/KoreanStockIDTests.swift` (or `Already in project: ...`)

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanStockIDTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: build FAIL with `cannot find 'KoreanStockID' in scope`

- [ ] **Step 4: Create `StockMonitor/Utils/KoreanStockID.swift`**

```swift
import Foundation

/// Helpers for converting between Stockbar's internal Korean stock ID
/// (`kr_<6digit>.ks` for KOSPI, `kr_<6digit>.kq` for KOSDAQ) and Yahoo
/// Finance symbol (`005930.KS`, `293490.KQ`).
enum KoreanStockID {

    /// Stockbar-internal ID prefix for Korean stocks.
    static let prefix = "kr_"

    /// Returns true if `id` looks like a Korean stock ID. Case-insensitive on the prefix.
    static func isKorean(_ id: String) -> Bool {
        let lower = id.lowercased()
        guard lower.hasPrefix(prefix) else { return false }
        // Anything after the prefix must contain at least one character beyond `kr_`
        return lower.count > prefix.count
    }

    /// Convert internal ID → Yahoo symbol. Returns nil for non-Korean IDs.
    /// e.g. `kr_005930.ks` → `005930.KS`
    static func toYahooSymbol(_ id: String) -> String? {
        guard isKorean(id) else { return nil }
        let lower = id.lowercased()
        let suffix = String(lower.dropFirst(prefix.count))
        return suffix.uppercased()
    }

    /// Convert Yahoo symbol → internal ID. Always succeeds.
    /// e.g. `005930.KS` → `kr_005930.ks`
    static func fromYahooSymbol(_ symbol: String) -> String {
        return prefix + symbol.lowercased()
    }
}
```

- [ ] **Step 5: Register source file with Xcode project**

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb StockMonitor/Utils/KoreanStockID.swift
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanStockIDTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: `Test Suite 'KoreanStockIDTests' passed`, 10 tests pass.

- [ ] **Step 7: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Utils/KoreanStockID.swift StockMonitorTests/Utils/KoreanStockIDTests.swift StockMonitor.xcodeproj/project.pbxproj
git commit -m "feat(korea): add KoreanStockID helpers for kr_<code>.ks/kq ↔ Yahoo symbol"
```

---

## Phase 2: Market enum & Stock model

### Task 2: Add `.krStock` market case

**Files:**
- Modify: `StockMonitor/Models/Stock.swift:3-13` — `Market` enum
- Modify: `StockMonitorTests/Models/StockTests.swift` — add KR cases

- [ ] **Step 1: Add failing tests in `StockMonitorTests/Models/StockTests.swift`**

Append the following test methods inside the `StockTests` class (before the closing brace):

```swift
    func test_market_fromCode_krStock_kospi() {
        XCTAssertEqual(Market.from(code: "kr_005930.ks"), .krStock)
    }

    func test_market_fromCode_krStock_kosdaq() {
        XCTAssertEqual(Market.from(code: "kr_293490.kq"), .krStock)
    }

    func test_market_krStock_rawValue() {
        XCTAssertEqual(Market.krStock.rawValue, "韩股")
    }

    func test_market_allCases_includes_kr() {
        XCTAssertTrue(Market.allCases.contains(.krStock))
    }

    func test_stock_codable_roundtrip_kr() throws {
        let stock = Stock(id: "kr_005930.ks", name: "Samsung Electronics", market: .krStock,
                         costPrice: 80000.0, holdingShares: 10)
        let data = try JSONEncoder().encode(stock)
        let decoded = try JSONDecoder().decode(Stock.self, from: data)
        XCTAssertEqual(decoded.id, "kr_005930.ks")
        XCTAssertEqual(decoded.market, .krStock)
        XCTAssertEqual(decoded.costPrice, 80000.0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/StockTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: build FAIL with `type 'Market' has no member 'krStock'`.

- [ ] **Step 3: Modify `StockMonitor/Models/Stock.swift`**

Replace the `Market` enum (lines 3–13) with:

```swift
enum Market: String, Codable, CaseIterable {
    case aStock  = "A股"
    case hkStock = "港股"
    case usStock = "美股"
    case krStock = "韩股"

    static func from(code: String) -> Market {
        if code.hasPrefix("hk")   { return .hkStock }
        if code.hasPrefix("usr_") { return .usStock }
        if code.hasPrefix("kr_")  { return .krStock }
        return .aStock
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/StockTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: all `StockTests` pass (existing + 5 new).

- [ ] **Step 5: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Models/Stock.swift StockMonitorTests/Models/StockTests.swift
git commit -m "feat(korea): add Market.krStock for Korean exchanges"
```

---

## Phase 3: KRW currency & exchange rates

### Task 3: Add `usdToKrw` to ExchangeRates and conversion paths

**Files:**
- Modify: `StockMonitor/Services/CurrencyService.swift:3-26` — `ExchangeRates` struct
- Create: `StockMonitorTests/Services/CurrencyKRWTests.swift`

- [ ] **Step 1: Create test file `StockMonitorTests/Services/CurrencyKRWTests.swift`**

```swift
import XCTest
@testable import Stockbar

final class CurrencyKRWTests: XCTestCase {

    private func rates() -> ExchangeRates {
        var r = ExchangeRates()
        r.usdToCny = 7.28
        r.usdToHkd = 7.78
        r.usdToKrw = 1380.0
        return r
    }

    func test_default_usdToKrw_isFallback() {
        // 默认值是兜底常量 1380，避免 convert 里出现除以 0
        let r = ExchangeRates()
        XCTAssertEqual(r.usdToKrw, 1380.0, accuracy: 0.0001)
    }

    func test_convert_krw_to_cny() {
        // 1,000,000 KRW @ 1380 USD/KRW = 724.64 USD * 7.28 USD/CNY ≈ 5275.36 CNY
        let r = rates()
        let cny = r.convert(1_000_000, from: .krStock, to: .cny)
        XCTAssertEqual(cny, 1_000_000.0 / 1380.0 * 7.28, accuracy: 0.01)
    }

    func test_convert_krw_to_usd() {
        let r = rates()
        let usd = r.convert(1_380_000, from: .krStock, to: .usd)
        XCTAssertEqual(usd, 1000.0, accuracy: 0.001)
    }

    func test_convert_krw_to_hkd() {
        // 1,380,000 KRW = 1000 USD → 7780 HKD
        let r = rates()
        let hkd = r.convert(1_380_000, from: .krStock, to: .hkd)
        XCTAssertEqual(hkd, 1000.0 * 7.78, accuracy: 0.01)
    }

    func test_convert_krw_to_krw_identity() {
        let r = rates()
        XCTAssertEqual(r.convert(123_456, from: .krStock, to: .krw), 123_456.0, accuracy: 0.001)
    }

    func test_convert_cny_to_krw() {
        // CNY → USD → KRW
        let r = rates()
        let krw = r.convert(728.0, from: .aStock, to: .krw)
        // 728 CNY / 7.28 = 100 USD * 1380 = 138_000 KRW
        XCTAssertEqual(krw, 138_000.0, accuracy: 0.1)
    }

    func test_convert_usd_to_krw() {
        let r = rates()
        let krw = r.convert(100.0, from: .usStock, to: .krw)
        XCTAssertEqual(krw, 138_000.0, accuracy: 0.1)
    }

    func test_convert_hkd_to_krw() {
        let r = rates()
        let krw = r.convert(778.0, from: .hkStock, to: .krw)
        // 778 HKD = 100 USD = 138_000 KRW
        XCTAssertEqual(krw, 138_000.0, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Register test file**

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb StockMonitorTests/Services/CurrencyKRWTests.swift
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/CurrencyKRWTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -25
```
Expected: build FAIL with errors like `value of type 'ExchangeRates' has no member 'usdToKrw'`, `'krStock'` not handled in switch.

- [ ] **Step 4: Update `ExchangeRates` struct in `StockMonitor/Services/CurrencyService.swift`**

Replace the entire `ExchangeRates` struct (lines 3–26) with:

```swift
struct ExchangeRates {
    var usdToCny: Double = 7.28      // 默认兜底值
    var usdToHkd: Double = 7.78
    var usdToKrw: Double = 1380.0    // 默认兜底（2026 年初均值）；CurrencyService 拉成功后覆盖

    /// HKD/CNY = USD/CNY ÷ USD/HKD
    var hkdToCny: Double { usdToCny / usdToHkd }
    /// KRW/CNY = USD/CNY ÷ USD/KRW
    var krwToCny: Double { usdToCny / usdToKrw }

    /// 将 amount（native 货币）转换为目标货币
    func convert(_ amount: Double, from market: Market, to currency: DisplayCurrency) -> Double {
        // 先统一转成 CNY
        let inCny: Double
        switch market {
        case .aStock:  inCny = amount
        case .hkStock: inCny = amount * hkdToCny
        case .usStock: inCny = amount * usdToCny
        case .krStock: inCny = amount * krwToCny
        }
        // 再从 CNY 转出去
        switch currency {
        case .cny: return inCny
        case .hkd: return inCny / hkdToCny
        case .usd: return inCny / usdToCny
        case .krw: return inCny / krwToCny
        }
    }
}
```

Note: `DisplayCurrency.krw` is added in Task 4. Both compile together once that task lands. **Do not run tests yet** — wait for Task 4.

- [ ] **Step 5: Commit (deferred — combine with Task 4)**

Skip commit here; tasks 3 + 4 land together for a clean build.

### Task 4: Add `.krw` to DisplayCurrency

**Files:**
- Modify: `StockMonitor/Models/AppSettings.swift:3-23` — `DisplayCurrency` enum

- [ ] **Step 1: Modify `DisplayCurrency` enum**

Replace lines 3–23 of `StockMonitor/Models/AppSettings.swift` with:

```swift
enum DisplayCurrency: String, Codable, CaseIterable {
    case cny = "CNY"
    case hkd = "HKD"
    case usd = "USD"
    case krw = "KRW"

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .hkd: return "HK$"
        case .usd: return "$"
        case .krw: return "₩"
        }
    }

    var displayName: String {
        switch self {
        case .cny: return "人民币 ¥"
        case .hkd: return "港币 HK$"
        case .usd: return "美元 $"
        case .krw: return "韩元 ₩"
        }
    }
}
```

- [ ] **Step 2: Run KRW tests — should now pass**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/CurrencyKRWTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: 8 tests pass.

- [ ] **Step 3: Run full test suite to confirm no regressions**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -30
```
Expected: all tests pass (existing + Phase 1/2/3 new). If `AppSettingsTests` references `DisplayCurrency.allCases.count`, may need adjustment — check before commit.

- [ ] **Step 4: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Services/CurrencyService.swift StockMonitor/Models/AppSettings.swift StockMonitorTests/Services/CurrencyKRWTests.swift StockMonitor.xcodeproj/project.pbxproj
git commit -m "feat(korea): add KRW currency support with ExchangeRates conversions"
```

### Task 5: Fetch `fx_susdkrw` from Sina

**Files:**
- Modify: `StockMonitor/Services/CurrencyService.swift:31-46` — `fetchRates`

- [ ] **Step 1: Update `fetchRates` URL and parsing**

In `StockMonitor/Services/CurrencyService.swift`, replace lines 31–46 with:

```swift
    /// 从新浪财经获取 USD/CNY、USD/HKD、USD/KRW 汇率，失败时返回内置兜底值
    static func fetchRates() async -> ExchangeRates {
        let urlStr = "https://hq.sinajs.cn/list=fx_susdcny,fx_susdhkd,fx_susdkrw"
        guard let url = URL(string: urlStr) else { return ExchangeRates() }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return ExchangeRates() }
        let body = StringDecoding.decodeGBK(data)

        var rates = ExchangeRates()
        for line in body.components(separatedBy: "\n") {
            if let r = parseFirstPositiveDouble(from: line, code: "fx_susdcny") { rates.usdToCny = r }
            if let r = parseFirstPositiveDouble(from: line, code: "fx_susdhkd") { rates.usdToHkd = r }
            if let r = parseFirstPositiveDouble(from: line, code: "fx_susdkrw") { rates.usdToKrw = r }
        }
        return rates
    }
```

- [ ] **Step 2: Verify build**

```bash
cd StockMonitor/StockMonitor && xcodebuild build \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Services/CurrencyService.swift
git commit -m "feat(korea): fetch USD/KRW rate from Sina fx_susdkrw"
```

---

## Phase 4: Korean quote fetch (DataService)

### Task 6: Capture Yahoo response fixtures

**Files:**
- Create: `StockMonitorTests/Fixtures/Korea/quote_005930_ks.json`
- Create: `StockMonitorTests/Fixtures/Korea/quote_293490_kq.json`
- Create: `StockMonitorTests/Fixtures/Korea/quote_empty.json`

- [ ] **Step 1: Save real Yahoo responses as fixtures**

```bash
cd StockMonitor/StockMonitor && mkdir -p StockMonitorTests/Fixtures/Korea
curl -sS 'https://query1.finance.yahoo.com/v8/finance/chart/005930.KS?interval=1m&range=1d' \
  -A 'Mozilla/5.0' -o StockMonitorTests/Fixtures/Korea/quote_005930_ks.json
curl -sS 'https://query1.finance.yahoo.com/v8/finance/chart/293490.KQ?interval=1m&range=1d' \
  -A 'Mozilla/5.0' -o StockMonitorTests/Fixtures/Korea/quote_293490_kq.json
```

- [ ] **Step 2: Sanity-check fixtures contain expected fields**

```bash
cd StockMonitor/StockMonitor && python3 -c "
import json
for f in ['quote_005930_ks.json','quote_293490_kq.json']:
    with open('StockMonitorTests/Fixtures/Korea/'+f) as fp: d = json.load(fp)
    m = d['chart']['result'][0]['meta']
    print(f, m['symbol'], m['regularMarketPrice'], m.get('chartPreviousClose'))
"
```
Expected: prints symbol + numeric price + numeric previous close for both files. If `regularMarketPrice` missing or zero, the market may be closed at capture time — capture during KST trading hours or use the historical close anyway (test still works since `chartPreviousClose` is always present).

- [ ] **Step 3: Create `quote_empty.json` synthetic fixture**

```bash
cd StockMonitor/StockMonitor && cat > StockMonitorTests/Fixtures/Korea/quote_empty.json <<'EOF'
{
  "chart": {
    "result": [{
      "meta": {
        "symbol": "999999.KS",
        "regularMarketPrice": null,
        "chartPreviousClose": null,
        "currency": "KRW",
        "exchangeName": "KSC",
        "timezone": "KST"
      },
      "timestamp": [],
      "indicators": { "quote": [{ "close": [] }] }
    }],
    "error": null
  }
}
EOF
```

- [ ] **Step 4: Add fixtures to Xcode test target as resources**

Xcode test bundles include resource files automatically when added to the target. Add each fixture file to the test target via `add_files.rb` (it will create a file reference in the `StockMonitorTests/Fixtures/Korea/` group):

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb \
  StockMonitorTests/Fixtures/Korea/quote_005930_ks.json \
  StockMonitorTests/Fixtures/Korea/quote_293490_kq.json \
  StockMonitorTests/Fixtures/Korea/quote_empty.json
```

After registering, verify resource membership by inspecting the test target's `Copy Bundle Resources` build phase. The `add_files.rb` script handles source files by default; verify it also adds JSON files to resources (open `StockMonitor.xcodeproj/project.pbxproj` and search for `quote_005930_ks.json` — it should appear under both a `PBXFileReference` and the test target's `PBXResourcesBuildPhase`). **If the script did NOT add the files to `PBXResourcesBuildPhase`, edit `add_files.rb` to handle non-Swift files**, or manually open Xcode → select the test target → Build Phases → Copy Bundle Resources → "+", and add the three JSON files.

- [ ] **Step 5: Commit fixtures**

```bash
cd StockMonitor/StockMonitor && git add StockMonitorTests/Fixtures/Korea/*.json StockMonitor.xcodeproj/project.pbxproj
git commit -m "test(korea): add Yahoo chart response fixtures for KOSPI/KOSDAQ"
```

### Task 7: `parseKoreanChartMeta` parser + tests

**Files:**
- Create: `StockMonitorTests/Services/KoreanQuoteParseTests.swift`
- Modify: `StockMonitor/Services/DataService.swift` — add parser

- [ ] **Step 1: Write failing test `StockMonitorTests/Services/KoreanQuoteParseTests.swift`**

```swift
import XCTest
@testable import Stockbar

final class KoreanQuoteParseTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture \(name).json missing — re-run Task 6 to capture")
        }
        return try Data(contentsOf: url)
    }

    func test_parseKoreanChartMeta_kospi() throws {
        let data = try loadFixture("quote_005930_ks")
        let quote = try XCTUnwrap(DataService.parseKoreanChartMeta(data, id: "kr_005930.ks"))
        XCTAssertEqual(quote.code, "kr_005930.ks")
        XCTAssertGreaterThan(quote.price, 0)
        // chartPreviousClose should be positive; change should match price - prevClose
        let prev = quote.price - quote.change
        XCTAssertGreaterThan(prev, 0)
        XCTAssertEqual(quote.changePercent, (quote.price - prev) / prev * 100, accuracy: 0.01)
    }

    func test_parseKoreanChartMeta_kosdaq() throws {
        let data = try loadFixture("quote_293490_kq")
        let quote = try XCTUnwrap(DataService.parseKoreanChartMeta(data, id: "kr_293490.kq"))
        XCTAssertEqual(quote.code, "kr_293490.kq")
        XCTAssertGreaterThan(quote.price, 0)
    }

    func test_parseKoreanChartMeta_emptyPrices_returnsNil() throws {
        let data = try loadFixture("quote_empty")
        XCTAssertNil(DataService.parseKoreanChartMeta(data, id: "kr_999999.ks"))
    }

    func test_parseKoreanChartMeta_garbageData_returnsNil() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(DataService.parseKoreanChartMeta(data, id: "kr_005930.ks"))
    }
}
```

- [ ] **Step 2: Register test file**

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb StockMonitorTests/Services/KoreanQuoteParseTests.swift
```

- [ ] **Step 3: Run tests to verify failure**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanQuoteParseTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: build FAIL with `'parseKoreanChartMeta' is not a member of 'DataService'`.

- [ ] **Step 4: Add parser to `StockMonitor/Services/DataService.swift`**

Append before the closing `}` of `DataService` class:

```swift
    // MARK: - Yahoo Finance（韩股）

    /// 从 Yahoo `/v8/finance/chart/<symbol>` 响应 meta 段解析 Quote。
    /// 接口对每只股票各请求一次（v7 batch quote 已被 Yahoo 限流封禁）。
    static func parseKoreanChartMeta(_ data: Data, id: String) -> Quote? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let meta = result["meta"] as? [String: Any] else { return nil }

        let price    = (meta["regularMarketPrice"] as? Double) ?? 0
        let prev     = (meta["chartPreviousClose"] as? Double)
                    ?? (meta["previousClose"]     as? Double) ?? 0
        guard price > 0, prev > 0 else { return nil }

        let change  = price - prev
        let pct     = change / prev * 100
        let mktTime = meta["regularMarketTime"] as? Double ?? 0
        let updateTime: String = {
            guard mktTime > 0 else { return "" }
            let fmt = DateFormatter()
            fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return fmt.string(from: Date(timeIntervalSince1970: mktTime))
        }()

        return Quote(code: id, name: "", price: price, change: change,
                     changePercent: pct, updateTime: updateTime)
    }
```

- [ ] **Step 5: Run tests**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanQuoteParseTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Services/DataService.swift StockMonitorTests/Services/KoreanQuoteParseTests.swift StockMonitor.xcodeproj/project.pbxproj
git commit -m "feat(korea): parse Yahoo v8 chart meta into Quote for Korean stocks"
```

### Task 8: `fetchKoreanQuotes` concurrent fetcher

**Files:**
- Modify: `StockMonitor/Services/DataService.swift` — add async fetch fn

- [ ] **Step 1: Add `fetchKoreanQuotes` to `DataService`**

Append before the closing `}` of the `DataService` class (right after `parseKoreanChartMeta` from Task 7):

```swift
    /// 并发拉取韩股报价。`ids` 为 Stockbar 内部 ID（如 `kr_005930.ks`）。
    /// 单只失败不影响其它；返回成功解析的 quotes 字典。
    static func fetchKoreanQuotes(ids: [String]) async -> [String: Quote] {
        guard !ids.isEmpty else { return [:] }
        return await withTaskGroup(of: (String, Quote?).self) { group in
            for id in ids {
                guard let symbol = KoreanStockID.toYahooSymbol(id) else { continue }
                group.addTask {
                    guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1m&range=1d") else {
                        return (id, nil)
                    }
                    var req = URLRequest(url: url)
                    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: req) else {
                        return (id, nil)
                    }
                    return (id, parseKoreanChartMeta(data, id: id))
                }
            }
            var out: [String: Quote] = [:]
            for await (id, q) in group {
                if let q { out[id] = q }
            }
            return out
        }
    }
```

Notes:
- Function is `async` not `async throws` — failures are swallowed per-ID (matches design's "single failure doesn't fail batch" requirement; aligns with `CurrencyService.fetchRates` non-throwing style).
- No retry logic. `AppState.refresh()` calls this every tick; transient failures recover on the next tick.

- [ ] **Step 2: Build to verify**

```bash
cd StockMonitor/StockMonitor && xcodebuild build \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Services/DataService.swift
git commit -m "feat(korea): concurrent fetch Korean quotes via Yahoo v8 chart endpoint"
```

---

## Phase 5: AppState integration & market session

### Task 9: `koreanMarketSession` + tests

**Files:**
- Modify: `StockMonitor/State/AppState.swift` — add static `koreanMarketSession`
- Create: `StockMonitorTests/State/KoreanMarketSessionTests.swift`

- [ ] **Step 1: Write failing test**

Create `StockMonitorTests/State/KoreanMarketSessionTests.swift`:

```swift
import XCTest
@testable import Stockbar

final class KoreanMarketSessionTests: XCTestCase {

    private func kstDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_session_at_open() {
        // 2026-05-14 (Thursday) 09:00 KST → "盘中"
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 9, minute: 0)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_one_minute_after_open() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 9, minute: 1)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_one_minute_before_close() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 15, minute: 29)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_at_close_inclusive() {
        // 15:30 inclusive — last point of trading
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 15, minute: 30)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_one_minute_after_close() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 15, minute: 31)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }

    func test_session_before_open() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 8, minute: 59)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }

    func test_session_saturday_returns_nil() {
        // 2026-05-16 is Saturday
        let d = kstDate(year: 2026, month: 5, day: 16, hour: 10, minute: 0)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }

    func test_session_sunday_returns_nil() {
        // 2026-05-17 is Sunday
        let d = kstDate(year: 2026, month: 5, day: 17, hour: 10, minute: 0)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }
}
```

- [ ] **Step 2: Register test file**

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb StockMonitorTests/State/KoreanMarketSessionTests.swift
```

- [ ] **Step 3: Run tests to verify failure**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanMarketSessionTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: build FAIL — `koreanMarketSession` not found.

- [ ] **Step 4: Add `koreanMarketSession` to `AppState`**

In `StockMonitor/State/AppState.swift`, append before the closing `}` of `AppState` class (right after `usMarketSession()`):

```swift
    // MARK: - 韩股交易时段

    /// 韩股交易时段：返回 "盘中" 或 nil（非交易时段 / 周末）。
    /// KST 固定 UTC+9，无夏令时。
    static func koreanMarketSession(at now: Date = Date()) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let wd = comps.weekday ?? 1
        // Swift Calendar weekday: 1=周日, 2=周一, ..., 6=周五, 7=周六
        guard wd >= 2 && wd <= 6 else { return nil }
        let t = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if t >= 9 * 60 && t <= 15 * 60 + 30 { return "盘中" }
        return nil
    }
```

- [ ] **Step 5: Run tests**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanMarketSessionTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: 8 tests pass.

- [ ] **Step 6: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/State/AppState.swift StockMonitorTests/State/KoreanMarketSessionTests.swift StockMonitor.xcodeproj/project.pbxproj
git commit -m "feat(korea): add AppState.koreanMarketSession for KST 09:00-15:30"
```

### Task 10: Wire Korean quotes into `AppState.refresh()`

**Files:**
- Modify: `StockMonitor/State/AppState.swift:178-216` — `refresh()`

- [ ] **Step 1: Update `refresh()` to include KR branch**

Replace the body of `refresh()` (lines 178–216 of current `AppState.swift`) with:

```swift
    func refresh() async {
        isLoading = true
        hasError  = false
        do {
            let all       = stocks.map(\.id)
            let sinaCodes = all.filter { !$0.hasPrefix("hk") && !KoreanStockID.isKorean($0) }
            let hkCodes   = all.filter {  $0.hasPrefix("hk") }
            let krIds     = all.filter {  KoreanStockID.isKorean($0) }

            let isOvernight = Self.usMarketSession() == "夜盘"
            let usCodes = isOvernight ? all.filter { $0.hasPrefix("usr_") } : []

            // 所有数据源并行请求
            async let sinaResult      = DataService.fetchSinaQuotes(codes: sinaCodes)
            async let hkResult        = DataService.fetchTencentHKQuotes(codes: hkCodes)
            async let krResult        = DataService.fetchKoreanQuotes(ids: krIds)
            async let ratesResult     = CurrencyService.fetchRates()
            async let overnightResult = PythService.fetchOvernightPrices(codes: usCodes)

            let (s, h) = try await (sinaResult, hkResult)
            let kr        = await krResult
            let rates     = await ratesResult
            let overnight = await overnightResult

            // 夜盘时段：清除新浪的盘后旧价格，用夜盘实时价替换
            var merged = s
            if isOvernight {
                for key in merged.keys where key.hasPrefix("usr_") {
                    merged[key]?.extendedPrice = overnight[key]
                }
            }

            quotes.merge(merged) { $1 }
            quotes.merge(h)  { $1 }
            quotes.merge(kr) { $1 }
            exchangeRates  = rates
            lastUpdateTime = Date()
            syncStockNamesFromQuotes()
        } catch {
            hasError = true
        }
        isLoading = false
    }
```

Changes from the original:
- `sinaCodes` filter now also excludes KR IDs (they don't start with `hk` but they also shouldn't go to Sina).
- New `krIds` filter.
- New `async let krResult` branch.
- Final `quotes.merge(kr) { $1 }`.
- KR is non-throwing (`fetchKoreanQuotes` returns `[:]` on failure), so it's awaited outside the `try`.

- [ ] **Step 2: Build & run full test suite**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -30
```
Expected: all tests pass; no regression in `AppStateTests`.

- [ ] **Step 3: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/State/AppState.swift
git commit -m "feat(korea): wire fetchKoreanQuotes into AppState.refresh parallel pipeline"
```

---

## Phase 6: RefreshScheduler trading hours

### Task 11: Include KR session in `isTradingHour`

**Files:**
- Modify: `StockMonitor/Services/RefreshScheduler.swift:46-70` — `isTradingHour`

- [ ] **Step 1: Review existing implementation**

Note: the current `isTradingHour` already returns `true` unconditionally for any weekday (the US branch at the bottom catches everything). So韩股 in北京 time 08:00-14:30 is automatically covered. No code change needed for KR to be refreshed.

**However**: the current implementation has a `return true` followed by an unreachable `return false` — that's a latent issue but not introduced by KR. Leave it alone (out of scope).

To be explicit that KR is intended, add a comment.

- [ ] **Step 2: Add documentation comment only**

Edit `StockMonitor/Services/RefreshScheduler.swift` lines 64–67, replace:

```swift
        // 美股：夜盘+盘前+正盘+盘后几乎覆盖全天（北京时间）
        // 夜盘 08:00-16:00, 盘前 16:00-21:30, 正盘 21:30-04:00, 盘后 04:00-08:00
        // 工作日已在上方过滤周末，此处直接返回 true
        return true
```

With:

```swift
        // 美股：夜盘+盘前+正盘+盘后几乎覆盖全天（北京时间）
        // 夜盘 08:00-16:00, 盘前 16:00-21:30, 正盘 21:30-04:00, 盘后 04:00-08:00
        // 韩股：北京时间 08:00-14:30（KST 09:00-15:30），与美股夜盘窗口重叠
        // 工作日已在上方过滤周末，此处直接返回 true
        return true
```

- [ ] **Step 3: Build to verify (no behavior change expected)**

```bash
cd StockMonitor/StockMonitor && xcodebuild build \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Services/RefreshScheduler.swift
git commit -m "docs(korea): note KR trading hours in RefreshScheduler"
```

---

## Phase 7: Chart service for Korean intraday

### Task 12: Capture chart fixture

**Files:**
- Create: `StockMonitorTests/Fixtures/Korea/chart_005930_ks.json`

- [ ] **Step 1: Capture fixture (re-use Task 6 file)**

The quote fixture from Task 6 already includes the full chart response (timestamp + close arrays). Symlink or copy:

```bash
cd StockMonitor/StockMonitor && cp StockMonitorTests/Fixtures/Korea/quote_005930_ks.json \
   StockMonitorTests/Fixtures/Korea/chart_005930_ks.json
```

- [ ] **Step 2: Register**

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb StockMonitorTests/Fixtures/Korea/chart_005930_ks.json
```

Same caveat as Task 6 step 4: verify it lands in `Copy Bundle Resources`.

- [ ] **Step 3: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitorTests/Fixtures/Korea/chart_005930_ks.json StockMonitor.xcodeproj/project.pbxproj
git commit -m "test(korea): add chart fixture"
```

### Task 13: `parseKoreanChartPoints` + tests

**Files:**
- Create: `StockMonitorTests/Services/KoreanChartParseTests.swift`
- Modify: `StockMonitor/Services/ChartService.swift` — add static parser + private fetch

- [ ] **Step 1: Write failing test**

Create `StockMonitorTests/Services/KoreanChartParseTests.swift`:

```swift
import XCTest
@testable import Stockbar

final class KoreanChartParseTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture \(name).json missing — re-run Task 12 to capture")
        }
        return try Data(contentsOf: url)
    }

    func test_parseKoreanChartPoints_returns_points_and_preclose() throws {
        let data = try loadFixture("chart_005930_ks")
        let result = try XCTUnwrap(ChartService.parseKoreanChartPoints(data))
        XCTAssertGreaterThan(result.preClose, 0)
        XCTAssertFalse(result.points.isEmpty)
        // x 轴基准：KST 09:00 = index 0；最大 index 389（15:29）
        for p in result.points {
            XCTAssertGreaterThanOrEqual(p.id, 0)
            XCTAssertLessThanOrEqual(p.id, 389)
            XCTAssertGreaterThan(p.price, 0)
        }
    }

    func test_parseKoreanChartPoints_invalid_data() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(ChartService.parseKoreanChartPoints(data))
    }

    func test_parseKoreanChartPoints_empty_meta() throws {
        let data = try loadFixture("quote_empty")
        // quote_empty has empty timestamp + close arrays; parser returns nil (no points)
        XCTAssertNil(ChartService.parseKoreanChartPoints(data))
    }
}
```

- [ ] **Step 2: Register test file**

```bash
cd StockMonitor/StockMonitor && ruby add_files.rb StockMonitorTests/Services/KoreanChartParseTests.swift
```

- [ ] **Step 3: Run to verify failure**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanChartParseTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: build FAIL — `parseKoreanChartPoints` undefined.

- [ ] **Step 4: Add Korean intraday support to `ChartService`**

In `StockMonitor/Services/ChartService.swift`:

**4a.** Update the dispatch in `fetchIntraday` (lines 12–17):

```swift
    /// 获取当日分时数据
    static func fetchIntraday(stock: Stock) async throws -> (points: [MinutePoint], preClose: Double) {
        if stock.market == .usStock {
            return try await fetchUSIntraday(stockId: stock.id)
        }
        if stock.market == .krStock {
            return try await fetchKoreanIntraday(stockId: stock.id)
        }
        return try await fetchTencentIntraday(stock: stock)
    }
```

**4b.** Append before the closing `}` of `ChartService`:

```swift
    // MARK: - Yahoo Finance API（韩股，KST 09:00-15:30）
    // x 轴以 09:00 KST 为 index=0，最大 index=389（15:29）

    private static func fetchKoreanIntraday(stockId: String) async throws -> (points: [MinutePoint], preClose: Double) {
        guard let symbol = KoreanStockID.toYahooSymbol(stockId) else {
            throw URLError(.badURL)
        }
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1m&range=1d"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let result = parseKoreanChartPoints(data) else { throw URLError(.cannotParseResponse) }
        return result
    }

    /// 解析 Yahoo v8 chart 响应为韩股 MinutePoint 列表 + 昨收。
    /// 抽出供单元测试使用；失败返回 nil。
    static func parseKoreanChartPoints(_ data: Data) -> (points: [MinutePoint], preClose: Double)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first else { return nil }

        let meta = result["meta"] as? [String: Any] ?? [:]
        let preClose = (meta["chartPreviousClose"] as? Double)
                    ?? (meta["previousClose"] as? Double)
                    ?? 0
        guard let timestamps = result["timestamp"] as? [Double],
              let indicators = result["indicators"] as? [String: Any],
              let quoteArr = indicators["quote"] as? [[String: Any]],
              let rawCloses = quoteArr.first?["close"] as? [Any] else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let fmt = DateFormatter()
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "HH:mm"

        var points: [MinutePoint] = []
        for (i, ts) in timestamps.enumerated() {
            guard i < rawCloses.count,
                  let price = rawCloses[i] as? Double, price > 0 else { continue }
            let date = Date(timeIntervalSince1970: ts)
            let comps = cal.dateComponents([.hour, .minute], from: date)
            let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let idx = minuteOfDay - (9 * 60)  // 距 09:00 的分钟数
            guard idx >= 0, idx <= 389 else { continue }
            points.append(MinutePoint(id: idx, time: fmt.string(from: date), price: price))
        }
        guard !points.isEmpty else { return nil }
        return (points, preClose)
    }
```

- [ ] **Step 5: Run tests**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StockMonitorTests/KoreanChartParseTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -20
```
Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Services/ChartService.swift StockMonitorTests/Services/KoreanChartParseTests.swift StockMonitor.xcodeproj/project.pbxproj
git commit -m "feat(korea): parse Korean intraday from Yahoo v8 chart (KST 09:00-15:30 → idx 0-389)"
```

---

## Phase 8: Chart view x-axis

### Task 14: Add Korean x-axis labels to `StockChartView`

**Files:**
- Modify: `StockMonitor/Views/StockChartView.swift:20-39` — `fullDayRange` and `xAxisLabels`

- [ ] **Step 1: Update both market switches**

In `StockMonitor/Views/StockChartView.swift`, replace lines 20–39 with:

```swift
    private var fullDayRange: ClosedRange<Int> {
        switch stock.market {
        case .aStock:  return 0...239
        case .hkStock: return 0...329
        case .usStock: return 0...959
        case .krStock: return 0...389
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
        case .krStock:
            // 基准 09:00 KST；180=12:00；389=15:29
            return [(0, "09:00"), (90, "10:30"), (180, "12:00"), (270, "13:30"), (389, "15:30")]
        }
    }
```

- [ ] **Step 2: Build to verify**

```bash
cd StockMonitor/StockMonitor && xcodebuild build \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Views/StockChartView.swift
git commit -m "feat(korea): add Korean intraday x-axis (09:00-15:30, 390 points)"
```

---

## Phase 9: UI surfaces — stock list & settings

### Task 15: Include Korean group in `DropdownView`

**Files:**
- Modify: `StockMonitor/Views/DropdownView.swift:38-49` — market iteration arrays

- [ ] **Step 1: Update `DropdownView.swift`**

In `StockMonitor/Views/DropdownView.swift`, replace:

```swift
            for market in [Market.aStock, .hkStock, .usStock] {
                let s = appState.stocks.filter { $0.market == market && !holdingIds.contains($0.id) }
                if !s.isEmpty { result.append((market, sorted(s, market: market), nil)) }
            }
        } else {
            for market in [Market.aStock, .hkStock, .usStock] {
                let s = appState.stocks.filter { $0.market == market }
                if !s.isEmpty { result.append((market, sorted(s, market: market), nil)) }
            }
        }
```

With:

```swift
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
```

- [ ] **Step 2: Build to verify**

```bash
cd StockMonitor/StockMonitor && xcodebuild build \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Views/DropdownView.swift
git commit -m "feat(korea): show Korean stock group in dropdown"
```

### Task 16: Add Korean search via Yahoo `/v1/finance/search`

**Files:**
- Modify: `StockMonitor/Views/SettingsView.swift` — `fetchSuggestions` and `directResult`

- [ ] **Step 1: Add Yahoo search fallback for KR keywords**

In `StockMonitor/Views/SettingsView.swift`, **append** a new private function after `sinaFetchSuggestions` (around line 443) and **modify** `fetchSuggestions` to chain it. Specifically:

**1a.** Replace the body of `fetchSuggestions` (lines 387–414) with:

```swift
    /// 腾讯代理搜索（JSON，直接返回中文名，A股+港股最可靠）
    private func fetchSuggestions(_ keyword: String) async -> [SearchResult] {
        // 韩股关键字：直接走 Yahoo 搜索（腾讯/新浪不覆盖）
        if looksKorean(keyword) {
            let kr = await yahooKoreanSearch(keyword)
            if !kr.isEmpty { return kr }
        }
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
                let parts = code.components(separatedBy: ".")
                let ticker = (parts.count > 1 ? parts.dropLast().joined(separator: ".") : code).lowercased()
                return SearchResult(id: "usr_\(ticker)", name: name, market: .usStock)
            default: return nil
            }
        }
        if results.isEmpty {
            // 退路：Yahoo 韩股搜索 → 直接代码兜底
            let yahoo = await yahooKoreanSearch(keyword)
            if !yahoo.isEmpty { return yahoo }
            return directResult(for: keyword)
        }
        return results
    }

    /// 关键字看起来像韩股查询：6位代码、韩文字母（Hangul Syllables）、或显式带 .ks/.kq 后缀
    private func looksKorean(_ s: String) -> Bool {
        let k = s.trimmingCharacters(in: .whitespaces)
        if k.lowercased().hasSuffix(".ks") || k.lowercased().hasSuffix(".kq") { return true }
        // 含 Hangul（U+AC00–U+D7AF）
        if k.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7AF }) { return true }
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
            // 韩股 symbol 以 .KS / .KQ 结尾；exchange 字段 KSC (KOSPI) 或 KOE (KOSDAQ)
            let isKR = symbol.uppercased().hasSuffix(".KS") || symbol.uppercased().hasSuffix(".KQ")
            guard isKR else { return nil }
            let id = KoreanStockID.fromYahooSymbol(symbol)
            let name = (q["shortname"] as? String) ?? (q["longname"] as? String) ?? symbol
            return SearchResult(id: id, name: name, market: .krStock)
        }
    }
```

**1b.** Extend `directResult` (lines 446–471) to recognize KR-direct codes. After the `usr_` block, add:

```swift
        // 韩股：用户输入 kr_005930.ks 或 005930.ks 形式
        if k.hasPrefix("kr_") {
            return [SearchResult(id: k, name: k.uppercased(), market: .krStock)]
        }
        if k.hasSuffix(".ks") || k.hasSuffix(".kq") {
            return [SearchResult(id: "kr_\(k)", name: k.uppercased(), market: .krStock)]
        }
```

The complete updated `directResult` body after these additions:

```swift
    private func directResult(for keyword: String) -> [SearchResult] {
        let k = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
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
        // 韩股：用户输入 kr_005930.ks 或 005930.ks 形式
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
```

Note on the 6-digit collision: A 6-digit input goes to A股 (existing rule). Users wanting KR by code must type `005930.ks` or `kr_005930.ks` explicitly, or search by name (e.g. "samsung").

- [ ] **Step 2: Update search placeholder text**

Change line 220 in `SettingsView.swift`:

```swift
TextField("代码或名称（回车搜索）", text: $searchText)
```

to:

```swift
TextField("代码 / 名称 / Samsung / 005930.ks", text: $searchText)
```

- [ ] **Step 3: Build**

```bash
cd StockMonitor/StockMonitor && xcodebuild build \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd StockMonitor/StockMonitor && git add StockMonitor/Views/SettingsView.swift
git commit -m "feat(korea): add Yahoo search for Korean stocks + direct code/suffix support"
```

---

## Phase 10: Full regression & manual smoke test

### Task 17: Run full test suite

- [ ] **Step 1: Run all tests**

```bash
cd StockMonitor/StockMonitor && xcodebuild test \
  -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/stockbar_test_build 2>&1 | tail -40
```
Expected: 0 failures. Print test counts for each new suite:
- `KoreanStockIDTests` — 10 tests
- `KoreanQuoteParseTests` — 4 tests
- `KoreanMarketSessionTests` — 8 tests
- `KoreanChartParseTests` — 3 tests
- `CurrencyKRWTests` — 8 tests
- existing `StockTests` — 7 + 5 new = 12 tests

If any fail, fix before proceeding.

### Task 18: Manual smoke test

Build a release-style universal binary and exercise the UI.

- [ ] **Step 1: Local Release build**

```bash
cd StockMonitor/StockMonitor && xcodebuild \
  -project StockMonitor.xcodeproj \
  -scheme Stockbar \
  -configuration Release \
  -derivedDataPath /tmp/stockbar_kr_smoke \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`. App path:

```bash
find /tmp/stockbar_kr_smoke -name "Stockbar.app" -maxdepth 6
```

- [ ] **Step 2: Open the app**

```bash
open "$(find /tmp/stockbar_kr_smoke -name 'Stockbar.app' -maxdepth 6 | head -1)"
```

- [ ] **Step 3: Walk through manual checklist**

Tick each item:
- [ ] Open settings → Add stock → Type `samsung` → KOSPI result appears with KR market tag → Add succeeds; stock shows in "韩股" group with a KRW price.
- [ ] Add `005930.ks` directly via search → resolves to Samsung.
- [ ] Add a KOSDAQ stock (e.g. `293490` then type `.kq` suffix: `293490.kq`) → "韩股" group, second entry.
- [ ] Settings → 持仓汇总货币 → 韩元 ₩ → 总盈亏 / 持仓 number switches to KRW.
- [ ] Settings → 持仓汇总货币 → 人民币 ¥ → KR stock pnl included in 总盈亏 with sensible magnitude (~1/200 of KRW number).
- [ ] Status bar picker → choose KR stock → menu bar shows KR price + percent in the user's color theme.
- [ ] Click KR stock row → chart opens → x-axis shows 09:00 / 10:30 / 12:00 / 13:30 / 15:30 → line drawn → bottom row shows 昨收/今开/最高/最低/现价.
- [ ] During KST trading hours (北京 08:00–14:30): price updates every refresh tick.
- [ ] Outside trading hours: still shows last known price; no errors in `~/Library/Logs/Stockbar/app.log`.
- [ ] Disable Wi-Fi for 60 seconds → KR stock retains last price; no crash; logs show retry attempts.
- [ ] Search "三星" (Chinese) → no result (expected; Yahoo lacks Chinese mapping). Search "삼성" (Hangul) → triggers Yahoo path → returns Samsung.

- [ ] **Step 4: Commit only if anything from prior tasks needed adjusting**

This is the manual gate. If smoke test passes, no commit. If a fix was needed, commit it with `fix(korea): <what>` message.

---

## Self-Review Summary

Spec coverage cross-check (each spec section → task that fulfills it):

| Spec section | Task |
|--------------|------|
| 3. Architecture & data flow | Task 10 (refresh wiring) |
| 4. ID & Stock model | Tasks 1, 2 |
| 5.1 DataService (Korean quotes) | Tasks 6, 7, 8 |
| 5.2 ChartService | Tasks 12, 13 |
| 5.3 CurrencyService (KRW) | Tasks 3, 4, 5 |
| 5.4 Search | Task 16 |
| 6.1 StockGroupView (group order) | Task 15 |
| 6.2 Add-stock panel | Task 16 (placeholder + KR search) |
| 6.3 StockRowView | unchanged (KR绕过盘外标记 by prefix mismatch — verified during smoke) |
| 6.4 SettingsView displayCurrency | Task 4 (DisplayCurrency.krw exposes via existing `ForEach(DisplayCurrency.allCases)`) |
| 6.5 MenuBarLabel | unchanged (works via existing `statusBarStock` mechanism — verified during smoke) |
| 7. Trading hours | Tasks 9, 11 |
| 8. Error handling | Implemented across tasks (DataService swallows per-ID failure; CurrencyService defaults; ChartService throws → UI shows "暂无分时数据") |
| 9.1 Unit tests | Tasks 1, 3, 7, 9, 13 |
| 9.3 Manual regression | Task 18 |

No placeholders. Type names verified consistent (`KoreanStockID.toYahooSymbol`, `parseKoreanChartMeta`, `parseKoreanChartPoints`, `fetchKoreanQuotes`, `fetchKoreanIntraday`, `koreanMarketSession`).
