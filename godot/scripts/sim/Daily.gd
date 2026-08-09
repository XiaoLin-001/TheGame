extends RefCounted
## 每日挑戰（`10_GDD.md` §3.10、§7.11；B2.2）。
##
## **純函式、零副作用、零系統時鐘。** 日期從呼叫端傳進來——`Time.get_date_*()`
## 是系統呼叫，放在這裡就等於讓「同一天全球同一張圖」取決於這支測試在幾點跑。
## 畫面層負責問今天是幾號（`Daily.today()` 在 `screens/` 那一側）。
##
## ── 這一批**不新增任何玩法**（§3.10「實作成本極低」）──────────────────
## 每日挑戰＝**無盡模式跑在一個固定的日種子上**，跑兩次、兩種起始配置。
## 地圖、波次、模擬、計分全部沿用 §7.10 那一套，一行都不改。
## 兩榜的差異**只在 `SessionState` 的初始化參數**（§3.10 明文：不得為此拆成兩套邏輯）。

const Loadout := preload("res://scripts/sim/Loadout.gd")

## 兩張榜的鍵。字串而不是 enum：它要進存檔，而存檔裡的數字之後沒有人看得懂。
const UNIFORM := "uniform"
const FREE := "free"
const BOARDS: Array[String] = [UNIFORM, FREE]

## 歷史保留幾筆。兩榜 × 15 天——再多也沒有人往下捲，而存檔要留給玩家的進度。
const HISTORY_MAX := 30


## 這一天的地圖種子。
##
## 就是 `YYYYMMDD` 本身，**不做雜湊混合**。理由有兩個：
##   ① 除錯時看得懂——「20260804」一眼知道是哪一天的圖，而一個混過的整數
##      要反查才知道。日種子會出現在錯誤回報與截圖檔名裡。
##   ② 混合買不到東西。`Rng.stream()` 底下是 PCG32，相鄰的種子本來就會長出
##      完全不同的序列；`daily_test` 直接斷言「連續 14 天的圖互不相同」。
##
## ⚠ **不要改用 `String.hash()`**：那是引擎的實作細節，換一版 Godot 就可能換一組
## 數字，而「同一天全球同一張圖」是一條跨版本的承諾（§3.10 接線上榜的前提）。
static func seed_of(y: int, m: int, d: int) -> int:
	return y * 10000 + m * 100 + d


## 存檔與 UI 用的日期鍵。`YYYY-MM-DD`，字典序＝時間序。
static func date_key(y: int, m: int, d: int) -> String:
	return "%04d-%02d-%02d" % [y, m, d]


## ★★ 這一榜帶得進去的局外成長。**統一配置榜拿到的是 `Loadout.NEUTRAL`。**
##
## 這是「與玩家的任何進度與課金完全無關」（憲法 B3）在程式碼裡**唯一的落點**：
## `SessionState.setup()` 的 `meta` 是這一局所有局外成長的入口，堵住它就堵住全部。
##
## ★ B2.7.1 之前這裡是一軸一支（`tech_for`／`levels_for`，B2.6 還要再加一支）。
##   **一軸一道閘等於靠列舉守住憲法**，而漏掉一道不會有任何東西報錯——
##   一條可以課金加速的軸就這樣洩進「對 P2W 的唯一制衡」那張榜。
##   現在是一道：新增一軸只要進 `Loadout.KEYS`，這裡不必動，而
##   `daily_test._uniform_gate_covers_every_axis()` 會列舉那些鍵逐一斷言。
##
## `daily_test` 另外拿三份進度／課金天差地遠的存檔開局，斷言 `state_hash()` 相同。
static func meta_for(board: String, player_meta: Dictionary) -> Dictionary:
	return Loadout.NEUTRAL.duplicate() if board == UNIFORM else player_meta


## ★ 統一配置榜的固定角色組（§3.10「固定角色組」、§7.11；B2.4 還的債）。
##
## **一份明列的清單，不是「空陣列＝全部」。** 後者在名冊落地的當下就會出事：
## 招募池的三隻是「抽到才有」，而「全部」會把它們發給這張榜上的每一個人——
## 那正好是憲法 B3（統一榜與玩家的任何進度與課金完全無關）要擋的東西，
## 而且**每加一隻新角色都會悄悄改變這張榜**，昨天的成績跟今天的不再可比。
##
## 內容 ＝ M1 結束時的全部十種（五種生產節點 ＋ 五隻確定性角色）。日後加角色
## **不動這一行**：要動它是一個賽季級的決定，該有版本註記，不是加一筆資料的副作用。
const UNIFORM_BUILD: Array[String] = [
	"extractor", "generator", "smelter", "relay", "silo",
	"anchor", "prism", "knell", "reclaimer", "breaker",
]


## 今天有沒有換日？換了就要把昨天的成績推進歷史、今天的兩榜歸零。
static func rolled_over(stored_date: String, today: String) -> bool:
	return stored_date != "" and stored_date != today


## 一筆歷史紀錄。欄位刻意和 `apply_daily()` 寫進去的那一份同構。
static func entry(date: String, board: String, wave: int, output: float) -> Dictionary:
	return {"date": date, "board": board, "wave": wave, "output": output}
