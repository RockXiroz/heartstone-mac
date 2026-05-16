# 爐石英雄戰場助手 · HearthstoneBGHelper

macOS 即時覆蓋層工具，分析英雄戰場商店並推薦最高勝率的購買選擇。

## 功能

| 功能 | 說明 |
|------|------|
| 🏹 箭頭指示 | 在遊戲視窗上直接顯示發光箭頭，指向最佳購買 |
| 📊 勝率分數 | 每張牌顯示綜合勝率百分比（綠 = 高，橘 = 中，紅 = 低）|
| 💬 購買理由 | 說明為何這張牌最好（種族協同、成長性、反制對手等）|
| ❄ 凍結建議 | 建議是否凍結商店以保留高價值牌 |
| 🗺 種族池追蹤 | 追蹤本場次的 5 個活躍種族 |
| 🔄 即時更新 | 每 4 小時從 HSReplay 取得最新勝率數據 |

## 勝率計算邏輯

勝率評分由 6 個加權因素組成：

```
勝率分數 = 0.35 × HSReplay真實勝率
         + 0.25 × 種族協同分數
         + 0.15 × 組合完成度（三倍牌/種族門檻）
         + 0.15 × 後期成長潛力
         + 0.10 × 對手反制效果
         ± 0.05 × 酒館等級效率
```

### 種族協同分數細節
- 若你已有 2 張同族，再買 1 張達到 3 族門檻 → 高加分
- 若正在快速組建種族陣容 → 中加分
- 若種族不在本場次種族池 → 懲罰
- 多名對手使用相同種族 → 競爭懲罰

### 對手追蹤
程式記錄對戰後的對手戰場，計算：
- 哪些對手在走相同種族（競爭分析）
- 哪些對手擁有高攻擊力牌（毒性/神盾加分）

## 系統需求

- **macOS 13.0+**（Ventura 或更新版本）
- **Xcode 15+** 用於編譯
- **Swift 5.9+**

## 安裝與使用

### 1. 編譯

```bash
git clone <this-repo>
cd heartstone-mac
chmod +x build.sh
./build.sh
```

### 2. 首次執行

```bash
./.build/release/HearthstoneBGHelper
```

macOS 會彈出授權請求：
- 前往 **系統設定 → 隱私權與安全性 → 螢幕錄製**
- 啟用 **HearthstoneBGHelper**
- 重新啟動程式

### 3. 使用流程

1. 先開啟爐石傳說並進入英雄戰場
2. 啟動助手（選單列會出現 🎮 圖示）
3. 每次進入補兵階段，助手會自動識別商店卡牌
4. 箭頭會指向最推薦購買的牌，並顯示勝率和理由
5. 若建議凍結，會在頂部顯示藍色凍結提示

### 4. 設定種族池

遊戲開始時（英雄選擇界面），點擊選單列圖示 → **設定種族池…**
勾選本場次出現的 5 個種族，助手會據此調整所有計算。

## 架構說明

```
Sources/HearthstoneBGHelper/
├── main.swift                      # 程式入口
├── AppDelegate.swift               # 應用程式生命週期、選單列
├── Models/
│   ├── Card.swift                  # 卡牌模型（攻防、關鍵詞、協同標籤）
│   ├── GameState.swift             # 遊戲狀態（商店、場上、對手）
│   ├── Tribe.swift                 # 種族枚舉與協同規則
│   └── Recommendation.swift       # 推薦結果模型
├── Services/
│   ├── ScreenCaptureService.swift  # ScreenCaptureKit 截圖（4fps）
│   ├── OCRService.swift            # Vision OCR 識別商店卡名
│   ├── CardDatabase.swift          # 卡牌資料庫（模糊比對）
│   ├── HSReplayAPIService.swift    # HSReplay 勝率數據（帶本地快取）
│   ├── WinRateService.swift        # 多因素勝率計算引擎
│   └── GameStateTracker.swift      # 遊戲狀態追蹤協調器
├── Overlay/
│   ├── OverlayWindow.swift         # 透明點擊穿透懸浮視窗
│   ├── ArrowIndicatorView.swift    # 動畫箭頭 + 工具提示
│   └── OverlayViewController.swift # 覆蓋層 UI 排版邏輯
└── Resources/
    ├── BattlegroundsCards.json     # 離線卡牌資料庫（含勝率底線值）
    └── TribeData.json              # 種族資訊與關鍵卡說明
```

## 主要技術

| 技術 | 用途 |
|------|------|
| **ScreenCaptureKit** | 擷取爐石遊戲視窗（4fps，低 CPU 佔用）|
| **Vision** | OCR 識別商店卡名（支援英文/繁中）|
| **AppKit + CALayer** | 透明覆蓋層 + 動畫箭頭 |
| **Swift Concurrency** | async/await 確保 UI 不卡頓 |
| **URLSession** | 定期從 HSReplay 取得最新勝率數據 |

## 隱私說明

- 本工具**不記錄**任何遊戲數據到外部服務器
- HSReplay 數據查詢僅包含公開統計，無個人帳號
- 所有分析在本機完成

## 常見問題

**Q: 程式找不到爐石視窗？**  
A: 確認爐石傳說已啟動並在英雄戰場模式。若使用全螢幕模式，請嘗試切換為視窗模式。

**Q: 識別不到卡名？**  
A: OCR 準確度依賴字型大小，建議解析度 1920×1080 或以上。可在 OCRService.swift 的 Layout 常數調整卡名區域座標。

**Q: 勝率數據多久更新一次？**  
A: 每 4 小時自動從 HSReplay 取得新數據，並快取至本地。離線時使用內建數據。
