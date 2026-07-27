# 《潮與線 / Tide & Line》— 專案指引（給 Claude Code）

塔防 × 節點連線式自動化。**你的生產線就是你的防線**——在敵潮抵達之前，決定這一分鐘是擴產還是築防。

---

## 開工前必做

> **要動手開發本專案，先載入 `game-studio` skill**（`~/.claude/skills/game-studio/SKILL.md`）。
> 它給你：部門帽子、工作室鐵律、階段閘門、批次工作流、QA 五層梯、Godot 實戰地雷。
> 就算使用者只說「繼續做」「做下一批」，也要先載入。

**盤點現況的方法**（不要相信任何記憶，一律實查）：
1. `scripts/core/GameState.gd` 頂部的 `const VERSION`
2. `git log --oneline -15`（批次標題含批次編號，如 `B0.3`）
3. `docs/40_PRODUCTION_PLAN.md` §5「當前狀態」與 §2 批次勾選狀態，對照 1／2 校正

---

## 文件權威順序

發生衝突時，**上位者為準**，並在當批修正下位文件：

```
00_CONCEPT.md  ──►  10_GDD.md  ──►  20_ART_DIRECTION.md
（願景與紅線）      （設計唯一權威）    （視覺／動效／音訊唯一權威）
                         │
                         ├──►  30_TECH_DESIGN.md（架構／存檔／測試鉤子／效能）
                         ├──►  40_PRODUCTION_PLAN.md（里程碑／批次／風險）
                         ├──►  50_QA_PLAN.md（測試策略／bug／回歸）
                         └──►  本檔 CLAUDE.md（工程慣例；與上述衝突時以上述為準）
```

**設計改動先改文件，再改程式碼。** 數值一律寫在 `10_GDD.md` §7，不在程式碼裡即興發明。

---

## 鎖定的設計（不要擅自更動，要改先問使用者）

- **核心取捨**：同一份能量，餵塔還是餵生產線。**塔在交戰時每秒吃電**——這是全案的心臟，不可移除。
- **耗能模型**：**交戰時每秒持續耗電，待機耗能 0**（少數特殊角色例外）。因此約束是**峰值電力**不是平均電力 → **儲槽是核心策略建築**（準備期充能、波次期放電）。
- **全域擊殺回收**：任何塔擊殺敵人回收其價值 **25%** 的礦砂。回收者的特殊能力是**射程內任何敵人死亡即回收 60% 為「能量」**（不限自己擊殺）。
- **塔＝角色**：全自動開火，射程內即攻擊，玩家不下戰鬥指令。生產與物流是另一套「建築」。
- **時間流**：純即時**不可暫停**；波與波之間有 45 秒準備期（可 4× 快進）；戰鬥期不可加速也不可減速。
- **自動化模型**：**流量網路**（每 tick 解容量受限比例分配），**不是**實體物品搬運。
  - **供不應求時按比例降速，不停機**（滿足率線性縮放產出與射速）。
  - **不變量：採集器無輸入需求** → 網路結構上不可能全域死鎖。新增節點不得破壞這一點。
- **主從結構**：塔防是主體，**潮汐公司 tycoon 是附屬補給站，不是第二個遊戲**。
  - tycoon 產出**全部流向塔防**（升級材料、招募券、藍圖槽、難度鑰匙）。
  - **防膨脹硬指標：tycoon 的 UI 深度上限為兩個畫面**（訂單板＋產線編輯）。每批 QA 必查。
  - **塔防不依賴 tycoon**：所有進度都能純靠遊玩取得。
- **商業模式**：**免費遊玩＋內購**（含 P2W 成分）。Windows 版**無廣告**；廣告保留至手機移植版。
  - **B6 賣速度，不賣次數，不賣進度**。禁止：體力、重試權、關卡鑰匙、**付費復活**。
  - **等級軸（付費可買，+80% 上限）的增幅必須被難度層同步吃掉**——買到的是「能挑戰更高難度層」，不是碾壓現有內容。
- **雙排行榜**：每日挑戰同種子同地圖跑兩榜——**統一配置榜**（固定配置，零付費影響，免費玩家的競技場）＋**自由配置榜**（總戰力）。**統一配置榜是對 P2W 的唯一制衡，不得移除、不得收費。**
- **平台**：Windows 先行，**但從第一批就以手機移植為前提設計**：UI 全可縮放（不硬編碼像素位置）、觸控命中區 ≥ 44×44 px、操作不得只靠 hover／右鍵／鍵盤。
- **設計紅線**（硬性禁令）：
  - **R1 無永久損失／刪檔**——失敗只花時間。
  - **R2 無體力值／等待閘門**——想玩多久就玩多久（F2P 下的操作定義：賣速度不賣次數）。

---

## 技術慣例

- **Godot 4.7**，`gl_compatibility` 渲染，Windows Desktop 匯出。
- **`scripts/sim/` 必須是純函式、零副作用、零系統 RNG。** 這是每日挑戰公平性、重播、可驗證榜單的地基。禁用 `randf()`／`randi()`／`Time.get_ticks_*()`，一律用注入的 seeded `Rng`。
- **固定時間步** `TICK = 0.1s`，模擬不使用 `delta`；渲染 60Hz 以插值呈現。
- **色值唯一來源是 `scripts/render/Palette.gd`。** 任何 `Color(...)` 字面量出現在其他檔案，視為缺陷。
- **中文 UI 一律 `SystemFont`**（微軟正黑體）。**不要改回 Godot 預設字型**（無 CJK，會變豆腐字）。
- **狀態讀檔時原地變更**（`clear()` + `append_array()`），絕不重新賦值容器——重新賦值會讓已持有引用的面板拿到斷裂的舊物件。
- **GDScript 嚴格型別地雷**：泛型 `lerp()` 編譯錯 → 用 `lerpf()`；untyped array 的 `for` 變數要顯式型別；`match` 各分支共享作用域，變數名要唯一。
- 存檔：`SaveService.SAVE_VERSION` 常數；讀取一律 `d.get(key, default)`；結構改動寫 `_migrate_sv<N>_to_sv<N+1>()`。**只增不破。**

---

## 跑與測（宣稱「能動」前先實際驗證）

```bash
# 新增腳本/資源後必跑（生成 .uid/.import，需一起 commit）
<godot> --headless --path godot --import

# 自動化測試
<godot> --headless --path godot --script res://tests/flow_test.gd

# 截圖驗證（自動靜音、約 3 秒後存圖並退出）
TL_SHOT="C:/tmp/shot.png" TL_PANEL=battle TL_SEED=42 <godot> --path godot --rendering-driver opengl3

# headless 模擬（平衡調校主力工具，輸出 JSON 到 stdout）
TL_SIM=3000 TL_SEED=42 <godot> --headless --path godot

# 匯出 exe
<godot> --headless --path godot --export-release "Windows Desktop"
```

`<godot>` = **console 版**執行檔（才看得到 stdout/stderr），放 `tools/godot/`（gitignore）。

**測試鉤子鐵律**：
1. 任何 `TL_*` 存在時 → `SaveService.persist = false`（絕不寫壞使用者真實存檔）。
2. `TL_SHOT` 或 `TL_MUTE` 存在時 → 全域靜音。
3. **絕不在沒有測試鉤子的情況下開遊戲視窗做自動化驗證**——使用者可能正在工作。

跑完截圖要**親眼讀那張 png**，並回答「這張圖證明了什麼」。

---

## 專案結構

```
TheGame/
├── CLAUDE.md                  本檔
├── CHANGELOG.md               每版一節，倒序
├── docs/
│   ├── 00_CONCEPT.md          概念書（願景、紅線、風險評估）
│   ├── 10_GDD.md              遊戲設計文件（設計唯一權威；數值在 §7）
│   ├── 20_ART_DIRECTION.md    美術方向（token、字型、動效、音訊、素材管線）
│   ├── 30_TECH_DESIGN.md      技術設計（架構、確定性、存檔、鉤子、效能）
│   ├── 40_PRODUCTION_PLAN.md  生產計畫（里程碑、批次、風險、砍案）
│   └── 50_QA_PLAN.md          QA（五層梯、bug 登記、回歸清單）
├── tools/godot/               （gitignore）Godot console exe
└── godot/
    ├── scripts/core/          GameState / SaveService / Hooks / AudioBus / Rng
    ├── scripts/sim/     ★     FlowNetwork / Combat / WaveGen / MapGen / Score（純函式、零 RNG）
    ├── scripts/game/          BattleController / BuildController / SessionState
    ├── scripts/screens/       各畫面
    ├── scripts/render/        Palette / Shapes / Motion（美術 token 實作）
    ├── scripts/ui/            UiKit
    ├── scripts/meta/          TechTree / RosterData / TycoonSim
    ├── data/                  角色、敵人、關卡、訂單資料表
    ├── tests/                 flow / combat / save / determinism / balance_probe
    └── assets/audio/
```

---

## 每批工作的收尾（缺一不可）

1. 版本號 bump（`GameState.gd` 的 `VERSION`）
2. `CHANGELOG.md` 加一節
3. 自檢 L1–L3 並附證據（測試輸出／截圖路徑）
4. commit（標題含批次編號，如 `B0.3 建造與地圖：網格、節點放置、導管拉線`）
5. **可玩 build**——絕不讓主線處於「改到一半跑不起來」過夜
