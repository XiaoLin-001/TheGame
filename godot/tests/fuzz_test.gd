extends SceneTree
## 模糊測試（B3.14）：**亂序的玩家操作 × 多張地圖**，找執行期錯誤與不變量破口。
##
## 為什麼要有它：其他測試各自驗「一件事做對了」，而這裡問的是「**隨便怎麼玩都不會壞**」。
## GDScript 的執行期錯誤會**中止那一支函式**而不是讓斷言變紅（RG-164），所以一支測試可以在
## 吞掉錯誤的情況下全綠——`qa/check.py tests` 因此把 stderr 裡的 `SCRIPT ERROR` 一律當失敗。
##
## 操作包含**不合法的**（界外、路徑格、重複、沒錢、不存在的導管索引）：規則層該回原因碼，
## 不該丟錯。種子固定，所以這支測試本身是確定性的（失敗時印出 map／seed／round，可重現）。
##
## 每一步之後檢查的不變量：
##   · 礦砂、合金不為負、全是有限值
##   · 每條導管的兩端都有節點（拆節點會連帶拆線）
##   · 每個存活節點的 hp > 0（打到 0 的當 tick 就被清掉；核心例外，它歸零＝輸）
##   · 敵人的 progress 落在路徑內
##   · `state_hash()` 算得出來
## 另外每張圖的第一個種子**跑兩次**，兩次的 `state_hash()` 必須相同（亂序操作下的確定性）。
##
## 跑法：<godot> --headless --path godot --script res://tests/fuzz_test.gd

const T := preload("res://tests/_assert.gd")
const RngLib := preload("res://scripts/core/Rng.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const Maps := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const CampaignData := preload("res://data/Campaign.gd")

const SEEDS := 4
const ROUNDS := 10
const MAX_TICKS_PER_ROUND := 60
## 無盡的大圖每 tick 要幾十毫秒（`30_TECH_DESIGN.md` §5.3），所以只跑很短。
const BIG_ROUNDS := 3
const BIG_TICKS_PER_ROUND := 12

var _failures: PackedStringArray = []
var _runs: int = 0


func _initialize() -> void:
	var t := T.new("fuzz_test", 80)

	var maps: Array[Dictionary] = []
	maps.append({"name": "shoal", "map": Maps.SHOAL, "unlocked": [], "big": false})
	maps.append({"name": "sandbox", "map": Maps.SANDBOX, "unlocked": [], "big": false})
	for i in CampaignData.count():
		var lv := CampaignData.at(i)
		maps.append({
			"name": "L%d" % (i + 1), "map": lv["map"], "unlocked": lv["unlocked"], "big": false,
		})
	for sd in [11, 4242]:
		maps.append({"name": "endless%d" % sd, "map": MapGen.generate(sd), "unlocked": [], "big": true})

	for m: Dictionary in maps:
		var first_hash := ""
		for sd in SEEDS:
			var h := _run(t, m, 1000 + sd)
			if sd == 0:
				first_hash = h
		# 第一個種子再跑一次：亂序操作下仍是同一個局。
		t.eq(_run(t, m, 1000), first_hash, "%s：同一組亂序操作跑兩次，state_hash 相同" % m["name"])

	t.ok(_failures.is_empty(), "全部不變量成立（%d 條破口）" % _failures.size())
	for f in _failures:
		t.ok(false, f)
	print("[fuzz] %d 局亂序操作" % _runs)
	quit(t.report())


## 一局。回傳最後的 `state_hash()`。
func _run(t: RefCounted, m: Dictionary, seed_value: int) -> String:
	_runs += 1
	var rng := RngLib.stream(seed_value)
	var s := SessionState.new()
	s.setup(m["map"], m["unlocked"])
	s.ore = 100000.0
	s.alloy = 100000.0
	var big: bool = m["big"]
	var tag := "%s/seed%d" % [m["name"], seed_value]
	var rounds := BIG_ROUNDS if big else ROUNDS
	var max_ticks := BIG_TICKS_PER_ROUND if big else MAX_TICKS_PER_ROUND
	for r in rounds:
		var ops := rng.randi_range(1, 14)
		for _i in ops:
			_random_op(s, rng, m)
		_check(t, s, "%s/round%d（操作後）" % [tag, r])
		for _k in rng.randi_range(5, max_ticks):
			BattleController.step(s)
			if s.phase == "lost" or s.phase == "won":
				break
		_check(t, s, "%s/round%d（推 tick 後）" % [tag, r])
		if s.phase == "lost" or s.phase == "won":
			break
	t.ok(true, "%s 跑完" % tag)
	return s.state_hash()


func _random_op(s: RefCounted, rng: RandomNumberGenerator, m: Dictionary) -> void:
	var size: Vector2i = s.map["size"]
	var pool: Array = m["unlocked"] if not (m["unlocked"] as Array).is_empty() else NodeDefs.BUILDABLE
	var roll := rng.randi_range(0, 99)
	if roll < 50:
		var type := String(pool[rng.randi_range(0, pool.size() - 1)])
		BuildController.place(s, type, _cell(rng, size))
	elif roll < 75:
		if s.nodes.size() >= 2 and rng.randi_range(0, 9) < 8:
			var a: Dictionary = s.nodes[rng.randi_range(0, s.nodes.size() - 1)]
			var b: Dictionary = s.nodes[rng.randi_range(0, s.nodes.size() - 1)]
			BuildController.lay_conduit(s, a["cell"], b["cell"])
		else:
			BuildController.lay_conduit(s, _cell(rng, size), _cell(rng, size))
	elif roll < 83:
		BuildController.upgrade_node(s, _cell(rng, size) if s.nodes.is_empty() else _node_cell(s, rng))
	elif roll < 87:
		BuildController.upgrade(s, rng.randi_range(-1, s.conduits.size() + 1))
	elif roll < 95:
		BuildController.demolish(s, _cell(rng, size) if s.nodes.is_empty() else _node_cell(s, rng))
	elif roll < 97:
		BuildController.demolish_conduit(s, rng.randi_range(-1, s.conduits.size() + 1))
	elif roll < 99:
		BattleController.start_wave(s)
	else:
		# 藍圖：框一塊、原地再放一次（多半被佔住——那正是要驗的「全有全無」）。
		var a := _cell(rng, size)
		var b := _cell(rng, size)
		var bp := Blueprint.capture(s.nodes, s.conduits, a, b)
		if not Blueprint.is_empty(bp):
			BuildController.blueprint_place(s, bp, _cell(rng, size))


func _cell(rng: RandomNumberGenerator, size: Vector2i) -> Vector2i:
	# 含界外兩格：規則層該回 OUT_OF_BOUNDS，不該丟錯。
	return Vector2i(rng.randi_range(-2, size.x + 1), rng.randi_range(-2, size.y + 1))


func _node_cell(s: RefCounted, rng: RandomNumberGenerator) -> Vector2i:
	return (s.nodes[rng.randi_range(0, s.nodes.size() - 1)] as Dictionary)["cell"]


func _check(t: RefCounted, s: RefCounted, where: String) -> void:
	if not (is_finite(s.ore) and is_finite(s.alloy)) or s.ore < -0.001 or s.alloy < -0.001:
		_failures.append("%s：礦砂／合金為負或非有限（%s／%s）" % [where, s.ore, s.alloy])
	var cells: Dictionary = {}
	for n: Dictionary in s.nodes:
		cells[n["cell"]] = true
		var hp := float(n["hp"])
		if not is_finite(hp) or (hp <= 0.0 and int(n["id"]) != s.core_id):
			_failures.append("%s：節點 %s@%s hp=%s" % [where, n["type"], n["cell"], hp])
	for c: Dictionary in s.conduits:
		if not (cells.has(c["a"]) and cells.has(c["b"])):
			_failures.append("%s：導管 %s→%s 有一端沒有節點" % [where, c["a"], c["b"]])
	var last := float(s.path.size() - 1)
	for e: Dictionary in s.enemies:
		var p := float(e["progress"])
		if not is_finite(p) or p < 0.0 or p > last + 0.001:
			_failures.append("%s：敵人 progress=%s 超出路徑 [0, %s]" % [where, p, last])
	if s.state_hash() == "":
		_failures.append("%s：state_hash 是空的" % where)
	for key: String in ["power_supply", "power_demand", "ore_in", "alloy_in"]:
		if not is_finite(float(s.rates[key])):
			_failures.append("%s：rates.%s 非有限" % [where, key])
