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

- [x] 分支 `3D-project`
- [x] 基線測試／截圖
- [x] `qa/check.py`（統一入口）、`dev/setup.py`／`play.bat`／`export.bat`

## 下一步

- [ ] （進行中）Phase 1 拆 Battle.gd

## 發現的問題（待登記進 50_QA_PLAN.md 的缺陷登記簿）

| 暫編 | 說明 | 狀態 |
|---|---|---|
| F-1 | `Env.HOOKS` 漏列 `TL_PICK`：單獨使用它時 `any_hook()` 為假 → 存檔不受保護（同 RG-61 的 TL_LEVEL／TL_FOCUS 舊案） | 待修 |
| F-2 | `Battle._restart()` 對 `get_children()` 全部 `queue_free()`，包含地貌層 `_terrain_layer`（未歸 null）→ 重來之後地貌可能消失 | 待驗證 |
