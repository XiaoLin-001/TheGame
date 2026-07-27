# 《潮與線》技術設計

> 架構、存檔、測試鉤子與效能的權威文件。
> 上位文件：`00_CONCEPT.md`、`10_GDD.md`、`20_ART_DIRECTION.md`。
> 狀態：**v0.2**（依 `10_GDD.md` v0.3 收斂：儲槽解算語意、優先權依類型、`TL_NAKED` 鉤子、版本編號修正）　|　最後更新：2026-07-27

---

## 1. 引擎選型

**選定：Godot 4.7，`gl_compatibility` 渲染後端，Windows Desktop 匯出。**

| 理由 | 說明 |
|---|---|
| 2D 效能足夠 | 本作無 3D 需求；`gl_compatibility` 體積小、相容性最好、老機器也跑得動 |
| 程序繪製友善 | `_draw()` API 與 `CanvasItem` shader 完全滿足 `20_ART_DIRECTION.md` §6 的零素材管線 |
| 工具鏈已驗證 | 同一套工具鏈（console exe、headless 測試、截圖鉤子、SystemFont CJK）已在既有專案出貨驗證 |
| GDScript 適合純函式模擬 | 模擬層可寫成無副作用純函式，天生可 headless 測試 |
| 匯出單一 exe | 符合交付形式 |

**不選 Unity/Unreal**：3D 引擎的體積與複雜度對純 2D 專案是純負擔。
**不選 Web/HTML5**：本作的模擬密度（數百節點 × 10 tick/秒）與長時遊玩（30 分/局）在瀏覽器上有風險，且交付形式已定為 exe。

**手機移植預留**：Godot 原生支援 Android / iOS 匯出，引擎層面無阻礙。真正的成本在 UI 與操作（`20_ART_DIRECTION.md` §1.3b 的 P1–P4 條款）、廣告 SDK 接入、帳號與雲端存檔、上架流程。**架構預留不代表承諾移植**（`00_CONCEPT.md` 風險 5）。

### 1.1 工具鏈

- 使用 **console 版**執行檔（`Godot_v4.7-stable_win64_console.exe`）才看得到 stdout/stderr。放 `tools/godot/`（gitignore）。
- 常用指令：

```bash
<godot> --headless --path godot --import                          # 新增腳本/資源後必跑（生成 .uid/.import，需一起 commit）
<godot> --headless --path godot --script res://tests/<name>.gd    # 自動化測試
<godot> --headless --path godot --export-release "Windows Desktop"
```

---

## 2. 架構

### 2.1 分層原則

```
┌─────────────────────────────────────────────────────────────┐
│  scenes/ + scripts/screens/   ── 畫面層（Godot 節點、UI）      │
│  只做「呈現」與「收使用者輸入」，不含規則                        │
├─────────────────────────────────────────────────────────────┤
│  scripts/game/                ── 局內遊戲層（狀態機、輸入轉指令）│
│  把玩家操作翻譯成模擬層的指令；擁有當前局的狀態                   │
├─────────────────────────────────────────────────────────────┤
│  scripts/sim/          ★★★  ── 模擬層（純函式、零副作用、零 RNG）│
│  FlowNetwork / Combat / WaveGen / Score                      │
│  同輸入必同輸出。這是確定性、可重播、可驗證榜單的地基             │
├─────────────────────────────────────────────────────────────┤
│  scripts/core/                ── 服務層（autoload）           │
│  GameState / SaveService / Hooks / AudioBus / Rng            │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 目錄結構

```
TheGame/
├── CLAUDE.md
├── CHANGELOG.md
├── docs/                       00–50 五份權威文件
├── tools/godot/                （gitignore）Godot console exe
└── godot/
    ├── project.godot           設定 + autoload 註冊
    ├── scripts/
    │   ├── core/               GameState.gd / SaveService.gd / Hooks.gd / AudioBus.gd / Rng.gd
    │   ├── sim/          ★     FlowNetwork.gd / Combat.gd / WaveGen.gd / MapGen.gd / Score.gd
    │   ├── game/               BattleController.gd / BuildController.gd / SessionState.gd
    │   ├── screens/            Title / MainMenu / Battle / Result / TechTree / Roster / Tycoon / Settings
    │   ├── render/             Palette.gd / Shapes.gd / Motion.gd   （美術 token 實作）
    │   ├── ui/                 UiKit.gd（共用 UI helpers，static）
    │   └── meta/               TechTree.gd / RosterData.gd / TycoonSim.gd
    ├── data/                   角色、敵人、關卡、訂單的資料表（.json 或 .tres）
    ├── tests/                  flow_test.gd / combat_test.gd / save_test.gd / determinism_test.gd
    └── assets/audio/
```

### 2.3 狀態擁有權

- **`GameState`（autoload）擁有跨局的持久狀態**：科技樹、名冊、tycoon、設定、紀錄。
- **`SessionState`（非 autoload）擁有當前局的狀態**：網路拓樸、資源、波次、敵人。局結束即銷毀。
- 畫面層**以引用**取得狀態，**不得持有副本**。
- **讀檔時原地變更**（`clear()` + `append_array()` / `merge()`），**絕不重新賦值容器**——重新賦值會讓已持有引用的面板拿到斷裂的舊物件。

### 2.4 確定性（★ 硬性要求）

**`scripts/sim/` 下的所有模擬必須是純函式且零系統 RNG。** 這是三件事的共同地基：

1. **每日挑戰榜的公平性**：全球同種子必須產生完全相同的局面。
2. **重播與驗證**：日後接線上榜時，伺服器需能以「種子 + 操作序列」重現分數。
3. **自動化測試**：測試能斷言精確數值，而非「大概差不多」。

**規則**：

| 規則 | 說明 |
|---|---|
| 禁用 `randf()` / `randi()` / `Time.get_ticks_*()` 於 `sim/` | 一律改用注入的 `Rng`（seeded `RandomNumberGenerator`）或確定性替代（hash、閾值、輪替） |
| 固定時間步 | 模擬以固定 `TICK = 0.1s` 推進，**不使用 `delta`**。畫面掉幀時補跑 tick，不改變模擬結果 |
| 浮點紀律 | 模擬層的累加運算固定順序（依節點 id 排序後遍歷），避免容器迭代順序造成的浮點差異 |
| 序列化 | `SessionState` 可完整序列化為 JSON；`(種子, 初始配置, 操作序列)` 三元組即可完整重現一局 |

**驗證方式**：`tests/determinism_test.gd`——同一組 `(seed, ops)` 跑兩次，斷言最終狀態雜湊完全相同。此測試在每批工作結束時必跑。

### 2.5 流量網路解算器（核心演算法）

**模型**：有向圖上的**容量受限比例分配**，非最大流演算法（過重且不符玩法直覺）。

**每 tick 的解算步驟**（依資源種類各跑一次）：

```
1. 收集：遍歷節點（依 id 排序），計算各自的 supply 與 demand
   - 儲槽：本 tick 淨供需為正 → 它是 demand（充能）；為負 → 它是 supply（放電）
2. 傳播：由供給節點沿出邊做 BFS 分配
   - 每條邊的可用量 = min(上游剩餘, edge.cap)
   - 下游多個需求者競爭時，按「優先權權重」等比例分配
     weight_i = priority_i / Σ priority
     ★ priority 讀的是「節點類型」的值，不是節點自己的欄位（GDD §3.1）
3. 削減：任一節點 satisfaction = 實得 / demand
   - 生產節點：產出 × satisfaction
   - 塔：射速 × satisfaction（不停火，見 GDD §3.3）
4. 回寫：每條邊記錄 flow，供渲染層讀取（線寬 = 2 + 6 × flow/cap）
```

**★ 儲槽（Silo）的解算語意**（GDD §3.1「能量是流率不是水池」）：

**沒有全域資源池。** 唯一的跨 tick 儲存體是儲槽節點，它是解算圖上的一個普通節點，只是會換邊站：

| 全網狀態 | 儲槽角色 | 速率上限 |
|---|---|---|
| 盈餘（supply > demand） | **消費者**，吸收剩餘充能，吃自己類型的優先權權重 | `min(剩餘容量, 自己那條導管的 cap)` |
| 赤字（demand > supply） | **供給者**，放電補缺口 | `min(當前充能, 自己那條導管的 cap)` |

**兩條硬性後果**：① 儲槽的**擺放位置有意義**——遠了、幹線沒加粗，它的電就趕不到前線；② 一座 300 容量的儲槽接在基礎 cap 10 的導管上，最多只放得出 10/秒，無法填補 23/秒的缺口（GDD §7.2 的取捨即由此而來）。**不得為了方便而讓儲槽豁免導管上限**——那等於偷偷退回全域水池模型。

**兩者都是純資料**：儲槽的 `charge` 存在 `SessionState`，由解算器的回傳值更新，解算器本身仍是純函式（`solve(nodes, edges, priorities) -> deltas`）。

**★ 放電只補缺口**（B0.2 實作時補齊的語意）：即使導管 cap 放得出更多，儲槽本 tick 的放電量也**以全網赤字為上限**（多座儲槽按各自可放電率等比例分攤）。否則多出來的電會流進網路卻無人可用，表現成「儲槽掉得比赤字還快」的無故漏電。
**充能則不封頂**：充能中的儲槽是**普通消費者**，照自己類型的優先權去搶——「充能搶不搶得贏熔爐」是玩家的戰術決定（GDD §3.1），不由解算器代為裁決。

**環路處理**：圖允許有環（玩家可以接回去）。解算採**單次前向傳播 + 迭代收斂上限 3 次**，超過即接受近似值。理由：完全收斂在有環圖上可能不穩定，而 3 次迭代在玩法上已無可感知誤差，且保證每 tick 的計算量有上界。

**傳播的實作形狀**（B0.2）：每次迭代先算出每個節點的「順著出邊還送得到多少需求」（`reach`，受各邊殘餘 cap 截斷；遇環即止步，交給下一次迭代），再依 `reach × 優先權` 分配上游手上的量。**已被認領的需求會即時從 `reach` 扣掉**，否則同一份下游需求會被兩個上游各服務一次。
**已知近似**：極少數拓樸下，資源可能流進中繼節點後無處可去（下游需求在同一迭代內被其他分支先吃掉），該份量留在原地不再前進。這是上面那條「3 次迭代後接受近似值」的具體長相，不是缺陷。

**複雜度**：`O(V + E)` × 3 次迭代 × 資源種類數。500 節點／2000 邊／3 種資源 ≈ 22,500 次基本運算/tick，10 tick/秒 → 完全在預算內。

**為什麼不做實體物品搬運**：Factorio 式的物品實體模擬複雜度是 `O(物品數)`（可達數萬），效能與確定性都會成為長期負債，且不符極簡幾何美術。流量模型在**視覺上更清楚**（線的粗細直接表達吞吐）、在**玩法上更聚焦於拓樸與取捨**，這正是本作要的。

---

## 3. 存檔設計

| 項目 | 決策 |
|---|---|
| 格式 | JSON，`user://save.json`（Windows：`%APPDATA%/Godot/app_userdata/TideAndLine/`） |
| 版本常數 | `SaveService.SAVE_VERSION`（int），置於 `scripts/core/SaveService.gd` 頂部 |
| 讀取紀律 | **一律 `d.get(key, default)`**，任何欄位缺失都必須有安全預設 |
| 遷移 | 結構性改動寫 `_migrate_sv<N>_to_sv<N+1>()` 分支，鏈式套用。**只增不破**（紅線層級的承諾） |
| 備份 | 寫檔採「寫入 `.tmp` → 驗證可讀 → 原子改名」，避免寫壞主檔 |
| 自動存檔 | 局末結算後、tycoon 收成後、設定變更後。**局內不自動存檔**（局內狀態不持久化，失敗重來即可，符合紅線 R1） |
| 多存檔槽 | M3 前不做，但 schema 預留 `slots` 陣列外層結構 |

**存檔內容**（v1 schema 骨架）：

```json
{
  "sv": 1,
  "company_level": 1,
  "tech": { "unlocked": ["conduit_1"], "data": 0 },
  "roster": { "owned": ["anchor","prism"], "tokens": 0 },
  "campaign": { "cleared": [], "stars": {} },
  "endless": { "best_wave": 0, "best_score": 0 },
  "daily": { "2026-07-27": { "score": 0, "wave": 0 } },
  "tycoon": { "level": 1, "credit": 0, "components": 0, "lines": [], "last_seen_unix": 0 },
  "levels": { "towers": {}, "nodes": {} },
  "entitlements": { "purchases": [], "no_ads": false, "pass_season": 0, "pass_owned": false },
  "blueprints": [],
  "settings": { "master": 0.8, "bgm": 0.6, "sfx": 0.8, "reduce_motion": false }
}
```

**`daily` 欄位存兩榜成績**：`{ "2026-07-27": { "unified": {...}, "free": {...} } }`（統一配置榜／自由配置榜）。

**購買驗證的固有限制**：離線單機的存檔可被本機竄改，`entitlements` 無法在客戶端可靠防偽。這是桌面 F2P 的結構性限制，**不在 M0–M3 處理**；M4 接平台 API（Steam Inventory 等）時，以平台收據為權威來源，本機 `entitlements` 降為快取。**不要為此在早期批次做加密或混淆——那只會增加除錯痛苦而擋不住任何真正想改的人。**

**離線結算**（tycoon 掛機）：以 `last_seen_unix` 與當前時間差計算，**但上限為倉儲容量**。時間差為負（使用者改系統時鐘）時視為 0，不獎勵也不懲罰。

---

## 4. 測試與鉤子

### 4.1 環境變數鉤子（第一批就要建的基建）

| 鉤子 | 作用 |
|---|---|
| `TL_SHOT=<png絕對路徑>` | 渲染數秒後截圖存檔並自動退出（截圖驗證的地基） |
| `TL_SHOT_DELAY=<秒>` | 截圖前等待秒數，讓動效跑完（預設 3） |
| `TL_PANEL=<畫面名>` | 直接開啟指定畫面，跳過導航（`battle` / `tech` / `roster` / `tycoon` / `settings`） |
| `TL_MUTE=1` | 全域靜音 |
| `TL_SEED=<int>` | 覆寫隨機種子，用於重現特定局面 |
| `TL_SIM=<ticks>` | **headless 模擬**：不開視窗，跑 N 個 tick 後把 `SessionState` 摘要以 JSON 輸出到 stdout 並退出。平衡調校與回歸測試的主力工具 |
| **`TL_NAKED=1`** ★ | **隱藏所有數值標籤**（頂欄數字、節點數值、優先權面板刻度、tooltip），只留圖形——線寬、顏色、節點三態徽章。**R-3 可讀性驗收專用**（見下） |

**★ `TL_NAKED` 存在的理由**（B0.6 起生效）：

R-3 的硬性驗收是「未受訓玩家能在 30 秒內指出瓶頸節點」。這條驗收的**判官是 Opus 5**（使用者只負責判斷好不好玩，agent 只驗程式碼與可讀性）。但 agent 讀得到截圖上的「能量 40/63 ⚠」「▲12/s」，拿一般截圖問它會**必過**——它答對的是「我讀得懂數字」，不是 R-3 要驗的「線寬與顏色本身在傳達資訊」。

`TL_NAKED=1` 把數值全部關掉，於是問題變成純視覺編碼的檢定：

```bash
TL_SHOT="C:/tmp/naked.png" TL_NAKED=1 TL_PANEL=battle TL_SEED=42 <godot> --path godot --rendering-driver opengl3
# 然後把 naked.png 交給 Opus 5：「哪個節點塞住了？」
# 答對 = 視覺編碼承載了資訊；答錯 = 線寬／顏色沒在傳達，要改，不是換個問法
```

**兩條硬性規則**：

1. **任何 `TL_*` 鉤子存在時，`SaveService.persist = false`**——測試絕不寫壞使用者的真實存檔。
2. **`TL_SHOT` 或 `TL_MUTE` 存在時自動全域靜音**——絕不在使用者可能正在工作時發出聲音。

**標準截圖驗證跑法**：

```bash
TL_SHOT="C:/tmp/shot.png" TL_PANEL=battle TL_SEED=42 <godot> --path godot --rendering-driver opengl3
```

跑完**親眼讀那張 png** 核對版面。`err=0` 才算存檔成功。

### 4.2 自動化測試

| 測試 | 內容 |
|---|---|
| `tests/flow_test.gd` | 流量網路解算：容量削減、優先權分配、環路收斂、飢餓比例 |
| `tests/combat_test.gd` | 傷害計算、護甲／屏障減免、能量不足時的射速縮放 |
| `tests/save_test.gd` | 存檔往返、缺欄位預設、各版本遷移分支 |
| `tests/determinism_test.gd` | ★ 同 `(seed, ops)` 兩次跑出相同狀態雜湊 |
| `tests/balance_probe.gd` | 用 `TL_SIM` 跑標準關卡 N 波，輸出經濟曲線供人工核對 |

**GDScript 測試地雷**：`--script` 模式**不載入 autoload**。因此 `tests/*.gd` 不得 `preload` 任何引用 autoload 的腳本。這反過來要求 `scripts/sim/` 的核心邏輯必須是**自足的純函式**——正好與 §2.4 的確定性要求一致。

### 4.3 GDScript 已知地雷（照抄，全部炸過真專案）

1. 嚴格型別下泛型 `lerp()` 編譯錯 → 用 `lerpf()`；untyped array 的 `for` 變數要顯式型別（`for x: float in arr`）；`var x := CONST_ARRAY[i]` 推成 Variant，需 cast；`match` 各分支共享作用域，變數名要唯一。
2. 十六進位字面量超過 `0x7FFFFFFFFFFFFFFF` 直接溢位報錯 → hash 常數改寫成有號十進位。
3. CJK 字型：Godot 預設字型無中文，**一律 `SystemFont`**，否則豆腐字。
4. 程序生成的全彩貼圖：`modulate = WHITE` + `TEXTURE_FILTER_NEAREST`，不要再染色。
5. 主腳本會長到數千行，動它先 Grep 定位，不整檔讀。

---

## 5. 效能預算

| 指標 | 目標 | 最低可接受 |
|---|---|---|
| 幀率 | 60 FPS @1280×720 | 不低於 45 FPS |
| 壓力情境 | 500 節點 ／ 2000 導管 ／ 200 敵人同屏，維持 60 FPS | — |
| 模擬耗時 | 單 tick < 3ms（10 tick/秒 → CPU 佔用 < 3%） | < 8ms |
| 記憶體 | < 400 MB | < 700 MB |
| exe 體積 | < 80 MB | < 150 MB |
| 冷啟動到主選單 | < 3 秒 | < 6 秒 |
| 最低規格 | Windows 10 64-bit、雙核 2.0GHz、4GB RAM、支援 OpenGL 3.3 的內顯 | — |
| **行動參考**（移植前的預算，非承諾） | 中階 Android（2020 年後、4GB RAM）維持 30 FPS；壓力情境降為 250 節點／1000 導管／100 敵人 | — |

**每個里程碑的壓力情境測試**同時記錄桌面實測值與「模擬層單 tick 耗時」——後者是行動端可行性的主要指標（渲染可以降級，模擬不能）。

**效能策略**：
- 模擬層與渲染層解耦：模擬固定 10 Hz，渲染 60 Hz **以插值呈現**（導管粗細、敵人位置在 tick 之間補間）。
- 導管渲染批次化：同色同寬的線合併為單一 `draw_multiline`。
- 敵人不使用獨立 `Node2D`：以資料陣列 + 單一 `_draw()` 批繪，避免數百節點的場景樹開銷。
- 每個里程碑結束跑一次壓力情境並記錄數據到 `50_QA_PLAN.md`。

---

## 6. 版本與分支

- **版本常數**：`scripts/core/GameState.gd` 頂部的 `const VERSION := "0.1.0"`，設定面板顯示。**這是未來任何人盤點進度的第一手依據。**
- **版本規則（★ 2026-07-27 修正）**：`0.<全域批次序號>.<修補>`，一路遞增到 Gold 才 bump 為 `1.0.0`。

  | 批次 | VERSION | | 批次 | VERSION |
  |---|---|---|---|---|
  | B0.1 | `0.1.0` | | B1.1 | `0.8.0` |
  | B0.7 | `0.7.0` | | B4.6 | `0.37.0` → Gold `1.0.0` |

  *原規則寫「M1 起 `1.x.y`、Gold 為 `1.0.0`」，但四個里程碑之後版本號回不到 1.0.0——自相矛盾，已改為單調遞增的 pre-1.0 慣例。批次序號全域連續，不因里程碑重置，這樣 `VERSION` 一眼就能對回 `40_PRODUCTION_PLAN.md` §2 的第幾批。*
- Git：`main` 為主線，**每批工作以一個 commit 收尾**，commit 標題含批次編號。
- 每批收尾必做：版本號 bump ＋ `CHANGELOG.md` 一節 ＋ 可玩 build。
