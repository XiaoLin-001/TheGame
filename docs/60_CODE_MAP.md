# 《潮與線》程式碼地圖

> 給接手的人。回答三件事：**這個遊戲靠哪些程式碼才跑得起來**、**想砍／想改某個功能會碰到哪裡**、**某件事該去哪個檔案**。
> 上位文件：`10_GDD.md`（設計）、`30_TECH_DESIGN.md`（架構）。本檔是它們的**索引**，不是新規則。
> 一律用**函式名**指路（行號會漂）。檔案行數與依賴出自 `python qa/gd_graph.py`——數字過期時重跑它，不要手改。
> 最後更新：B3.14（v0.43.0）。

---

## 1. 一張圖：資料怎麼流

```
 玩家輸入 ─► Battle._gui_input ─► BuildController.place / lay_conduit / upgrade* / demolish*
                                          │（合法性判斷在 sim/Build.gd，這裡只管錢與落地）
                                          ▼
                                   ┌─ SessionState ─┐   局的狀態：nodes、conduits、enemies、ore/alloy、phase…
                                   └───────▲────────┘   （純資料 ＋ 查詢；局結束即銷毀，不進存檔）
                                           │ 就地變更
 每幀 Battle._process ── 累積 delta ──► BattleController.step ◄── 每 0.1 秒一個 tick（固定時間步，不吃 delta）
        step 的順序是有意義的：
          _phase（準備期倒數／出怪）→ Combat.engaged（誰在射程內）→ _edges（導管→有向邊）
          → FlowNetwork.solve ×3（礦砂 → 能量 → 合金；能量要吃礦砂的滿足率）
          → Combat.auras → _advance_and_damage（Tide：敵人 walk-by）→ _fire → _end_of_wave → _write_rates

 SessionState ─► Stage2D._draw*（畫世界）   ─┐
              ─► hud/* 的 refresh_*（讀 s.rates）├─ 只讀，不改局面
              ─► Feedback（狀態差值 → 音效、死因）┘
 局結束 ─► hud/ResultPanel ─► SaveService.apply_*（星等、研究數據、紀錄）─► user://save.json（原子寫入）
```

**一條規則撐起整個架構**：`scripts/sim/`、`data/`、`scripts/meta/` 是純函式層——不依賴畫面、不用系統 RNG、
不讀時鐘。所以模擬能在 headless 跑一萬次得到同一個 `state_hash()`（每日挑戰、重播、可驗證榜單的地基）。
`python qa/gd_graph.py --layers` 守著它：目前 0 條違規。

---

## 2. 分級：砍了會怎樣

「砍」的意思是**把那個檔案（或那段邏輯）拿掉**。分四級，由重到輕：

| 級 | 意思 | 砍掉的後果 |
|---|---|---|
| **T0 脊椎** | 沒有它遊戲開不起來，或核心循環不成立 | 載入失敗／整個玩法不存在 |
| **T1 核心規則** | 鎖定的設計（`CLAUDE.md`「鎖定的設計」）住在這些函式裡 | 遊戲跑得起來，但**不再是這個遊戲** |
| **T2 功能模組** | 一個獨立的玩家功能（科技樹、潮汐公司、每日挑戰…） | 主選單少一顆鈕；要改幾個接點，詳見 §2.3 |
| **T3 呈現層** | 畫面、音效、動效 | headless 模擬照跑，但玩家看不見東西 |
| **T4 開發輔助** | 測試鉤子、自檢、工具 | 一般遊玩完全不受影響 |

> ⚠ **「載入層級」與「功能層級」不同。** `Main.gd` 在檔案頂端 `preload` 了每一個畫面，所以
> `python qa/gd_graph.py --cut data/Achievements.gd` 會報「遊戲開不起來」——那只是說 `Main.gd` 與
> `SaveService.gd` 還引用著它，**不是**說成就是脊椎。要真的拿掉一個 T2 功能，照 §2.3 的接點表改。

### 2.1 T0 脊椎（64 個 runtime 檔、約 19,000 行裡真正承重的）

| 檔案 | 行 | 角色 | 為什麼砍不得 |
|---|---:|---|---|
| `scenes/Main.tscn` ＋ `scripts/screens/Main.gd` | 628 | 啟動場景、標題、主選單、`TL_PANEL` 路由（`PANEL_SCREENS`） | 沒有它沒有入口 |
| `scripts/core/Hooks.gd` `Env.gd` | 185／86 | autoload：測試鉤子的執行者；`Env.any_hook()` 是**存檔保護**（有鉤子時不落地） | 拿掉 `any_hook()` 的判斷，任何自動化都會寫壞真實存檔 |
| `scripts/core/GameState.gd` | 51 | autoload：`VERSION`、`data`（持久資料的唯一持有者） | 所有畫面都讀它 |
| `scripts/core/SaveService.gd` | 507 | autoload：存檔（`SAVE_VERSION`、`migrate`、原子寫入） | 進度全在這；**只增不破** |
| `scripts/core/Rng.gd` | 49 | autoload：種子的唯一擁有者 | 每日挑戰／無盡的確定性 |
| `scripts/core/AudioBus.gd` | 235 | autoload：匯流排、靜音、播放 | 16 個檔案引用它；靜音是鐵律 2 的落地 |
| `scripts/game/SessionState.gd` | 364 | 局的狀態 ＋ `state_hash()` | 模擬的唯一狀態擁有者 |
| `scripts/game/BattleController.gd` | 762 | **每 tick 的解算迴圈** `step()` | 沒有它沒有遊戲 |
| `scripts/game/BuildController.gd` | 422 | 玩家操作 → 對局面的變更（錢、落地） | 沒有它蓋不了任何東西 |
| `scripts/sim/FlowNetwork.gd` | 644 | 流量網路解算器 | 全案的心臟（見 §2.2 ①②） |
| `scripts/sim/Combat.gd` `Tide.gd` `Build.gd` `Clock.gd` `Score.gd` | 189／113／272／17／66 | 戰鬥計算、敵潮、建造規則、固定時間步、結算數學 | 純函式；每一支都有 headless 測試鎖住 |
| `data/NodeDefs.gd` `Enemies.gd` `Maps.gd` | 301／421／292 | 節點、敵人、地圖的**資料表** | 數值唯一來源是 `10_GDD.md` §7，這裡是它的實作 |
| `scripts/screens/Battle.gd` ＋ `screens/battle/*` | 693 ＋ 約 5,300 | 局內畫面 | 玩家的唯一操作介面（舞台 `Stage2D` 是 T3，但沒有它看不見局面） |
| `scripts/render/Palette.gd` `scripts/ui/UiKit.gd` | 166／306 | 色值唯一來源、CJK 字型與主題 | 拿掉就是豆腐字與錯色（`Color(` 字面量是缺陷） |

### 2.2 T1 核心規則：設計鎖在哪幾行

這張表是「**要動這個設計之前，先問使用者**」（`CLAUDE.md` 鎖定設計）的程式碼對照。

| 鎖定的設計 | 它在哪 | 砍／改了會怎樣 |
|---|---|---|
| **① 塔在交戰時每秒吃電，待機 0**（全案的心臟） | `Combat.engaged()`（只看幾何：射程內有沒有敵人）→ `BattleController._solve_power()` 的 `engage_power` 分支；`NodeDefs` 每座塔的 `engage_power`（`power_in` 刻意是待機＝0） | 拿掉＝塔不再和產線搶能量，「同一份能量餵塔還是餵產線」這個取捨消失 |
| **② 能量是流率不是水池；儲槽受導管 `cap` 約束** | `FlowNetwork.solve()`（`charge`／`capacity`／`charge_delta`）；`BattleController._edges()`（每條導管展開成兩條帶 `cap` 的有向邊）；`Build.CAP_BASE=10 < 發電機 20`（**設計不是漏洞**）、`conduit_cap()` | 讓儲槽豁免 `cap`＝偷偷退回水池模型；「峰值電力」約束失效 |
| **③ 供不應求按比例降速，不停機** | `FlowNetwork.solve()` 的滿足率；`Combat.shots()` 把滿足率直接乘進射速累加器；`_solve_power` 發電機產出 × 礦砂滿足率 | 改成停機＝雪崩（一個缺口讓整網死鎖） |
| **④ 不變量：採集器無輸入需求 → 全域不可能死鎖** | `NodeDefs`（`extractor` 沒有 `ore_in`／`power_in`）；`BattleController._solve_ore()` | 新增一種「採集器也要吃東西」的節點會破壞這條 |
| **⑤ 優先權設在「節點類型」；滑桿恆為九條** | `NodeDefs.DEFAULT_PRIORITY`／`PRIORITY_ROWS`／`PRIORITY_GROUP`；`FlowNetwork.solve(…, priorities, …)`；`hud/PriorityPanel.gd` | 改成每座建築一條＝操作負擔隨建築數量成長（R-1）。合併只在 UI 層，`FlowNetwork` 仍逐 type 讀 |
| **⑥ 全域擊殺回收 25% 礦砂；回收者 60%→能量；匯率 1:5** | `BattleController._on_kill()`；`Combat.salvage_ore()`／`reclaim_power()` | 回收者變成淨耗電＝「打破峰值約束的鑰匙」成了假的 |
| **⑦ 敵人 walk-by：永不停步，只有核心讓它們駐足** | `BattleController._advance_and_damage()`（先打相鄰 1 格再繼續走）；`Tide.advance()`／`at_core()`／`in_blast()` | 改成「停下來攻擊」＝便宜中繼變肉盾，迷宮塔防的後門打開 |
| **⑧ 橋是架高的，橋上導管免疫** | `Tide.immune_indices()`；`Build.can_place()`（路徑格禁節點）／`can_connect()`（導管只能經由跨越點） | 橋的座數是關卡設計的主要刻度尺 |
| **⑨ 固定時間步 0.1s；純即時不可暫停；準備期可 4× 快進、戰鬥期不可加速** | `Clock.TICK`；`Battle._process()`（累積 delta、每個 tick 呼叫 `step`）；`BattleController.start_wave()`／`_end_of_wave()` 把 `speed_mult` 在戰鬥期鎖回 1；`hud/MenuLayer`（選單也不暫停） | 用 `delta` 推模擬＝確定性消失 |
| **⑩ 確定性：同一組 (seed, ops) 必得同一個 `state_hash()`** | `SessionState.state_hash()`；`scripts/sim/` 零系統 RNG（`gd_lint` 規則 3）；`tests/determinism_test.gd` | 每日挑戰公平性、重播、榜單全部依賴它 |
| **⑪ 不用隱藏係數調難度** | 沒有「新手餘裕」係數；難度只在關卡參數（`data/Maps.gd`／`Campaign.gd`）與難度層（`data/Difficulty.gd`）——玩家看得見的 | 偷改物理＝教錯模型（本作核心是學電力數學） |
| **⑫ 戰役關卡一屏可見** | `Stage.FRAME`（框架恆定）＋ `Stage2D.reset_view()`（進場自動 fit）；`Shapes.fit_zoom()`；`campaign_test` 斷言每關 fit 後填滿框架 | 地圖尺寸變成受畫面限制 |
| **⑬ tycoon 是附屬補給站；UI 深度上限兩個畫面** | `scripts/meta/TycoonSim.gd`（純函式、不讀時鐘）；`screens/TycoonOrders.gd` → `TycoonLines.gd` | 長成第二個遊戲＝紅線 |
| **⑭ 統一配置榜與玩家進度／課金完全無關** | `Daily.UNIFORM_BUILD`（**明列**的十種）、`Daily.meta_for()`、`sim/Loadout.gd`（局外成長進局的**唯一入口**）；`roster_test`／`daily_test` | 一軸一道閘等於靠列舉守住憲法，漏一道不會報錯——所以只有一道 |
| **⑮ 失敗只花時間（R1）、無體力值（R2）** | 沒有任何「重試券」「體力」欄位；`SaveService.defaults()` 不存這類東西 | 紅線 |

### 2.3 T2 功能模組：想整塊拿掉，要改這些接點

每個功能都是「資料表／純函式（一個檔）＋ 畫面（一個檔）＋ 主選單一顆鈕 ＋ 存檔裡一個區段」。
**接點**＝拿掉它時必須同時改的外部引用（`python qa/gd_graph.py --why FILE` 現場查）。

| 功能 | 檔案 | 外部接點 | 對遊戲其餘部分的影響 |
|---|---|---|---|
| **潮汐公司（tycoon）** | `meta/TycoonSim.gd`、`screens/TycoonOrders.gd`、`TycoonLines.gd` | `Main.gd`（`PANEL_SCREENS["tycoon"]`、主選單鈕、`_tycoon_progress`）；`SaveService`（`tycoon` 區段）；`Achievements`／`Roster` 的材料與券來源 | 升級材料與招募券少一個來源——**塔防不依賴 tycoon**（設計鎖定），其餘照跑 |
| **成就** | `data/Achievements.gd`、`screens/Achievements.gd` | `Main.gd`；`SaveService.components()` 向它問材料獎勵；`Roster` 向它問券。成就是**推導的**（存檔其他欄位 ≥ 門檻），沒有自己的存檔區段 | 少一批獎勵；存檔不受影響 |
| **名冊與招募** | `data/Roster.gd`、`screens/Roster.gd` | `Main.gd`；`Battle._setup_session()`（無盡／自由榜的建造欄吃名冊）；`SaveService` | 無盡的建造欄回到「全部」；**會改變無盡的玩法**（B2.4 已知變更） |
| **難度層** | `data/Difficulty.gd`、`screens/Tiers.gd` | `SessionState.setup()`（三層倍率乘在 `mods` 上）；`TopBar`／`ResultPanel`（顯示層數）；`Achievements`／`Roster` | 無盡只剩第 0 層 |
| **每日挑戰** | `sim/Daily.gd`、`screens/DailyScreen.gd` | `Main.gd`；`Battle._setup_session()`；`ResultPanel`（寫成績）；`SaveService`（`daily`） | 少一個競技場；統一配置榜是對 P2W 的**唯一制衡**（設計鎖定，不得移除） |
| **無盡模式** | `sim/MapGen.gd`、（`Enemies.endless_schedule`） | `Battle._setup_session()`；`Main.gd`；`Tiers`；`DailyScreen` | 每日挑戰跟著失去地圖——它們共用同一個生成器 |
| **藍圖庫** | `sim/Blueprint.gd`、`hud/BlueprintPanel.gd` | `BuildController.blueprint_*`；`Stage2D`（落點預覽）；`SaveService`（`blueprints`）；`Battle`（`bp_*` 狀態、`Mode.BLUEPRINT`） | 少一顆建造欄鈕 |
| **科技樹／等級軸** | `data/Tech.gd`、`data/Levels.gd`、`screens/Tech.gd`、`sim/Loadout.gd` | `SessionState.setup()`（`mods` 的來源）；`SaveService`；`BlueprintPanel`（槽數）；`Campaign` | `mods` 恆為中性值——模擬照跑，局外成長消失 |
| **戰役** | `data/Campaign.gd`、`data/Levels.gd`、`screens/Campaign.gd` | `Main.gd`；`SaveService.apply_result`；`Roster`（券來自星數）；`Achievements` | 沒有關卡可玩（無盡與測試圖仍可） |
| **設定畫面** | `screens/Settings.gd` | `Main.gd`；`hud/MenuLayer`（局內選單開它）；`GameState.apply_settings()` | 沒有音量／解析度／減少動態效果 |

### 2.4 T3 呈現層

| 區段 | 檔案 | 說明 |
|---|---|---|
| **舞台（2D）** | `screens/battle/Stage.gd`（契約）、`Stage2D.gd`（視野、拾取、繪圖）、`StageLayer.gd`（快取圖層） | 畫面層只認 `Stage.gd` 的契約；**2D→3D 要換掉的就是這一塊**（見 `70_3D_MIGRATION.md`）。**繪圖拆成快取層**：路徑與網格整局不重畫、導管與節點逐件只在簽章變了才重畫（`30_TECH_DESIGN.md` §5.4）——**新增一個會改動畫面的建造動作要在 `SessionState.rev` 加一** |
| 舞台（傾斜，B4.1／B4.2） | `screens/battle/Stage3D.gd`（約 800 行）：內嵌 `Stage2D` 當地面貼圖 ＋ 3D 地形／建築／敵人／徽章；傾斜控制在 `Battle`（左上角「3D」鈕與滑桿、右鍵拖曳、Shift＋滾輪）；`TL_STAGE=2d｜3d`、`TL_TILT=<度>`；**玩家實玩預設用它，自動化預設平面** | 使用者指定的「俯瞰 2D → 側視 3D」；`tests/stage3d_test.gd` 是契約與造型的驗收尺，`tests/gallery_shot.gd` 是看造型的陳列照工具 |
| 開機速度（B4.4） | `screens/BattleLoader.gd`（延後載入局內畫面，標題一出來就 `ResourceLoader.load_threaded_request` 預取）；`Hooks._run_sim()` 的 `load()`（不 `preload`）；`Battle.SELFTEST_PATH`（測試鉤子執行者只在有 `TL_*` 時載入） | `Main`／`Campaign`／`Tiers` 不再 `preload` `Battle.gd`——`preload` 會在載入那支腳本時把整個局內（約 2/3 的腳本行數）編譯完，玩家先等完才看得到標題 |
| 自動化的視窗（B4.4） | `qa/desk.py`（`CreateDesktop` 私有桌面）；`qa/check.py` 的 `_godot()` 走它 | 視窗開在另一個 Windows 桌面物件上：不出現在使用者的螢幕、不搶焦點；`--position` 沒用（Godot 夾回螢幕內）、`--headless` 沒有 GL |
| 覆蓋層 | `screens/battle/Overlay2D.gd` | 能量列、小地圖、邊緣箭頭——螢幕座標，只問舞台契約 |
| HUD | `screens/battle/hud/*.gd`（11 個面板） | 全是 2D `Control` |
| 3D 美術生成器 | `render/3d/`：`Extrude`（積木＋烘焙光照＋徽章）、`Models`（十四種建築與六種敵人的配方、敵人的動作參數）、`Relief`（梯田地形、懸崖、擺設）、`Wires`（導管的路徑與實例資料、單位方盒）、`Fx3D`（特效與血條的幾何） | 純函式，輸出網格；吃與 2D 同一組級數步數與機制欄位；顏色全來自 `Palette` 的材質色票 |
| 2D 美術生成器 | `render/2d/`：`Glyphs`（節點幾何）、`Foes`（敵人幾何）、`Terrain`（地貌）、`TitleBackdrop`、`Batch`（同色圖形併成一個指令） | 純函式，輸出幾何；3D 要寫對應的網格生成器 |
| 效能量測 | `core/Prof.gd`（`TL_PROF`）、`qa/check.py perf`、`SelfTest.stress_frame()` | 逐段計時、引擎渲染 CPU／GPU、draw call；T4，一般遊玩閒置 |
| 共用美術 token | `render/Palette.gd`（色值）、`Motion.gd`（時長階、`reduce_motion`）、`Shapes.gd`（格大小 `GRID`、`fit_zoom`、線形 helper） | 維度無關（`Shapes` 的繪圖 helper 是 2D 的，`GRID`／`fit_zoom` 不是） |
| 音訊 | `core/AudioBus.gd`、`screens/battle/Feedback.gd`、`assets/audio/`（`assetgen/gen_audio.py` 生成） | 音源是**程序生成的**：改音色改腳本，**不要修 wav** |

### 2.5 T4 開發輔助（一般遊玩閒置）

`screens/battle/SelfTest.gd`（約 1400 行：`TL_CLICKTEST`／`TL_STRESS`／示範佈局）、`core/Hooks.gd` 的 `TL_SIM`／`TL_SHOT`、
`tests/`（22 支 headless ＋ 輔助）、`qa/`、`dev/`、`assetgen/`。匯出時 `exclude_filter="tests/*"`——
**所以 headless 測試在 exe 上跑不到**，exe 上唯一還在的驗證是 `clicktest` 與 `TL_SHOT`（見 `CLAUDE.md` 每批收尾）。

---

## 3. 依賴方向與已知的耦合

```
screens/ ──► game/ ──► sim/ ──► data/          （箭頭＝可以依賴；反過來不行）
   │           │         ▲
   │           └─► meta/ │
   └─► render/ ─┐        │
        ui/ ◄───┘        └─ core/（autoload：Hooks、Rng、AudioBus、SaveService、GameState）
```

**已驗證**（`python qa/gd_graph.py --layers`）：`sim/`、`data/`、`meta/` 沒有任何一條往上的依賴。

**已知的耦合（不是缺陷，但接手的人會撞到）**：

1. **`SaveService` 認得每個功能**：它的 `defaults()` 為每個 T2 功能各留一個區段，並 `preload` 了 `Daily`／`Blueprint`／`Score`／
   `Roster`／`Achievements`／`Levels`。所以「整塊拿掉一個功能」永遠要同時改存檔——這是持久層的本質，不是壞設計。
2. **`Main.gd` 是全部畫面的註冊處**（`PANEL_SCREENS` 與九顆主選單鈕）。新增畫面＝加一列表 ＋ 一顆鈕 ＋ 一條 clicktest。
3. **`BattleController` 依賴 `render/Motion`**：`Motion.ticks()` 讀 `reduce_motion`，決定要不要生成純渲染的碎片爆
   （`_burst`／`_shield`）。這些記錄**不進 `state_hash()`**，所以不影響確定性；但它是模擬層裡唯一讀到「玩家設定」的地方。
4. **外界讀 `Battle` 的欄位**：`Campaign`／`Tiers`／`DailyScreen`／`Main` 只做 `new()` → 指派
   `level`／`endless_seed`／`difficulty`／`daily_board`／`daily_date`／`on_exit` → `add_child()`；
   `Tiers` 的 clicktest 讀 `battle.s`，`Campaign` 的讀 `battle.menulayer.menu_layer`。改這些名字要一起改那幾處。
5. **局內畫面的模組靠「同名欄位」接線**（`Battle._wire_modules()`）：模組想用另一個模組，就在自己身上宣告一個**同名欄位**；
   主畫面對號入座。欄位名就是 `Battle.gd` 頂端的那些變數名（`stage`、`topbar`、`inspector`…）。

---

## 4. 想做某件事，去哪裡

| 我想… | 去 | 注意 |
|---|---|---|
| 調數值（造價、射速、血量、耗能） | `data/NodeDefs.gd`／`Enemies.gd`／`Maps.gd`／`Campaign.gd`，**先**改 `10_GDD.md` §7 | 數值不在程式碼裡即興發明 |
| 加一種節點／塔 | `NodeDefs`（一列）＋ `render/2d/Glyphs.gd`（圖形）＋ `hud/CodexPanel`（簡介）＋ 測試 | `TL_CLICKTEST` 的 `glyph` 段會逼你補圖形（B2.4.6：沒有圖形的塔是隱形的） |
| 加一種敵人 | `Enemies`（一列）＋ `render/2d/Foes.gd`（圖形，**由機制欄位推導**，不新增美術欄位） | |
| 加一個關卡 | `Campaign.gd`（一筆，含**參考解**）＋ `Maps.gd`（地圖） | `campaign_test` 會真的跑參考解（約 3 分鐘）——「這一關過得了」的唯一證據 |
| 改建造規則 | `sim/Build.gd`（純函式，回傳原因碼）＋ `game/BuildController.gd`（文案） | 規則不放在 UI 的 if 裡 |
| 加一個 HUD 面板 | `screens/battle/hud/` 新檔 ＋ `Battle._build_modules()`／`_modules()`／`_field_of()` 各一行 ＋ `_build_ui()` 排位置 | 加入順序就是繪圖順序與命中順序 |
| 加一個畫面 | `screens/` 新檔 ＋ `Main.gd`（`PANEL_SCREENS`、主選單鈕）＋ clicktest | 先看 `CLAUDE.md` 的 `TL_PANEL` 慣例 |
| 改存檔結構 | `SaveService`：`SAVE_VERSION` ＋ `_migrate_svN_to_svN+1()` | **只增不破**；讀取一律 `d.get(key, default)` |
| 加測試鉤子 | `Env.HOOKS` ＋ `Hooks.gd`／消費端；`gd_lint` 規則 8 會檢查有沒有列 | 有鉤子時存檔不落地 |
| 換成 3D | `docs/70_3D_MIGRATION.md` | 先讀 §1 要使用者拍板的決定 |
