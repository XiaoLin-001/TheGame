extends SceneTree
## 效能：模擬層單 tick 耗時（B1.7、`30_TECH_DESIGN.md` §5）。
##
## **量的是模擬，不是渲染**，因為那是行動端可行性的主要指標——渲染可以降級
## （少畫幾條線、關掉動效），模擬不能：它就是規則本身。渲染那一半走 `TL_STRESS=1`。
##
## 這支測試分兩層：
##   ① **戰役五關的參考解 ＋ 40 隻敵人 ＝ M1 真正的負載**。這一層有斷言，
##      因為它是「這一版能不能出」的門。
##   ② **規模哨兵**只印不擋預算，只擋數量級——它的用途是
##      「下一次有人動了解算器，有沒有把成本整整齊齊地放大十倍」。
##
## ★ RG-8（500 節點／2000 導管／200 敵人 @60FPS）**目前不通過**，已改排 B2.1
##   並登記為風險 R-17。傳播的拜訪次數是 `O(迭代 × (V+E)²)` 級，要壓下來得換掉
##   `FlowNetwork._reach` 的估計方式——**那會動到分配比例**，得連五關的難度校準
##   一起重做，不是 M1 驗收該順手做的事。
##
## 跑法：<godot> --headless --path godot --script res://tests/perf_test.gd

const T := preload("res://tests/_assert.gd")
const Maps := preload("res://data/Maps.gd")
const Campaign := preload("res://data/Campaign.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

## §5 的兩條線。**斷言掛在「最低可接受」上**，目標值只印出來——
## 把目標當紅線會讓一台比較慢的機器把測試變成擲骰子。
const BUDGET_MS := 3.0
const MAX_MS := 8.0

## 局內同屏敵人數的實務上限（五關最大一波約 20 隻，這裡取兩倍當餘裕）。
const ENEMIES := 40

## 規模哨兵的大小與護欄。這個毫秒數**不是預算**，是數量級的哨兵。
const CANARY := Vector2i(8, 8)
const CANARY_MAX_MS := 2000.0


## ★ 無盡大圖的規模曲線（B2.1b）。節點間隔 2 格，三個規模。
## 上限**不是預算**，和哨兵一樣只擋數量級——R-17 是已登記、未修的風險。
const ENDLESS_STEPS := [Vector2i(10, 6), Vector2i(18, 11), Vector2i(31, 19)]
const ENDLESS_MAX_MS := 20000.0


func _initialize() -> void:
	var t := T.new("perf_test", 28)
	_campaign_levels(t)
	_scaling_canary(t)
	_endless_scale(t)
	quit(t.report())


func _ms(s: RefCounted, reps: int) -> float:
	# 暖身：第一次跑會付掉一次性的配置成本，混進平均值會虛報。
	for _i in 3:
		BattleController.step(s)
	var t0 := Time.get_ticks_usec()
	for _i in reps:
		BattleController.step(s)
	return float(Time.get_ticks_usec() - t0) / float(reps) / 1000.0


## ① M1 真正的負載：五關的參考解，每關灌 40 隻敵人。
func _campaign_levels(t: T) -> void:
	var worst := 0.0
	for i in Campaign.count():
		var lv: Dictionary = Campaign.at(i)
		var s: RefCounted = SessionState.new()
		s.setup(lv["map"], lv["unlocked"])
		s.ore = 999999.0
		s.alloy = 999999.0
		var ops: Array = []
		for op: Array in lv["demo"]:
			if String(op[0]) in ["place", "conduit", "upgrade", "priority"]:
				ops.append(op)
		var fails: Array = BuildController.apply_ops(s, ops)
		# 蓋不起來的參考解量到的是一個空網路，然後宣稱效能沒問題（B1.3 同一課）。
		t.ok(fails.is_empty(), "第 %d 關參考解蓋得起來（失敗 %d）" % [i + 1, fails.size()])
		for k in ENEMIES:
			s.add_enemy(["drifter", "carapace", "ember"][k % 3])
		s.phase = "wave"
		var ms := _ms(s, 40)
		worst = maxf(worst, ms)
		print("[PERF] 第 %d 關　節點 %3d／導管 %3d／敵人 %d → %6.2f ms/tick%s" % [
			i + 1, s.nodes.size(), s.conduits.size(), s.enemies.size(), ms,
			"" if ms <= BUDGET_MS else "　⚠ 超出目標 %.0f ms" % BUDGET_MS
		])
		t.ok(ms < MAX_MS, "第 %d 關單 tick < %.0f ms（實際 %.2f）" % [i + 1, MAX_MS, ms])
	if worst > BUDGET_MS:
		print("[PERF] ⚠ 最重的一關 %.2f ms 超出目標 %.0f ms（仍在上限 %.0f 內）——記在 §5" % [
			worst, BUDGET_MS, MAX_MS
		])


## ② 規模哨兵。**只擋數量級**，不擋預算。
func _scaling_canary(t: T) -> void:
	var s: RefCounted = SessionState.new()
	s.setup(Maps.stress_map())
	s.ore = 9999999.0
	s.alloy = 9999999.0
	var fails: Array = BuildController.apply_ops(s, Maps.stress_ops(CANARY.x, CANARY.y))
	t.ok(fails.is_empty(), "哨兵佈局蓋得起來（失敗 %d）" % fails.size())
	var ms := _ms(s, 5)
	print("[PERF] 規模哨兵　節點 %3d／導管 %3d（無敵人）→ %7.1f ms/tick" % [
		s.nodes.size(), s.conduits.size(), ms
	])
	t.ok(ms < CANARY_MAX_MS, "哨兵 < %.0f ms（實際 %.1f）——超過代表解算器的數量級跑掉了" % [
		CANARY_MAX_MS, ms
	])


## ③ ★ 無盡大圖（B2.1b）。這一層要回答的是 **R-17 到底從幾個節點開始痛**，
## 所以印的是一條規模曲線，不是單一個數字。
##
## 佈局刻意是「玩家真的會蓋出來的形狀」——節點間隔 2 格、**只往右與往下接**
## （分支度約 4）。壓力情境（RG-8）的分支度是 7.5，那是量測台不是玩法；
## 拿它來回答「大圖能不能玩」會高估成本，而高估和低估一樣沒有用。
func _endless_scale(t: T) -> void:
	for step: Vector2i in ENDLESS_STEPS:
		var s: RefCounted = SessionState.new()
		s.setup(MapGen.generate(42))
		s.ore = 9999999.0
		s.alloy = 9999999.0
		var path: Dictionary = s.sets["path"]
		var ore: Dictionary = s.sets["ore"]
		var size: Vector2i = s.map["size"]
		var grid: Dictionary = {}
		var ops: Array = []
		for gy in step.y:
			for gx in step.x:
				var c := Vector2i(2 + gx * 2, 2 + gy * 2)
				if c.x >= size.x or c.y >= size.y or path.has(c) or ore.has(c):
					continue
				grid[Vector2i(gx, gy)] = c
				var i := gy * step.x + gx
				ops.append(["place", "anchor" if i % 9 == 0 else (
					"generator" if i % 7 == 0 else "relay"
				), c])
		# ★ 採集器（B2.1e）。**沒有它，量到的是一張死網**：中繼與錨都不產礦，
		#   發電機的產出又要乘上自己的礦砂滿足率，於是全網供給恆為 0，
		#   `FlowNetwork` 的傳播迴圈連一次都不會跑——B2.1b 記在
		#   `30_TECH_DESIGN.md` §5.2 的那條曲線量到的是「建索引」的成本，
		#   不是解算的成本。真值大它五十倍（219 節點：27 ms → 1449 ms）。
		for oc: Vector2i in ore.keys():
			ops.append(["place", "extractor", oc])
		for g: Vector2i in grid.keys():
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if grid.has(g + d):
					ops.append(["conduit", grid[g], grid[g + d]])
		# 採集器與核心各自接上對得齊的鄰近網格節點（不合法的一律被 `apply_ops` 擋掉）。
		for oc: Vector2i in (ore.keys() + [s.map["core"] as Vector2i]):
			for g: Vector2i in grid.keys():
				var to: Vector2i = grid[g]
				var d := to - oc
				if maxi(absi(d.x), absi(d.y)) > 5:
					continue
				if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
					continue
				ops.append(["conduit", oc, to])
		BuildController.apply_ops(s, ops)
		var supply := 0.0
		for n: Dictionary in s.nodes:
			supply += float(NodeDefs.of(String(n["type"])).get("ore_out", 0.0))
		t.ok(supply > 0.0, "無盡 %d×%d 的量測台真的有供給（死網量不到解算器）" % [step.x, step.y])
		for k in ENEMIES:
			s.add_enemy(["drifter", "carapace", "ember"][k % 3])
		s.phase = "wave"
		var ms := _ms(s, 1 if step.x > 20 else 5)
		print("[PERF] 無盡大圖 %2d×%2d　節點 %3d／導管 %3d／敵人 %d → %8.1f ms/tick%s" % [
			step.x, step.y, s.nodes.size(), s.conduits.size(), s.enemies.size(), ms,
			"" if ms <= MAX_MS else "　⚠ 超出上限 %.0f ms（R-17）" % MAX_MS
		])
		t.ok(
			ms < ENDLESS_MAX_MS,
			"無盡 %d×%d < %.0f ms（實際 %.1f）——只擋數量級，不是預算"
				% [step.x, step.y, ENDLESS_MAX_MS, ms]
		)
