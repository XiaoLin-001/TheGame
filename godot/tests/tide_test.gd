extends SceneTree
## 敵潮：walk-by 破壞、橋的免疫、時間流（`10_GDD.md` §3.5、§7.1、§7.5、§7.6）。
##
## 這支測試鎖住的設計承諾：
##   RG-16 **橋（含引道）上的導管全程無損；貼路 1 格內的建築會被打壞；退 2 格無損**
##   RG-17 **敵人不因任何建築停步**——丟一排中繼擋不住任何一隻（防迷宮塔防後門）
##   §3.5 只有核心會讓它們駐足；核心歸零＝失敗
##   B5   準備期可快進、戰鬥期不可加速也不可減速
##
## 跑法：<godot> --headless --path godot --script res://tests/tide_test.gd

const T := preload("res://tests/_assert.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Maps := preload("res://data/Maps.gd")
const Enemies := preload("res://data/Enemies.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("tide_test")
	_blast_geometry(t)
	_bridge_immunity(t)
	_never_stops(t)
	_walk_by_breaks_lines(t)
	_two_cells_back_is_safe(t)
	_core_is_the_only_anchor(t)
	_wave_schedule(t)
	_phases_and_fast_forward(t)
	quit(t.report())


# ── 破壞半徑（純函式）──────────────────────────────────────────────────

func _blast_geometry(t: T) -> void:
	var e := Vector2i(10, 4)
	t.ok(Tide.in_blast(e, Vector2i(10, 5)), "破壞半徑：正下方 1 格中")
	t.ok(Tide.in_blast(e, Vector2i(11, 5)), "破壞半徑：斜角 1 格也中（Chebyshev）")
	t.ok(not Tide.in_blast(e, Vector2i(10, 6)), "破壞半徑：2 格外不中")
	t.ok(not Tide.in_blast(e, Vector2i(12, 4)), "破壞半徑：橫向 2 格外不中")


# ── ★ 橋的免疫含引道（`10_GDD.md` §3.5）──────────────────────────────

func _bridge_immunity(t: T) -> void:
	# 一條垂直穿過橫向路徑的導管，正好走跨越點 (22,4)。
	var cells := Build.line_cells(Vector2i(22, 2), Vector2i(22, 6))
	var crossings := {Vector2i(22, 4): true}
	var immune := Tide.immune_indices(cells, crossings)

	t.eq(cells.size(), 5, "橋線：(22,2)→(22,6) 共 5 格")
	t.ok(immune.has(2), "免疫：橋面那一格")
	t.ok(immune.has(1) and immune.has(3), "★ 免疫：**上下橋的引道也免疫**（跨越點 ±1）")
	t.ok(not immune.has(0) and not immune.has(4), "免疫：引道之外仍會挨打")

	# 敵人站在橋下的路徑格上——整條線一根寒毛都不能少。
	t.ok(
		not Tide.conduit_hit(cells, crossings, Vector2i(22, 4)),
		"★ RG-16：敵人正站在橋下，橋上導管**無損**"
	)
	t.ok(
		not Tide.conduit_hit(cells, crossings, Vector2i(21, 4)),
		"★ RG-16：敵人在橋旁邊一格，橋上導管仍無損（引道免疫在守這一格）"
	)
	# 免疫**不是**整條線的免死金牌：只涵蓋跨越點 ±1。
	# 一條 45° 上橋的線，遠端仍然貼著另一段路徑，那一段照打。
	var ramp := Build.line_cells(Vector2i(26, 5), Vector2i(30, 9))
	var vert := {Vector2i(30, 9): true}
	t.eq(Tide.immune_indices(ramp, vert).size(), 2, "45° 上橋：免疫橋面與它前面那格引道")
	t.ok(
		Tide.conduit_hit(ramp, vert, Vector2i(27, 4)),
		"★ 免疫不是無限延伸：這條線的遠端貼著橫向路徑，照樣挨打"
	)
	t.ok(
		not Tide.conduit_hit(ramp, vert, Vector2i(30, 8)),
		"★ 但它靠橋的那一端，敵人站在橋邊也打不到"
	)

	# 對照組：同樣穿過路徑，但**沒有走跨越點**。
	var bad := Build.line_cells(Vector2i(20, 2), Vector2i(20, 6))
	t.ok(
		Tide.conduit_hit(bad, crossings, Vector2i(20, 4)),
		"對照：不走橋的線在路徑上直接挨打"
	)


# ── ★ RG-17 永不停步（防迷宮塔防後門）────────────────────────────────

func _never_stops(t: T) -> void:
	var path_len := 40
	var p := 0.0
	for i in 10:
		p = Tide.advance(p, 1.0, path_len)
	t.near(p, 1.0, "推進：1.0 格/秒 × 10 tick = 1 格")

	# 同樣的輸入、同樣的結果——`advance()` 的簽章裡**根本沒有建築**，
	# 這比任何斷言都強：擋路這件事在型別層面就不可能發生。
	var s := _session()
	# 丟一排中繼貼著路徑（QA §4.6 的「中繼牆」）
	for x in range(12, 20):
		BuildController.place(s, "relay", Vector2i(x, 5))
	t.eq(s.count_of("relay"), 8, "中繼牆：8 個中繼貼在路徑旁")

	BattleController.start_wave(s)
	s.add_enemy("drifter")
	var e: Dictionary = s.enemies[0]
	for i in 200:  # 20 秒
		BattleController._advance_and_damage(s)
	t.near(
		float(e["progress"]), 20.0,
		"★ RG-17：20 秒走 20 格——**中繼牆一秒也沒擋住它**"
	)


# ── ★ walk-by 打斷產線（DoD）─────────────────────────────────────────

func _walk_by_breaks_lines(t: T) -> void:
	var s := _session()
	# 貼路徑的線：短、便宜、危險（§3.5）
	BuildController.place(s, "relay", Vector2i(14, 5))
	BuildController.place(s, "relay", Vector2i(18, 5))
	BuildController.lay_conduit(s, Vector2i(14, 5), Vector2i(18, 5))
	t.eq(s.conduits.size(), 1, "前置：貼路徑鋪了一條線")

	BattleController.start_wave(s)
	s.add_enemy("drifter")
	for i in 200:
		BattleController._advance_and_damage(s)
	t.eq(s.conduits.size(), 0, "★ DoD：行進中的敵人把貼路徑的導管打斷了")

	# ★ 一隻漂蟲打斷了線，卻打不死中繼——這不是 bug，是**暴露量隨長度成長**：
	#   中繼只有 3 格路徑打得到它（3 秒 × 8 = 24 < 30 血）；
	#   橫跨 5 格的導管有 7 格路徑打得到（7 秒 × 8 = 56 > 40 血）。
	#   「貼路徑走的線短、便宜、危險」（§3.5）在數字上就是這個形狀。
	t.eq(s.count_of("relay"), 2, "一隻漂蟲打不死中繼（3 秒 × 8 傷害 = 24 < 30 血）")
	t.near(float(s.node_at(Vector2i(14, 5))["hp"]), 6.0, "中繼剩 6 血——挨過打，但撐住了")

	s.add_enemy("drifter")
	for i in 200:
		BattleController._advance_and_damage(s)
	t.eq(s.count_of("relay"), 0, "★ 第二隻走過去，中繼就沒了")


func _two_cells_back_is_safe(t: T) -> void:
	var s := _session()
	# 退開 2 格：長、貴，但全程無損（§3.5 的空間取捨）
	BuildController.place(s, "relay", Vector2i(14, 6))
	BuildController.place(s, "relay", Vector2i(18, 6))
	BuildController.lay_conduit(s, Vector2i(14, 6), Vector2i(18, 6))

	BattleController.start_wave(s)
	s.add_enemy("drifter")
	for i in 400:
		BattleController._advance_and_damage(s)
	t.eq(s.conduits.size(), 1, "★ RG-16：退開 2 格的導管全程無損")
	t.eq(s.count_of("relay"), 2, "★ RG-16：退開 2 格的節點全程無損")
	t.near(float((s.conduits[0] as Dictionary)["hp"]), 40.0, "退 2 格：血量一點沒掉")


# ── ★ 只有核心會讓它們駐足（§3.5）────────────────────────────────────

func _core_is_the_only_anchor(t: T) -> void:
	var s := _session()
	BattleController.start_wave(s)
	s.add_enemy("drifter")
	var e: Dictionary = s.enemies[0]
	var last: int = s.path.size() - 1

	for i in 2000:  # 200 秒，遠超過走完全程需要的時間
		BattleController._advance_and_damage(s)
		if Tide.at_core(float(e["progress"]), s.path.size()):
			break
	t.ok(Tide.at_core(float(e["progress"]), s.path.size()), "抵達路徑終點（核心）")
	t.near(float(e["progress"]), float(last), "駐足：停在終點，不會走過頭")

	var before: float = s.core_hp()
	for i in 10:
		BattleController._advance_and_damage(s)
	t.ok(s.core_hp() < before, "★ 駐足後持續啃核心")

	# 一路啃到歸零 → 失敗
	for i in 20000:
		BattleController.step(s)
		if s.phase == "lost":
			break
	t.eq(s.phase, "lost", "★ 核心歸零觸發失敗")
	t.ok(s.core_hp() <= 0.0, "失敗時核心血量 ≤ 0")

	var ticks: int = s.tick_count
	BattleController.step(s)
	t.eq(s.tick_count, ticks, "失敗後模擬停住（不再空轉扣血）")


# ── 波次表（純函式、零 RNG）───────────────────────────────────────────

func _wave_schedule(t: T) -> void:
	var w: Array = Maps.waves_of(Maps.SHOAL)
	t.eq(w.size(), 5, "淺灘：5 波")

	var first: Array = Enemies.schedule(w, 0)
	t.eq(first.size(), 4, "第 1 波：4 隻")
	t.ok(
		first.all(func(x: Dictionary) -> bool: return x["type"] == "drifter"),
		"第 1 波只出漂蟲（§7.7 前兩關只出漂蟲）"
	)
	t.near(float(first[0]["at"]), 0.0, "第一隻在 0 秒出場")
	t.near(float(first[1]["at"]), 1.5, "第二隻在 1.5 秒（gap）")

	t.eq(
		Enemies.schedule(w, 0), Enemies.schedule(w, 0),
		"★ 同一波兩次產生完全相同的出場表（確定性，§2.4）"
	)
	t.eq(Enemies.schedule(w, 99).size(), 0, "越界的波次索引回空表，不當掉")
	t.eq(Enemies.schedule(w, 4).size(), 17, "第 5 波：8+5+4 = 17 隻")

	t.near(Enemies.endless_hp_scale(0), 1.0, "無盡：第 0 波血量係數 1.0")
	t.eq(Enemies.endless_count(9), 7, "無盡：count(9) = 4 + 3")


# ── 時間流（`10_GDD.md` B5、§7.1）────────────────────────────────────

func _phases_and_fast_forward(t: T) -> void:
	var s := _session()
	t.eq(s.phase, "prep", "開局是準備期")
	t.near(s.prep_time(), 60.0, "淺灘宣告的準備期 60 秒（PREP_TIME_TUTORIAL）")

	for i in 599:
		BattleController.step(s)
	t.eq(s.phase, "prep", "59.9 秒仍在準備期")
	BattleController.step(s)
	t.eq(s.phase, "wave", "★ 準備期結束自動開打")
	t.eq(s.wave_index, 1, "波次計數推進到 1")
	t.eq(s.speed_mult, 1, "★ 開打時快進強制歸 1（B5：戰鬥期不可加速也不可減速）")

	# 提前召喚＝在準備期主動開打
	var s2 := _session()
	BattleController.start_wave(s2)
	t.eq(s2.phase, "wave", "★ 提前召喚：準備期可主動開打")
	BattleController.start_wave(s2)
	t.eq(s2.wave_index, 1, "★ 戰鬥中再按沒有作用（連點防護，QA §4.2）")


# ── 小工具 ────────────────────────────────────────────────────────────

func _session() -> RefCounted:
	var s := SessionState.new()
	s.setup(Maps.SHOAL)
	s.ore = 100000.0
	return s
