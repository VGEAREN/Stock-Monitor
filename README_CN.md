# StockMonitor 股票监控

> 一款轻量级 macOS 菜单栏股票行情监控工具，支持 A股、港股、美股实时监控。

![平台](https://img.shields.io/badge/平台-macOS%2013.5%2B-lightgrey?logo=apple)
![架构](https://img.shields.io/badge/架构-Universal%20(Intel%20%2B%20Apple%20Silicon)-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![许可证](https://img.shields.io/badge/许可证-MIT-green)

---

## 截图

> *(即将上传)*

---

## 功能特性

- **多市场支持** — 一个应用同时监控 A股（沪/深/北）、港股、美股
- **菜单栏常驻** — 极简悬浮于菜单栏，显示图标、实时价格及涨跌幅，不打扰日常工作
- **分时走势图** — 点击任意股票行，即可查看当日分钟级走势图
  - A股 / 港股：全天坐标轴（09:30 – 15:00 / 16:00）
  - 美股：含盘前+盘中+盘后完整坐标轴（04:00 – 20:00 ET）
- **美股时段标注** — 自动识别当前所处时段（夜盘 / 盘前 / 盘中 / 盘后），展示对应时段实时价及相对昨收涨跌幅
- **持仓盈亏跟踪** — 可为每只股票设置成本价和持仓股数，实时显示浮动盈亏和当日盈亏
- **按涨跌幅排序** — 工具栏一键切换，按今日表现重新排序股票列表
- **涨跌颜色主题** — 支持中式（红涨绿跌）和欧美式（绿涨红跌）两种配色
- **数据持久化** — 股票列表保存至本地文件，最多保留 10 份自动备份，防止数据丢失
- **开机自启动** — 基于 `SMAppService` 注册登录项，可在设置中开关
- **通用二进制** — 原生支持 Apple Silicon 和 Intel Mac

---

## 系统要求

| | |
|---|---|
| **系统版本** | macOS 13.5（Ventura）及以上 |
| **架构** | Apple Silicon (arm64) · Intel (x86\_64) |

---

## 安装方法

1. 从 [Releases](../../releases) 页面下载最新的 `StockMonitor.dmg`
2. 打开 DMG，将 **StockMonitor.app** 拖入 **应用程序** 文件夹
3. 启动应用，菜单栏将出现奶牛图标

> **首次启动提示**：如果 macOS 提示"无法验证开发者"，请前往 **系统设置 → 隐私与安全性**，点击 **仍要打开**。

---

## 使用说明

### 添加股票

1. 点击菜单栏图标展开面板
2. 点击右下角 **齿轮图标**（⚙）进入设置
3. 在搜索框输入股票名称或代码（如 `AAPL`、`腾讯`、`600000`）
4. 点击搜索结果即可添加到自选列表

### 设置持仓

1. 在 **设置 → 我的股票** 中点击铅笔图标
2. 填写 **成本价** 和 **持仓股数**
3. 股票行将实时显示浮动盈亏和当日盈亏

### 分时走势图

点击面板中任意股票行即可打开分时图，点击左上角 **←** 返回列表。

### 状态栏显示

在 **设置 → 状态栏显示** 中，可以选择在菜单栏显示哪只股票的行情，或选择 **"不显示"** 仅保留图标。

---

## 数据来源

所有数据均来自免费公开接口，**无需 API Key**。

| 数据源 | 用途 |
|--------|------|
| **新浪财经** (`hq.sinajs.cn`) | A股、美股实时行情；美股延伸时段价格 |
| **腾讯证券** (`qt.gtimg.cn`) | 港股实时行情 |
| **腾讯证券** (`web.ifzq.gtimg.cn`) | A股、港股分时走势数据 |
| **Yahoo Finance** (`query1.finance.yahoo.com`) | 美股分时走势数据（04:00 – 20:00 ET） |
| **腾讯搜索** (`proxy.finance.qq.com`) | 股票搜索（主） |
| **新浪 Suggest** (`suggest3.sinajs.cn`) | 股票搜索（兜底） |

> 数据为免费公开接口，存在一定延迟，仅供个人参考，不构成任何投资建议。

---

## 本地构建

```bash
git clone https://github.com/VGEAREN/StockMonitor.git
cd StockMonitor/StockMonitor
open StockMonitor.xcodeproj
```

选择 **StockMonitor** Scheme，目标设为 **My Mac**，按 **⌘R** 运行。

构建 Universal 发布包：

```bash
xcodebuild -scheme StockMonitor -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
```

---

## 项目结构

```
StockMonitor/
├── Models/
│   ├── Stock.swift          # 股票模型（代码、名称、市场、成本、持仓）
│   └── Quote.swift          # 行情模型（价格、涨跌、扩展时段价格）
├── State/
│   └── AppState.swift       # 全局状态、定时刷新、数据持久化与备份
├── Services/
│   ├── DataService.swift    # 实时行情抓取（新浪 / 腾讯）
│   ├── ChartService.swift   # 分时数据抓取（腾讯 / Yahoo Finance）
│   └── RefreshScheduler.swift
├── Views/
│   ├── MenuBarLabel.swift   # 菜单栏图标 + 行情显示
│   ├── DropdownView.swift   # 主面板
│   ├── StockRowView.swift   # 股票行
│   ├── StockGroupView.swift # 市场分组
│   ├── StockChartView.swift # 分时走势图
│   ├── SettingsView.swift   # 设置面板
│   ├── ToolbarView.swift    # 工具栏
│   └── ProfitSummaryView.swift
└── StockMonitorApp.swift    # App 入口 + AppDelegate
```

---

## 参与贡献

欢迎提交 Issue 和 Pull Request。对于较大的改动，建议先开 Issue 讨论方向。

---

## 许可证

[MIT](LICENSE)

---

## 免责声明

本项目仅供**个人学习和参考使用**。股票数据由第三方公开接口提供，可能存在延迟，作者不对任何基于本应用的投资决策承担责任。
