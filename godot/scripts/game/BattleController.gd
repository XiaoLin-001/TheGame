extends RefCounted
## 每 tick 的解算迴圈（`30_TECH_DESIGN.md` §2.4、§2.5）。
##
## **固定時間步 0.1 秒，模擬不使用 `delta`。** 畫面掉幀時補跑 tick，
## 不改變模擬結果——這是確定性的另一半（另一半是 `sim/` 的純函式）。
##
## 解算順序是有意義的：**先礦砂、後能量**。發電機的能量產出要乘上它自己的
## 礦砂滿足率（供不應求按比例降速，不停機，`10_GDD.md` §3.1）。

const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

const TICK := 0.1


## 推進一個 tick。就地變更 `s`。
static func step(s: RefCounted) -> void:
	s.tick_count += 1
	# 邊只建一次：兩個資源網與回寫共用同一份，索引順序才對得起來。
	var edges := _edges(s)
	var ore_res := _solve_ore(s, edges)
	var power_res := _solve_power(s, edges, ore_res)
	_write_rates(s, edges, ore_res, power_res)


# ── 礦砂網 ────────────────────────────────────────────────────────────

static func _solve_ore(s: RefCounted, edges: Array) -> Dictionary:
	var nodes: Array = []
	var supply_total := 0.0
	var demand_total := 0.0
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		var supply := float(def.get("ore_out", 0.0)) * TICK
		var demand := float(def.get("ore_in", 0.0)) * TICK
		supply_total += supply
		demand_total += demand
		nodes.append(_sim_node(n, supply, demand))

	# ★ 核心只收剩下的（`10_GDD.md` §7.3）：燃料永遠優先於入帳。
	# 這讓「礦砂 ▲0/秒」變成一句完整的診斷——你採到的剛好被發電機吃光。
	for sn: Dictionary in nodes:
		if sn["id"] == s.core_id:
			sn["demand"] = maxf(0.0, supply_total - demand_total)

	return FlowNetwork.solve(nodes, edges, s.priorities)


# ── 能量網 ────────────────────────────────────────────────────────────

static func _solve_power(s: RefCounted, edges: Array, ore_res: Dictionary) -> Dictionary:
	var sat: Dictionary = ore_res.get("satisfaction", {})
	var nodes: Array = []
	for n: Dictionary in s.nodes:
		var type := String(n["type"])
		var def := NodeDefs.of(type)
		# 發電機的產出 × 它自己的礦砂滿足率（按比例降速，不停機）。
		var supply := float(def.get("power_out", 0.0)) * TICK * float(sat.get(n["id"], 1.0))
		var demand := float(def.get("power_in", 0.0)) * TICK
		var sn := _sim_node(n, supply, demand)
		if type == "silo":
			# 儲槽是能量專用緩衝（§7.3）。charge 是**絕對量**，不乘 TICK；
			# 解算器拿它跟「每 tick 的 cap」比，兩邊都是同一 tick 的單位。
			sn["charge"] = float(n["charge"])
			sn["capacity"] = float(def.get("capacity", 0.0))
		nodes.append(sn)

	var res := FlowNetwork.solve(nodes, edges, s.priorities)

	# 回寫儲槽充能。解算器是純函式，狀態的變更在這一層。
	var deltas: Dictionary = res.get("charge_delta", {})
	for n: Dictionary in s.nodes:
		if n["type"] != "silo":
			continue
		var cap := float(NodeDefs.of("silo").get("capacity", 0.0))
		n["charge"] = clampf(float(n["charge"]) + float(deltas.get(n["id"], 0.0)), 0.0, cap)
	return res


# ── 共用 ──────────────────────────────────────────────────────────────

static func _sim_node(n: Dictionary, supply: float, demand: float) -> Dictionary:
	return {
		"id": int(n["id"]),
		"type": String(n["type"]),
		"supply": supply,
		"demand": demand,
		"charge": 0.0,
		"capacity": 0.0,
	}


## 導管 → 有向邊。**儲槽那條線展開成雙向**（進去充能、出來放電），
## 這正是 `sim/FlowNetwork.gd` 文件裡要求的表示法。
## 所有量都換算成「每 tick」，包含 cap。
static func _edges(s: RefCounted) -> Array:
	var edges: Array = []
	for c: Dictionary in s.conduits:
		var a: Dictionary = s.node_at(c["a"])
		var b: Dictionary = s.node_at(c["b"])
		if a.is_empty() or b.is_empty():
			continue
		var cap := Build.conduit_cap(int(c["level"])) * TICK
		edges.append({"from": int(a["id"]), "to": int(b["id"]), "cap": cap, "conduit": c["id"]})
		if a["type"] == "silo" or b["type"] == "silo":
			edges.append({"from": int(b["id"]), "to": int(a["id"]), "cap": cap, "conduit": c["id"]})
	return edges


## 把解算結果換算成**單位/秒**寫進 `rates`，供渲染與頂欄讀取。
## 渲染層不做單位換算——它只讀這裡。
static func _write_rates(
	s: RefCounted, edges: Array, ore_res: Dictionary, power_res: Dictionary
) -> void:
	var per_sec := 1.0 / TICK
	var flows: Dictionary = {}
	for i in edges.size():
		var cid: int = int((edges[i] as Dictionary).get("conduit", -1))
		var f := float((ore_res["flow"] as Array)[i]) + float((power_res["flow"] as Array)[i])
		flows[cid] = maxf(float(flows.get(cid, 0.0)), f * per_sec)

	var charge := 0.0
	var capacity := 0.0
	for n: Dictionary in s.nodes:
		if n["type"] == "silo":
			charge += float(n["charge"])
			capacity += float(NodeDefs.of("silo").get("capacity", 0.0))

	var sat: Dictionary = {}
	for id: int in (ore_res["satisfaction"] as Dictionary):
		sat[id] = minf(
			float(ore_res["satisfaction"][id]), float(power_res["satisfaction"].get(id, 1.0))
		)

	s.rates["ore_in"] = float((ore_res["received"] as Dictionary).get(s.core_id, 0.0)) * per_sec
	s.rates["power_supply"] = float(power_res["supply_total"]) * per_sec
	# 儲槽的充能需求算進「需求」——網路本 tick 確實想要那些電，
	# 存量／容量則由 `silo_charge` / `silo_capacity` 另列一格（GDD §3.1）。
	s.rates["power_demand"] = (
		float(power_res["demand_total"]) + float(power_res["silo_demand_total"])
	) * per_sec
	s.rates["silo_charge"] = charge
	s.rates["silo_capacity"] = capacity
	s.rates["conduit_flow"] = flows
	s.rates["satisfaction"] = sat

	# 入帳：**只有送達核心的礦砂算數**（§7.3）。
	s.ore += float((ore_res["received"] as Dictionary).get(s.core_id, 0.0))
