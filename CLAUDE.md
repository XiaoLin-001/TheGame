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
- **能量是流率，不是水池**：**沒有全域能量池**。唯一的跨 tick 儲存體是儲槽節點，**充放電受它自己那條導管的 `cap` 約束**。頂欄顯示的是「本 tick 供給／需求」，不是存量／容量。不得為了方便讓儲槽豁免導管上限——那等於偷偷退回水池模型。
- **導管基礎 `cap` 10 小於發電機輸出 20，是設計不是漏洞**：第一台發電機就會讓那條線滿載變色，用第二個建築教玩家讀瓶頸。加粗幹線（局內升級 +6/級 ×3 → 28）本身就是一個和「多蓋採集器」競爭的取捨。
- **優先權設在「節點類型」，不是單一節點**（5–8 條滑桿恆在同一位置；儲槽佔一格）。理由：不可暫停的戰術動作必須是一個手勢，而且操作負擔不得隨建築數量成長（R-1）。**★ B2.4 起新角色併進既有的列**（`NodeDefs.PRIORITY_GROUP`），滑桿恆為九條的子集——否則 M3 的 24 隻角色就是 28 條滑桿。合併只在 UI 層，`FlowNetwork` 仍逐 type 讀。
- **全域擊殺回收**：任何塔擊殺敵人回收其價值 **25%** 的礦砂。回收者的特殊能力是**射程內任何敵人死亡即回收 60% 為「能量」**（不限自己擊殺）。
- **礦砂↔能量匯率 1:5**（沿用發電機 4 礦砂→20 能量）。任何價值換能量的地方一律用它，不另發明數字。
- **路徑規則**：敵人路徑格**不可蓋節點**；導管**只能經由地圖指定的跨越點（橋）通過**。**橋是架高的 → 橋上導管不受攻擊**，是玩家可規劃的安全動線。橋的座數是關卡設計的主要刻度尺。
- **敵人是 walk-by**：**永不停步**，每 tick 傷害相鄰 1 格內的玩家建築，**只有核心會讓它們駐足**。不做「停下來攻擊」——那會讓便宜中繼變成肉盾，等於把砍案清單上的迷宮塔防裝回來。
- **不用隱藏係數調難度**：新手餘裕係數已刪除。難度只能用玩家看得見的關卡參數表達（敵人數量、礦點密度、核心距離、跨越點座數、該關宣告的準備期）。本作核心是「學會電力數學」，偷改物理＝教錯模型。
- **地圖尺度**：**戰役關卡硬性一屏可見**；只有無盡的程序生成圖可大過一屏（小地圖與導引隨之為必需，排 B2.1）。局內 HUD 是**全畫面地圖＋可收合浮層／抽屜**，不是三欄式。
- **塔＝角色**：全自動開火，射程內即攻擊，玩家不下戰鬥指令。生產與物流是另一套「建築」。
- **時間流**：純即時**不可暫停**；波與波之間有 45 秒準備期（可 4× 快進）；戰鬥期不可加速也不可減速。**局內選單（ESC）也不暫停**——面板上寫明「時間仍在走」。
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
- **GDScript 嚴格型別地雷**：泛型 `lerp()` 編譯錯 → 用 `lerpf()`；untyped array 的 `for` 變數要顯式型別；`match` 各分支共享作用域，變數名要唯一；**三元式產出的是 untyped `Array`**——`var a: Array[int] = [1,-1] if c else [-1,1]` 過得了編譯、**在執行期才炸**，而且炸在生成器裡的樣子是「礦點靜靜地變成 0 個」。
- **`data/` 與 `scripts/meta/` 的分界**（B2.7.2 補寫）：兩邊都是純函式、零副作用，差別在形狀——
  **`data/` 是一張表 ＋ 讀它的函式**（`NodeDefs`、`Tech`、`Levels`、`Achievements`、`Roster`、`Campaign`：
  加內容是**加一列**）；**`scripts/meta/` 是有狀態轉移的局外系統**（`TycoonSim`：accept / assign /
  accrue / collect / expand）。不確定時問自己：「新增一筆內容是加資料還是加一個動詞？」
- 存檔：`SaveService.SAVE_VERSION` 常數；讀取一律 `d.get(key, default)`；結構改動寫 `_migrate_sv<N>_to_sv<N+1>()`。**只增不破。**

---

## 跑與測（宣稱「能動」前先實際驗證）

```bash
# 新增腳本/資源後必跑（生成 .uid/.import，需一起 commit）
<godot> --headless --path godot --import

# 自動化測試（18 支：flow / build / combat / tide / save / determinism / hud / tech / audio / perf / campaign / endless / daily / blueprint / roster / tycoon / progress / difficulty）
<godot> --headless --path godot --script res://tests/flow_test.gd

# ★ 音源是程序生成的（B1.5）。改音色改腳本，**不要去修 wav**；改完要重新匯入。
python assetgen/gen_audio.py && <godot> --headless --path godot --import

# ★ 戰役五關的參考解實跑（最慢的一支，約 3 分鐘）——「這一關過得了」的唯一證據
<godot> --headless --path godot --script res://tests/campaign_test.gd

# ★ 效能（B1.7）：模擬走 perf_test（五關實測 ＋ 規模哨兵）；渲染走 TL_STRESS。
# TL_STRESS 的模擬是**凍結**的——那一份佈局單 tick 要 30 秒，不凍結就量不到渲染。
TL_STRESS=1 TL_MUTE=1 <godot> --path godot --rendering-driver opengl3

# ★ 文案稽核（B2.7.3）。規則在 `20_ART_DIRECTION.md` §3.5：**介面說事實，玩家自己下結論**。
# 基準：破折號 8 條（全是錯誤訊息的補救步驟）、開發代號 0 條、`**` 0 條。
cd godot && python ../qa/copy_extract.py && python ../qa/copy_tells.py

# 截圖驗證（自動靜音、約 3 秒後存圖並退出）
# TL_SHOT 存在時模擬凍結在 TL_DEMO_TICKS 那一格 → 同參數在任何機器上拍出同一張圖
TL_SHOT="C:/tmp/shot.png" TL_PANEL=battle TL_SEED=42 <godot> --path godot --rendering-driver opengl3

# 拍玩家真正的第一眼（TL_DEMO_TICKS=0 ＝ 不要示範佈局）
TL_SHOT="C:/tmp/first.png" TL_DEMO_TICKS=0 TL_PANEL=battle <godot> --path godot --rendering-driver opengl3

# ★ 戰役（B1.2）：TL_PANEL=campaign 是關卡選擇，加 TL_LEVEL=1..5 直接進那一關。
# 關卡的示範佈局＝該關的參考解，與 campaign_test 跑的是同一份腳本。
# ⚠ TL_DEMO_TICKS 是**從參考解跑完那一刻起算**的（參考解的 wait 已經推掉一批 tick）。
TL_SHOT="C:/tmp/lv.png" TL_PANEL=campaign TL_LEVEL=4 TL_DEMO_TICKS=1600 <godot> --path godot --rendering-driver opengl3

# ★ 每日挑戰（B2.2）：TL_PANEL=daily。種子是 YYYYMMDD，**有鉤子時日期固定為 2026-01-01**
# （否則同一組參數會因為今天是幾號而拍出不同的圖）。
TL_SHOT="C:/tmp/daily.png" TL_PANEL=daily <godot> --path godot --rendering-driver opengl3

# ★ 名冊（B2.4）：TL_PANEL=roster。存檔在有鉤子時是零進度 → 只有「錨」是你的，
# 其餘七張卡是暗的並寫著怎麼拿到。
TL_SHOT="C:/tmp/roster.png" TL_PANEL=roster <godot> --path godot --rendering-driver opengl3

# ★ 潮汐公司（B2.5）：TL_PANEL=tycoon 是**訂單板**。產線編輯不在 PANEL_SCREENS 上
# （兩個畫面、一條路），所以拍它要**配 clicktest ＋ TL_LEVEL=2**——自檢跑完之後
# 再往前一步開產線編輯。零進度的公司是空的，要看的是它忙起來的樣子。
TL_CLICKTEST=1 TL_SHOT="C:/tmp/ty_orders.png" TL_MUTE=1 TL_PANEL=tycoon <godot> --path godot --rendering-driver opengl3
TL_CLICKTEST=1 TL_SHOT="C:/tmp/ty_lines.png" TL_MUTE=1 TL_PANEL=tycoon TL_LEVEL=2 <godot> --path godot --rendering-driver opengl3
# ★ 「有券可招募」那一格**只有互動才到得了**（零進度沒券、抽完就畢業）。
# 兩個鉤子一起下 → 自檢跑完全部斷言之後把畫面留在那一格再拍。
TL_CLICKTEST=1 TL_SHOT="C:/tmp/roster_open.png" TL_MUTE=1 TL_PANEL=roster <godot> --path godot --rendering-driver opengl3

# ★ 局外成長（B1.3 科技樹 ＋ B2.7 等級軸）：TL_PANEL=tech。存檔在有鉤子時是預設值
# （研究數據 0、等級軸零級零材料），所以 clicktest 會自己先塞數據與材料再點——
# 不寫檔，玩家進度碰不到。★ 兩軸的卡片在捲動區**外面**，配 TL_CLICKTEST 才拍得到買過的樣子。
TL_CLICKTEST=1 TL_SHOT="C:/tmp/growth.png" TL_MUTE=1 TL_PANEL=tech <godot> --path godot --rendering-driver opengl3

# ★ 成就（B2.7）：TL_PANEL=achievements。零進度的清單是**全暗的**（那是誠實的，
# 但看不出東西），所以配 TL_CLICKTEST——它會塞一顆星進去讓第一條亮起來再拍。
TL_CLICKTEST=1 TL_SHOT="C:/tmp/ach.png" TL_MUTE=1 TL_PANEL=achievements <godot> --path godot --rendering-driver opengl3

# ★ 難度層（B2.6）：TL_PANEL=tiers 是無盡的入口（四張規則卡）。零進度時只有第 0 層
# 是開的，其餘三張寫著解鎖條件——那是誠實的，但看不到解鎖之後的樣子，
# 要看就配 TL_CLICKTEST（它會先把戰役塞成滿星、再塞一筆第 1 層的紀錄）。
TL_SHOT="C:/tmp/tiers.png" TL_PANEL=tiers <godot> --path godot --rendering-driver opengl3

# ★ 無盡（B2.1a）：TL_PANEL=endless 直接進一局程序生成圖（**第 0 層**，B2.6 之後仍不變
#   ——那些斷言驗的是局內的東西，不該因為前面多一個選擇畫面就要多按一顆鈕）。
# 種子走 Rng.next_seed()，所以**同一個 TL_SEED 開出的永遠是同一張圖**。
# ⚠ 生成器的幾何用截圖判不出來（說明浮層要放下第一個節點才收、格子只有 32px）。
#   要看路徑／橋／礦點的擺法，寫一支 --script 把 Maps.path_of() 印成 ASCII——
#   B2.1a 的兩個真缺陷（轉角廢橋、路徑貼邊）都是這樣才看到的。
TL_SHOT="C:/tmp/endless.png" TL_PANEL=endless TL_SEED=42 <godot> --path godot --rendering-driver opengl3

# ★ 拍特效近照（B1.6）：TL_FOCUS="x,y,zoom" 把鏡頭對到某一格並放大。
# 特效是 0.2 秒、十幾個像素的東西——在 fit 倍率的全圖截圖上判不出好壞，
# 沒有這個鉤子就會變成「宣稱做好了但沒真的看過」。
TL_SHOT="C:/tmp/fx.png" TL_PANEL=campaign TL_LEVEL=5 TL_DEMO_TICKS=581 TL_FOCUS="30,15,3" <godot> --path godot --rendering-driver opengl3

# ★ 輸入層自檢：用合成滑鼠事件真的點地圖（約 1 秒後自己退出，0 ＝ PASS）
# ⚠ 唯一不能 --headless 的檢查：dummy display server 不做 GUI 命中測試
TL_CLICKTEST=1 TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 關卡選擇畫面的同一件事（那個畫面的全部價值就是「一顆鈕點得到」）
TL_CLICKTEST=1 TL_PANEL=campaign TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 局外成長（科技解鎖鈕點得到、真的扣款、捲到底最後一顆鈕還在畫面內；
# 等級軸零材料時是關的、塞材料後升得了級、餘額真的少一級的價）
# ⚠ 等級軸「買不起」那一條要在**買科技之前**量——買下第一個科技會當場達成成就
#   「第一項科技」，15 材料立刻進帳（成就沒有領取鈕）。
TL_CLICKTEST=1 TL_PANEL=tech TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 成就（20 列全部建得出來、零進度時一條都沒有、達成的當下獎勵就在餘額裡、捲到底看得到最後一列）
TL_CLICKTEST=1 TL_PANEL=achievements TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 難度層（四張卡、零進度只開第 0 層、鎖著時說得出條件、解鎖階梯跳不過去、
# 出擊真的帶著那一層的倍率進局——不是只有「畫面開起來了」）
TL_CLICKTEST=1 TL_PANEL=tiers TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 每日挑戰（兩顆鈕點得到、種子是今天那一個、離線註記真的在畫面上）
TL_CLICKTEST=1 TL_PANEL=daily TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 名冊（招募鈕真的扣券、連抽三次不重複、畢業後再按也不扣、抽到的進得了建造欄）
# ★ 存檔在有鉤子時是零進度＝零券，所以自檢自己先把戰役塞成滿星再點——不寫檔。
TL_CLICKTEST=1 TL_PANEL=roster TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# ★ 潮汐公司（B2.5）：一整條循環——接單 → 產線編輯指派 → 回來 → 收成 → 擴廠
TL_CLICKTEST=1 TL_PANEL=tycoon TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 設定（音量真的接到匯流排、reduce_motion 當場生效、視窗真的變大再變回來）
TL_CLICKTEST=1 TL_PANEL=settings TL_MUTE=1 <godot> --path godot --rendering-driver opengl3
# 主選單（九顆鈕、ESC 往返、無盡那一顆真的開出生成圖）
# ★ on_screen 量的是**那一欄的每一個子節點**，不只是鈕——B2.5 只列舉鈕，
#   於是 B2.7 多一行字把版本號切出畫面時它照樣是綠的（RG-149）。
# ★ 斷言看的是**局面裡的地圖帶不帶 endless 旗標**，不是 `endless_seed` 有沒有值
#   ——後者在畫面已經用錯地圖之後才被設上一樣是 true（B2.1a 的假綠燈）
TL_CLICKTEST=1 TL_PANEL=title TL_MUTE=1 <godot> --path godot --rendering-driver opengl3

# 拍「只有互動才到得了」的狀態：驅動完 UI 之後不退出，交給 TL_SHOT
TL_CLICKTEST=1 TL_SHOT="C:/tmp/panels.png" TL_MUTE=1 <godot> --path godot --rendering-driver opengl3

# 可讀性驗收：隱藏所有數值標籤，只留線寬／顏色／三態徽章
TL_SHOT="C:/tmp/naked.png" TL_NAKED=1 TL_PANEL=battle TL_SEED=42 <godot> --path godot --rendering-driver opengl3

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

**誰判什麼**（`50_QA_PLAN.md` §0.1）：
- **你（agent）判程式碼完整性與可讀性**：L1–L3、測試、`TL_NAKED` 的視覺編碼檢定、資訊完備性。
- **使用者判好不好玩。** 不要替他判，也不要用「應該蠻有趣的」充數。
- **可讀性驗收一律用 `TL_NAKED=1`。** 拿有數字的截圖問「瓶頸在哪」是假綠燈——你讀得到那些數字，真人讀不到線寬。
- **判準寫「陌生人」「未受訓玩家」的項目，在拉到真人之前不得標記通過**（R-14）。

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
│   ├── 50_QA_PLAN.md          QA（五層梯、bug 登記、回歸清單）
│   └── agents/                外掛 skill 的設定（見「Agent skills」）
├── qa/copy_*.py               文案稽核（掃玩家字串 ＋ 比對 §3.5 的四條禁令）
├── assetgen/gen_audio.py      音源產生器（純 Python 標準庫；**音源的原始碼**）
├── tools/godot/               （gitignore）Godot console exe
└── godot/
    ├── scripts/core/          GameState / SaveService / Hooks / AudioBus / Rng
    ├── scripts/sim/     ★     FlowNetwork / Combat / WaveGen / MapGen / Score / Daily /
    │                          Loadout（局外成長進局的唯一入口）——純函式、零 RNG
    ├── scripts/game/          BattleController / BuildController / SessionState
    ├── scripts/screens/       各畫面
    ├── scripts/render/        Palette / Shapes / Motion（美術 token 實作）
    ├── scripts/ui/            UiKit
    ├── scripts/meta/          TycoonSim（純函式的**狀態機**）
    ├── data/                  節點、角色、敵人、地圖、戰役、科技、等級軸、成就、**難度層**資料表
    ├── tests/                 flow / build / combat / tide / save / determinism / hud / tech / audio / perf / campaign / endless / difficulty …
    └── assets/audio/          bgm/ 3 首、sfx/ 14 支（`assetgen/gen_audio.py` 生成）
```

---

## 每批工作的收尾（缺一不可）

1. 版本號 bump（`GameState.gd` 的 `VERSION`）
2. `CHANGELOG.md` 加一節
3. 自檢 L1–L3 並附證據（測試輸出／截圖路徑）
4. commit（標題含批次編號，如 `B0.3 建造與地圖：網格、節點放置、導管拉線`）
5. **★ 真的匯出 exe 並在 exe 上再驗一次**（`build/TideAndLine.exe`）——**每一次改動都要，不是只有大批次**（使用者 2026-08-06 明確要求）

```bash
<godot> --headless --path godot --export-release "Windows Desktop"
# 匯出完在 **exe 上**跑一輪 clicktest（不是在原始碼樹上）
TL_CLICKTEST=1 TL_PANEL=<panel> TL_MUTE=1 ./build/TideAndLine.exe --rendering-driver opengl3
TL_SHOT="C:/tmp/exe.png" TL_PANEL=title ./build/TideAndLine.exe --rendering-driver opengl3
```

> **為什麼要在 exe 上再跑一次，而不是信原始碼樹的綠燈**：匯出會**打包**資源
> （`export_filter="all_resources"`、`exclude_filter="tests/*"`）。新加的
> `.wav`／`.gd` 沒被打包進去時，**原始碼樹的測試全綠而 exe 缺檔**——而 `tests/`
> 本身不在包裡，headless 測試在 exe 上根本跑不到。exe 上唯一還在的驗證是
> clicktest（它寫在畫面自己裡面）與 `TL_SHOT`。截圖要**確認版本號是新的那一個**，
> 否則你看的是上一次的 exe。
>
> **絕不讓主線處於「改到一半跑不起來」過夜**，而且**沒有匯出的 build 不算交付**
> ——使用者玩的是 exe，不是我的 git 工作區。

---

## Agent skills

外掛 engineering skills（`to-tickets` / `triage` / `to-spec` / `qa` / `wayfinder` …）讀的設定。
**與本檔及 `docs/00`–`50` 衝突時，一律以本專案文件為準。**

### Issue tracker

GitHub issues（`gh` CLI）。**遠端尚未建立**——建法與 `--private` 的理由見 `docs/agents/issue-tracker.md`。
**批次 backlog 不搬到 issues**：`40_PRODUCTION_PLAN.md` 仍是里程碑排程的權威，
issues 給的是 bug、回鍋的點子、`/to-tickets` 拆出來的實作票。

### Triage labels

五個預設標籤（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。
**判準寫「好不好玩」「陌生人」的一律 `ready-for-human`**（§0.1 判官分工、R-14）。
見 `docs/agents/triage-labels.md`。

### Domain docs

Single-context，但**不建 `CONTEXT.md` 與 `docs/adr/`**——`docs/00`–`50` 已經在做同一件事。
詞彙讀 `10_GDD.md` §3、數值讀 §7、決策紀錄讀 §8 與 `CHANGELOG.md`。見 `docs/agents/domain.md`。
