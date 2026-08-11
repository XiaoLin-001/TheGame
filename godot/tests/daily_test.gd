extends SceneTree
## 每日挑戰雙榜（`10_GDD.md` §3.10、§7.11；B2.2）。
##
## 這支測試守的是**憲法 B3**：統一配置榜是對 P2W 的唯一制衡，
## 「與玩家的任何進度與課金完全無關」必須是一條斷言，不是一句承諾。
##
## 跑法：<godot> --headless --path godot --script res://tests/daily_test.gd

const Loadout := preload("res://scripts/sim/Loadout.gd")
const T := preload("res://tests/_assert.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const Tech := preload("res://data/Tech.gd")

## 掃幾天驗「同日同種子、異日異圖」。
const SWEEP := 14


func _initialize() -> void:
	var t := T.new("daily_test", 42)
	_seed_is_a_function_of_the_date(t)
	_uniform_ignores_progress(t)
	_free_uses_progress(t)
	_boards_share_one_map(t)
	_records_and_rollover(t)
	quit(t.report())


# ── ① 種子 ────────────────────────────────────────────────────────────

func _seed_is_a_function_of_the_date(t: T) -> void:
	t.eq(Daily.seed_of(2026, 8, 4), 20260804, "種子就是 YYYYMMDD（看得懂比混過好）")
	t.eq(Daily.date_key(2026, 8, 4), "2026-08-04", "日期鍵字典序＝時間序")
	# 同一天問幾次都一樣——這是「全球同一張圖」的最小條件。
	t.eq(Daily.seed_of(2026, 8, 4), Daily.seed_of(2026, 8, 4), "同日同種子")

	# ★ **不同天要長出不同的圖**，而且是真的不同，不只是種子不同。
	#   種子不混合的代價如果存在，會出現在這裡（相鄰種子生出幾乎一樣的圖）。
	var seen: Dictionary = {}
	for i in SWEEP:
		var sd := Daily.seed_of(2026, 8, 1 + i)
		var m: Dictionary = MapGen.generate(sd)
		# 把圖的骨架攤成一個字串來比：路徑、跨越點、礦點。
		var key := "%s|%s|%s" % [m["waypoints"], m["crossings"], m["ore"]]
		t.ok(not seen.has(key), "第 %d 天的圖沒有和前面任何一天重複" % (i + 1))
		seen[key] = true


# ── ② 憲法 B3：統一配置榜不吃任何進度 ────────────────────────────────

## 三份**天差地遠**的存檔：全新、科技買了一半、科技全開（＝課金到頂的極端）。
func _saves() -> Array[Dictionary]:
	var fresh := SaveService.defaults()
	var half := SaveService.defaults()
	var maxed := SaveService.defaults()
	var all: Array = []
	for i in Tech.count():
		all.append(String(Tech.NODES[i]["id"]))
	half["tech"] = {"unlocked": all.slice(0, all.size() / 2), "data": 300.0}
	maxed["tech"] = {"unlocked": all, "data": 9999.0}
	maxed["campaign"] = {"stars": {"shoal": 3}}
	maxed["endless"] = {"best_wave": 99, "best_output": 12.0}
	# ★ 等級軸也要在這份「天差地遠」的存檔裡（B2.7.1）——不放的話，
	#   下面那條 `state_hash()` 斷言只驗得到科技軸，而等級軸才是**可以課金的那一軸**。
	maxed["levels"] = {"tower": 10, "line": 10, "from_battle": 9999}
	return [fresh, half, maxed] as Array[Dictionary]


func _session(board: String, save: Dictionary, sd: int) -> RefCounted:
	var s: RefCounted = SessionState.new()
	s.setup(MapGen.generate(sd), [], Daily.meta_for(board, Loadout.of(save)))
	return s


## ★★★ 這一條就是 B3。三份存檔開出來的起始局面必須**逐位元相同**。
##
## 用 `state_hash()` 而不是逐欄比對：它涵蓋的是「權威狀態的全部」，
## 日後有人在 `SessionState` 加一個吃進度的欄位，這一條會自己變紅。
## 逐欄比對只會驗到寫測試那天想得到的那幾欄。
func _uniform_ignores_progress(t: T) -> void:
	var sd := Daily.seed_of(2026, 8, 4)
	var saves := _saves()
	var base: String = _session(Daily.UNIFORM, saves[0], sd).state_hash()
	for i in range(1, saves.size()):
		t.eq(
			_session(Daily.UNIFORM, saves[i], sd).state_hash(), base,
			"★ 統一配置榜：第 %d 份存檔開出來的起始局面與全新存檔完全相同（憲法 B3）" % (i + 1)
		)
	# 光看雜湊會漏掉一件事：`mods` 不進 `state_hash()`（它是查表結果不是狀態）。
	# 而 `mods` 正是科技生效的地方——所以另外釘一次。
	for i in saves.size():
		t.eq(
			_session(Daily.UNIFORM, saves[i], sd).mods, Tech.NO_MODS,
			"★ 統一配置榜：第 %d 份存檔的局內加成是中性值" % (i + 1)
		)


## 對照組。**沒有這一半，上面那條可以靠「兩榜都不吃科技」通過**——
## 那會把自由配置榜一起做壞掉，而且測試全綠。
func _free_uses_progress(t: T) -> void:
	var sd := Daily.seed_of(2026, 8, 4)
	var saves := _saves()
	var fresh: RefCounted = _session(Daily.FREE, saves[0], sd)
	var maxed: RefCounted = _session(Daily.FREE, saves[2], sd)
	t.eq(fresh.mods, Tech.NO_MODS, "前置：全新存檔在自由配置榜也是中性值")
	t.ok(maxed.mods != Tech.NO_MODS, "★ 自由配置榜：科技全開的存檔真的吃到了加成")


# ── ③ 兩榜共用同一套地圖與波次（§3.10「不得拆成兩套邏輯」）────────────

func _boards_share_one_map(t: T) -> void:
	var sd := Daily.seed_of(2026, 8, 4)
	var saves := _saves()
	var uni: RefCounted = _session(Daily.UNIFORM, saves[2], sd)
	var free: RefCounted = _session(Daily.FREE, saves[2], sd)
	t.eq(uni.map["size"], free.map["size"], "兩榜同一張圖（尺寸）")
	t.eq(uni.map["core"], free.map["core"], "兩榜同一張圖（核心）")
	t.eq(uni.sets["ore"].keys().size(), free.sets["ore"].keys().size(), "兩榜同一批礦點")
	t.eq(uni.path.size(), free.path.size(), "兩榜同一條路徑（＝同一波的秒數）")
	# 波次由 `map.seed` 推導，兩榜同種子 → 同一張出場表（§7.10）。
	BattleController.start_wave(uni)
	BattleController.start_wave(free)
	t.eq(
		uni.spawn_queue.size(), free.spawn_queue.size(),
		"★ 兩榜第一波的出場表一樣長（同種子同波次）"
	)
	t.eq(
		String((uni.spawn_queue[0] as Dictionary)["type"]),
		String((free.spawn_queue[0] as Dictionary)["type"]),
		"★ 兩榜第一隻敵人是同一種"
	)


# ── ④ 成績與跨日 ─────────────────────────────────────────────────────

func _records_and_rollover(t: T) -> void:
	var d := SaveService.defaults()
	var day1 := "2026-08-04"
	var day2 := "2026-08-05"

	var first := SaveService.apply_daily(d, day1, Daily.UNIFORM, 7, 3.5)
	t.ok(bool(first["wave"]) and bool(first["output"]), "第一次挑戰兩欄都是新紀錄")
	# 兩欄各自取最大值（與 `apply_endless` 同一條理由：撐得久 vs 產線好）。
	SaveService.apply_daily(d, day1, Daily.UNIFORM, 9, 1.0)
	var slot: Dictionary = d["daily"]["today"][Daily.UNIFORM]
	t.eq(int(slot["wave"]), 9, "波次刷新")
	t.near(float(slot["output"]), 3.5, "★ 產能沒有被一局「波次高但產線爛」洗掉")

	# 另一榜是獨立的一格。
	SaveService.apply_daily(d, day1, Daily.FREE, 2, 0.5)
	t.eq(int(d["daily"]["today"][Daily.UNIFORM]["wave"]), 9, "打自由配置不會動到統一配置")

	# ★ 跨日：昨天的兩榜推進歷史，今天歸零。
	SaveService.apply_daily(d, day2, Daily.FREE, 1, 0.1)
	var hist: Array = d["daily"]["history"]
	t.eq(hist.size(), 2, "★ 跨日把昨天的兩榜都推進歷史")
	t.eq(String((hist[0] as Dictionary)["date"]), day1, "歷史記的是昨天的日期")
	t.eq(
		int(d["daily"]["today"][Daily.UNIFORM]["wave"]), 0,
		"★ 跨日之後**沒玩的那一榜也要歸零**——昨天那個數字是在另一張圖上打的"
	)
	t.eq(int(d["daily"]["today"][Daily.FREE]["wave"]), 1, "今天玩的那一榜記上了")

	# 歷史有上限，而且丟的是最舊的。
	for i in Daily.HISTORY_MAX + 5:
		SaveService.apply_daily(d, "2026-09-%02d" % (i % 28 + 1), Daily.FREE, i + 1, 1.0)
	t.ok(
		(d["daily"]["history"] as Array).size() <= Daily.HISTORY_MAX,
		"歷史不會無限長（上限 %d）" % Daily.HISTORY_MAX
	)

	# 舊存檔讀進來要長出這一格，而且不動原有資料（只增不破）。
	var old := {"sv": 2, "tech": {"unlocked": ["dmg1"], "data": 5.0}}
	var norm := SaveService.normalize(old)
	t.ok(norm.has("daily"), "舊存檔讀進來自動長出 daily 這一格")
	t.eq(int((norm["daily"] as Dictionary)["today"][Daily.UNIFORM]["wave"]), 0, "初值 0")
	t.eq(
		((norm["tech"] as Dictionary)["unlocked"] as Array).size(), 1,
		"★ 補鍵不動玩家原有的資料"
	)
