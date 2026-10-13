# 工作日誌：環境 ＋ 重構 ＋ 3D 準備（暫存；全部做完後併入 CHANGELOG 並刪除）

> 這份是**接手用的進度紀錄**：session 中斷（額度、重開）時從「下一步」那一行接著做。
> 分支：`3D-project`（從 master `0621b0b` 切出；**未 push**）。

## 使用者的五件事

1. 環境：下載必要檔案與工具、設定好，讓使用者能跑遊戲
2. 審視程式碼，找出「砍了遊戲就無法運作」的核心區段
3. 重構程式碼結構，方便開發與維護
4. 開 `3D-project` 分支，為 2D→3D 做準備
5. 檢查現階段遊戲的問題與 bug

## 基線（動手前，master 0621b0b）

- Godot 4.7 console exe、Windows 匯出範本、`export_presets.cfg` **本來就在這台機器上**（`python dev/setup.py --check` 全綠）
- 19 支 headless 測試全過（flow 50 / build 79 / combat 218 / tide 47 / save 98 / determinism 20 / hud 709 /
  tech 56 / audio 145 / perf 28 / campaign 945 / endless 70 / daily 42 / blueprint 51 / roster 83 /
  tycoon 74 / progress 146 / difficulty 65 / m2 368）
- `qa/gd_lint.py` 0 條
- 截圖基線 32 張（`qa/check.py shots`）。**重構的判準：0 像素差。**
- 工具 `game-studio` skill（CLAUDE.md 要求先載入）在這台機器上**不存在**（`~/.claude/skills/` 只有 electronics-circuit-design）

## 重構策略（重點）

`screens/Battle.gd` 5316 行是唯一的神類別（全專案 18181 行的 29%）。其餘檔案結構健康：
`sim/`、`data/` 純函式且單向依賴。成員交叉分析顯示 **繪圖層是葉節點**（UI 與輸入從不呼叫它），
所以可以無痛抽成「舞台」——那也正是 2D→3D 的接縫。

工具：`gdsplit.py`（scratchpad，不進 repo）機械搬運 ＋ 改寫跨模組引用，**不手改函式本體**。
安全網：截圖矩陣 0 像素差 ＋ 19 支測試 ＋ 十條 clicktest。

Phase 1：`screens/battle/` ← Stage2D（視野＋繪圖）、Overlay2D（小地圖／箭頭／能量列）、Feedback（音訊＋死因）、SelfTest（自檢＋示範佈局＋壓力）
Phase 2：HUD 面板拆成各自的類別
Phase 3：render/ 分 2D 專用與共用；Main.gd 標題背景抽出

## 已完成

- [x] 分支 `3D-project`（從 master `0621b0b` 切出；**未 push**）
- [x] 基線：19 支測試全過、gd_lint 0 條、截圖基線 32 張（兩次重拍 0 像素差＝確定性）
- [x] `qa/check.py`（統一入口）、`dev/setup.py`／`play.bat`／`export.bat`、`qa/gd_graph.py`（依賴圖／砍除分析／分層檢查）
- [x] Phase 1（60791e5）：Battle.gd → Stage／Stage2D／Overlay2D／Feedback／SelfTest（5316→2336）
- [x] Phase 2（05cd566）：HUD 11 個面板到 `screens/battle/hud/`（→800 行）；Phase 2b（4b67cbc）各面板自建 widget（→約 690 行）
- [x] 以上每一步：32 張截圖逐像素 0 差、clicktest 全過
- [x] F-1 TL_PICK 漏列（修；gd_lint 規則 8 防再犯）、F-2 重來之後地貌消失（修；clicktest restart 段落）
- [x] 文件草稿：README.md、docs/60_CODE_MAP.md、docs/70_3D_MIGRATION.md（數字待最後校正）

## 下一步（照順序）

- [ ] （進行中）Phase 3：render/2d/（Glyphs／Foes／Terrain 搬家；TitleBackdrop 從 Main.gd 抽出）→ 驗證 → commit
- [ ] 全測試（19 支，含 campaign）＋ 效能量測（baseline vs 現在；TL_STRESS 在這台機器被釘 133ms，RG-177，要換量法）
- [ ] 程式碼審查找 bug（聚焦：存檔遷移、離線結算、每日換日、設定套用、Hooks）
- [ ] 文件校正：60／70 的行數、CLAUDE.md 結構段與指令、30_TECH_DESIGN §結構、20/10 內的 `Battle._draw_*` 路徑、CHANGELOG、50_QA_PLAN 缺陷登記（RG-178 重來地貌、RG-179 TL_PICK）、40_PRODUCTION_PLAN §5
- [ ] VERSION bump（0.43.0）→ 匯出 exe → 在 exe 上跑 clicktest ＋ 截圖（確認版本號是新的）
- [ ] （選配）Stage3D 脊椎 spike，放在 TL 鉤子後面、預設 2D
- [ ] 最後：整理給使用者的簡報（要他決斷的：D1–D7 摘要、是否 push）

## 發現的問題

| 編號 | 說明 | 狀態 |
|---|---|---|
| RG-178 | `Battle._restart()` 對 `get_children()` 全部 `queue_free()`，連地貌層一起砍掉；`_terrain_id` 沒變所以不會重建 → 按「立刻重來」之後整張圖地貌消失（master 上已驗證：截圖前後差異；修後逐像素相同） | ✅ 已修 |
| RG-179 | `Env.HOOKS` 漏列 `TL_PICK`：單獨使用時 `any_hook()` 為假 → 存檔不受保護（RG-61 的同一個錯第三次） | ✅ 已修；`gd_lint` 規則 8 |
| （觀察） | 重構時差點踩到：成員改名後，函式參數與新成員同名（`_on_mode(…, mode)` 變 `mode = mode`）；外部畫面（Campaign）讀 Battle 內部欄位——只 grep tests/ 會漏 | 已處理；工具 `gdsplit2` 有 shadow 檢查 |
