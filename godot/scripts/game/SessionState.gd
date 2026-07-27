extends RefCounted
## 當前一局的狀態擁有者（`30_TECH_DESIGN.md` §2.3）。**局結束即銷毀，不持久化。**
##
## 這裡**只有狀態與查詢，沒有規則**——建造規則在 `sim/Build.gd`（純函式），
## 花錢與扣款在 `game/BuildController.gd`，每 tick 的解算在 `game/BattleController.gd`。
##
## 畫面層以**引用**取得本物件，不得持有副本；容器一律原地變更。

const Maps := preload("res://data/Maps.gd")
## `sim/` 一律以路徑 preload，不靠 global class name——
## `--script` 模式不載入 autoload，模擬層必須自足（`50_QA_PLAN.md` §2）。
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

## 地圖原始資料與它的集合形式（查詢用，每局只轉一次）。
var map: Dictionary = {}
var sets: Dictionary = {}

## 帳上礦砂。**只有送達核心的礦砂才進得來**（`10_GDD.md` §7.3）。
var ore: float = 0.0

## `{id, type, cell, hp, charge}`。核心也是一個節點（type = "core"）。
var nodes: Array[Dictionary] = []
## `{id, a, b, level, hp}`。`a`→`b` 有向；儲槽那條線在解算時自動展開成雙向。
var conduits: Array[Dictionary] = []

## 依**節點類型**的優先權（`10_GDD.md` §3.1）。面板要到 B0.5 才拉得動。
var priorities: Dictionary = {}

var tick_count: int = 0
var core_id: int = -1

## 最近一次解算的顯示值（**單位/秒**，供渲染與頂欄讀取）。
## `conduit_flow` 依 conduit 索引；其餘依 node id。
var rates: Dictionary = {
	"ore_in": 0.0,       # 本 tick 實際入帳速率
	"power_supply": 0.0,
	"power_demand": 0.0,
	"silo_charge": 0.0,
	"silo_capacity": 0.0,
	"conduit_flow": {},   # {conduit 索引: 該線的最大資源流率}
	"satisfaction": {},   # {node id: 0..1}
}

var _next_id: int = 1


func setup(map_def: Dictionary) -> void:
	map = map_def
	sets = Maps.to_sets(map_def)
	ore = float(map_def.get("start_ore", 0))
	priorities = NodeDefs.DEFAULT_PRIORITY.duplicate()
	core_id = add_node("core", map_def.get("core", Vector2i.ZERO))


func add_node(type: String, cell: Vector2i) -> int:
	var id := _next_id
	_next_id += 1
	nodes.append({
		"id": id,
		"type": type,
		"cell": cell,
		"hp": NodeDefs.hp(type),
		"charge": 0.0,
	})
	return id


func add_conduit(a: Vector2i, b: Vector2i) -> int:
	var id := _next_id
	_next_id += 1
	conduits.append({"id": id, "a": a, "b": b, "level": 0, "hp": 40.0})
	return id


## 移除一個節點，連同所有碰到它的導管（斷了的線留著只會騙人）。
func remove_node_at(cell: Vector2i) -> void:
	for i in range(nodes.size() - 1, -1, -1):
		if nodes[i]["cell"] == cell:
			nodes.remove_at(i)
	for i in range(conduits.size() - 1, -1, -1):
		var c: Dictionary = conduits[i]
		if c["a"] == cell or c["b"] == cell:
			conduits.remove_at(i)


func remove_conduit(index: int) -> void:
	if index >= 0 and index < conduits.size():
		conduits.remove_at(index)


func node_at(cell: Vector2i) -> Dictionary:
	for n: Dictionary in nodes:
		if n["cell"] == cell:
			return n
	return {}


func occupied() -> Dictionary:
	var d: Dictionary = {}
	for n: Dictionary in nodes:
		d[n["cell"]] = true
	return d


func conduit_keys() -> Dictionary:
	var d: Dictionary = {}
	for c: Dictionary in conduits:
		d[Build.conduit_key(c["a"], c["b"])] = true
	return d


## 點到哪條導管上？（拆除／升級要用；命中判定放寬到半格）
func conduit_at(cell: Vector2i) -> int:
	for i in conduits.size():
		var c: Dictionary = conduits[i]
		for cc: Vector2i in Build.line_cells(c["a"], c["b"]):
			if cc == cell and cc != c["a"] and cc != c["b"]:
				return i
	return -1


func count_of(type: String) -> int:
	var n := 0
	for node: Dictionary in nodes:
		if node["type"] == type:
			n += 1
	return n
