# StockMonitor

> A lightweight macOS menu bar app for monitoring A-share, Hong Kong, and US stock markets in real time.

![Platform](https://img.shields.io/badge/platform-macOS%2013.5%2B-lightgrey?logo=apple)
![Architecture](https://img.shields.io/badge/arch-Universal%20(Intel%20%2B%20Apple%20Silicon)-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Screenshot

> *(Coming soon)*

---

## Features

- **Multi-market support** — A-shares (Shanghai / Shenzhen / Beijing), Hong Kong, and US stocks in one place
- **Menu bar display** — Quietly lives in the menu bar; shows icon, real-time price, and change percentage at a glance
- **Intraday chart** — Click any stock row to view a minute-level price chart for the current session
  - A-shares & HK: full-day axis (09:30 – 15:00 / 16:00)
  - US stocks: full extended-hours axis (04:00 – 20:00 ET), covering pre-market, regular, and after-hours
- **US session indicator** — Displays the current US market session (Pre-market / Regular / After-hours / Night) alongside the session price and percentage change vs. previous close
- **Portfolio P&L** — Set cost price and share count per stock; see floating P&L and daily P&L live
- **Sort by change%** — One-click toggle to re-sort the stock list by today's performance
- **Color themes** — Chinese convention (red = up, green = down) or Western convention (green = up, red = down)
- **Persistent storage** — Stock list saved to `~/Library/Application Support/StockMonitor/stocks.json`; auto-backup with up to 10 rolling snapshots
- **Launch at login** — Registers as a login item via `SMAppService`; toggle in Settings
- **Universal binary** — Runs natively on both Apple Silicon and Intel Macs

---

## Requirements

| | |
|---|---|
| **OS** | macOS 13.5 (Ventura) or later |
| **Architecture** | Apple Silicon (arm64) · Intel (x86\_64) |

---

## Installation

1. Download the latest `StockMonitor.dmg` from [Releases](../../releases)
2. Open the DMG and drag **StockMonitor.app** into your **Applications** folder
3. Launch the app — the cow icon will appear in your menu bar

> **First launch on macOS 13+**: If macOS shows a security warning, go to **System Settings → Privacy & Security** and click **Open Anyway**.

---

## Usage

### Adding stocks

1. Click the menu bar icon → open the dropdown
2. Click the **gear icon** (⚙) to open Settings
3. Search by stock name or ticker (e.g. `AAPL`, `腾讯`, `600000`)
4. Click a result to add it to your watchlist

### Setting up portfolio tracking

1. In **Settings → My Stocks**, tap the pencil icon next to a stock
2. Enter your **cost price** and **number of shares**
3. Floating P&L and daily P&L will appear in the stock row

### Intraday chart

Click any stock row in the dropdown to open a minute-level intraday chart. Click the **←** button to return to the list.

### Status bar display

In **Settings → Status Bar**, choose which stock to show in the menu bar, or select **"Don't show"** to display only the icon.

---

## Data Sources

All data is fetched from free public APIs — no API key required.

| Source | Usage |
|--------|-------|
| **Sina Finance** (`hq.sinajs.cn`) | Real-time quotes for A-shares and US stocks; US extended-hours price |
| **Tencent Finance** (`qt.gtimg.cn`) | Real-time quotes for HK stocks |
| **Tencent Finance** (`web.ifzq.gtimg.cn`) | Intraday minute data for A-shares and HK stocks |
| **Yahoo Finance** (`query1.finance.yahoo.com`) | Intraday minute data for US stocks (04:00 – 20:00 ET) |
| **Tencent Search** (`proxy.finance.qq.com`) | Stock search (primary) |
| **Sina Suggest** (`suggest3.sinajs.cn`) | Stock search (fallback) |

> Data is delayed or near-real-time depending on the source and market. This app is intended for personal reference only and should not be used for trading decisions.

---

## Building from Source

```bash
git clone https://github.com/VGEAREN/StockMonitor.git
cd StockMonitor/StockMonitor
open StockMonitor.xcodeproj
```

Select the **StockMonitor** scheme, set destination to **My Mac**, and press **⌘R** to run.

To build a universal release binary:

```bash
xcodebuild -scheme StockMonitor -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
```

---

## Project Structure

```
StockMonitor/
├── Models/
│   ├── Stock.swift          # Stock model (id, name, market, cost, shares)
│   └── Quote.swift          # Quote model (price, change, extended price)
├── State/
│   └── AppState.swift       # Central state, scheduler, persistence, backup
├── Services/
│   ├── DataService.swift    # Real-time quote fetching (Sina / Tencent)
│   ├── ChartService.swift   # Intraday minute data (Tencent / Yahoo Finance)
│   └── RefreshScheduler.swift
├── Views/
│   ├── MenuBarLabel.swift   # Menu bar icon + quote display
│   ├── DropdownView.swift   # Main dropdown panel
│   ├── StockRowView.swift   # Individual stock row
│   ├── StockGroupView.swift # Market group header + rows
│   ├── StockChartView.swift # Intraday minute chart
│   ├── SettingsView.swift   # Settings panel
│   ├── ToolbarView.swift    # Sort / settings toolbar
│   └── ProfitSummaryView.swift
└── StockMonitorApp.swift    # App entry point + AppDelegate
```

---

## Contributing

Issues and pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

---

## License

[MIT](LICENSE)

---

## Disclaimer

This project is for **personal and educational use only**. Stock data is provided by third-party public APIs and may be delayed. The author is not responsible for any financial decisions made based on this application.
