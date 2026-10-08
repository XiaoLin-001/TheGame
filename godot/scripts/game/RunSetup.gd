extends RefCounted
## 開一局：把「這一局是什麼」變成一個設定好的 `SessionState`。B3.14 自 `screens/Battle.gd`
## 的 `_setup_session()` 抽出。
##
## **這是核心玩法的入口。** 畫面（2D 或日後的 3D）只決定「怎麼呈現」，
## 「這一局用哪張圖、帶哪些科技、蓋得出哪些節點、吃不吃名冊」全部在這裡——
## 所以它能在 `--script` 模式下不開視窗跑完一局（`tests/run_test.gd`）。
##
## **純函式、零副作用、不引用 autoload。** 存檔以參數傳入（畫面傳 `GameState.data`）。

const BuildController := preload("res://scripts/game/BuildController.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Loadout := preload("res://scripts/sim/Loadout.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const MapsData := preload("res://data/Maps.gd")
const RosterData := preload("res://data/Roster.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")

## 局的種類（`kind_of()` 的回傳值）。
const CAMPAIGN := "campaign"
const ENDLESS := "endless"
const DAILY := "daily"
const SANDBOX := "sandbox"   ## 測試圖／沙盤：沒有星等、沒有解鎖限制、不寫存檔


## `spec`（全部可省略）：
##   level        : Dictionary  戰役關卡（`data/Campaign.gd` 的一筆）；空 ＝ 不是戰役
##   endless_seed : int         無盡／每日的地圖種子；0 ＝ 不是
##   difficulty   : int         難度層（只有無盡帶得進來；戰役與每日恆為 0）
##   daily_board  : String      每日挑戰的榜（`Daily.UNIFORM`／自由）；"" ＝ 不是每日
##   sandbox      : bool        測試圖「靜水」（`TL_PANEL=sandbox`）
##   stress       : bool        壓力情境（`TL_STRESS`，只為了量渲染）
static func new_session(spec: Dictionary, save: Dictionary) -> RefCounted:
	var s: RefCounted = SessionState.new()
	var level: Dictionary = spec.get("level", {})
	var endless_seed: int = int(spec.get("endless_seed", 0))
	var difficulty: int = int(spec.get("difficulty", 0))
	var daily_board: String = String(spec.get("daily_board", ""))

	# ★ 局外科技（B1.3）。有測試鉤子時 `SaveService.persist=false` → 存檔是預設值
	#   → `unlocked` 為空 → mods 全中性，所以 `TL_*` 的任何一張截圖與任何一支自檢
	#   都不會因為這台機器上玩家買了什麼科技而改變（RG-61 的同一條紀律）。
	var meta := Loadout.of(save, difficulty)
	if not level.is_empty():
		s.setup(level["map"], level["unlocked"], meta)
	elif endless_seed != 0:
		# ★ 建造欄不再是「空陣列＝全部」（B2.4）。無盡與每日自由配置榜給的是
		#   **這名玩家的名冊**——招募池的三隻是抽到才有的，發給所有人等於沒有名冊。
		#
		# ★ 統一配置榜走一份**明列的固定清單**（`Daily.UNIFORM_BUILD`，§7.11）：
		#   它與玩家的任何進度與課金完全無關（憲法 B3），而「空陣列＝全部」會讓
		#   每加一隻角色就悄悄改變這張榜。這是 B2.2 記在 §7.11 的那筆債。
		#
		# ★ 兩榜的差異仍然**只在 `SessionState.setup()` 的參數**（§3.10 明文：
		#   不得為此拆成兩套邏輯）。同一張生成圖、同一套波次、同一支模擬。
		var build_list: Array = (
			Daily.UNIFORM_BUILD.duplicate() if daily_board == Daily.UNIFORM
			else RosterData.buildable(save)
		)
		# ★ 統一配置榜的**全部**局外成長由 `Daily.meta_for()` 一次歸零（憲法 B3）。
		#   一軸一道閘等於靠列舉守住憲法（`sim/Loadout.gd` 開頭）。
		s.setup(MapGen.generate(endless_seed), build_list, Daily.meta_for(daily_board, meta))
	elif bool(spec.get("stress", false)):
		# ★ 壓力情境（B1.7、RG-8）：只為了量渲染。模擬在畫面的 `_process` 裡凍結——
		#   這一份佈局的單 tick 要 30 秒（`perf_test.gd` 的說明），不凍結的話
		#   量到的會是模擬的耗時，而渲染一幀都畫不完。
		s.setup(MapsData.stress_map(), [], meta)
		s.ore = 9999999.0
		s.alloy = 9999999.0
		BuildController.apply_ops(s, MapsData.stress_ops())
		for i in MapsData.STRESS_ENEMIES:
			s.add_enemy(["drifter", "carapace", "ember"][i % 3])
		s.phase = "wave"
	else:
		s.setup(MapsData.SANDBOX if bool(spec.get("sandbox", false)) else MapsData.SHOAL, [], meta)
	return s


## 這個 spec 是哪一種局。結算、存檔寫哪一格、要不要星等都問它。
static func kind_of(spec: Dictionary) -> String:
	if not (spec.get("level", {}) as Dictionary).is_empty():
		return CAMPAIGN
	if int(spec.get("endless_seed", 0)) != 0:
		return DAILY if String(spec.get("daily_board", "")) != "" else ENDLESS
	return SANDBOX
