extends RefCounted
## 藍圖庫（`10_GDD.md` §3.7、§7.12；B2.3）。
##
## **純函式、零副作用。** 一張藍圖是一組**相對座標**的節點與導管，
## 和它被框走的那張地圖完全脫鉤——所以它跨局、跨地圖、跨模式都成立。
##
## ── 座標為什麼存成 `[dx, dy]` 而不是 `Vector2i` ──────────────────────
## 藍圖要進 `user://save.json`，而 `Vector2i` 不是 JSON 型別
## （`JSON.stringify()` 會把它變成 `"(1, 2)"` 這種讀不回來的字串）。
## 直接存兩個整數的陣列，**存檔往返就不需要任何一層序列化程式碼**——
## 少一層轉換就少一個「存進去和讀出來不一樣」的機會。

const NodeDefs := preload("res://data/NodeDefs.gd")
const Build := preload("res://scripts/sim/Build.gd")

## 免費藍圖槽。科技「藍圖槽 I／II」各 +1（§7.8），tycoon 的供給排 B2.5。
##
## 為什麼不是 0：**槽數 0 等於這個功能要先買才存在**，而藍圖庫的設計意圖是
## 消除重複勞動（§3.7）——那個痛苦第一局就開始了，不該用科技擋在後面。
const BASE_SLOTS := 2


## 這一份存檔有幾個槽。`mods` 是 `Tech.mods(unlocked)` 的結果。
static func slots(mods: Dictionary) -> int:
	return BASE_SLOTS + int(float(mods.get("blueprint_slots", 0.0)))


## 框選 → 藍圖。矩形**含兩個端點**，原點是矩形左上角。
##
## 兩條收錄規則，都是為了「展開之後真的是同一個東西」：
##   ① **核心不收**——它蓋不出來（`BuildController.place` 沒有這條路），
##      收進去只會讓每次展開都固定失敗一格。
##   ② **導管要兩端都在框內才收**。只有一端在框內的導管，展開時另一端
##      接不到任何節點（`lay_conduit` 直接失敗）——那不是藍圖的一部分，
##      是它和外界的接線，而接線是玩家在新地圖上要自己決定的事。
##
## 節點與導管都**排序後才存**，所以同一份佈局不論當初蓋的順序如何，
## 框出來的藍圖逐欄相同（`blueprint_test` 斷言這件事）。
static func capture(nodes: Array, conduits: Array, a: Vector2i, b: Vector2i) -> Dictionary:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var inside: Dictionary = {}
	var out_nodes: Array = []
	for n: Dictionary in nodes:
		var c: Vector2i = n["cell"]
		if c.x < lo.x or c.x > hi.x or c.y < lo.y or c.y > hi.y:
			continue
		inside[c] = true
		if String(n["type"]) == "core":
			continue
		out_nodes.append({"type": String(n["type"]), "at": [c.x - lo.x, c.y - lo.y]})
	var out_wires: Array = []
	for w: Dictionary in conduits:
		var ca: Vector2i = w["a"]
		var cb: Vector2i = w["b"]
		if not inside.has(ca) or not inside.has(cb):
			continue
		out_wires.append([[ca.x - lo.x, ca.y - lo.y], [cb.x - lo.x, cb.y - lo.y]])
	out_nodes.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return _key(x["at"]) < _key(y["at"])
	)
	out_wires.sort_custom(func(x: Array, y: Array) -> bool:
		return _key(x[0]) * 4096 + _key(x[1]) < _key(y[0]) * 4096 + _key(y[1])
	)
	return {"name": "", "nodes": out_nodes, "conduits": out_wires}


static func _key(at: Array) -> int:
	return int(at[1]) * 64 + int(at[0])


static func is_empty(bp: Dictionary) -> bool:
	return (bp.get("nodes", []) as Array).is_empty()


## 佔用的格數範圍（給畫面畫框、給清單顯示「3×4」）。
static func span(bp: Dictionary) -> Vector2i:
	var w := 0
	var h := 0
	for n: Dictionary in bp.get("nodes", []):
		w = maxi(w, int((n["at"] as Array)[0]) + 1)
		h = maxi(h, int((n["at"] as Array)[1]) + 1)
	return Vector2i(w, h)


## 展開要花多少。**導管的造價只看兩端的相對位移**（`Build.conduit_cost` 取
## Chebyshev 距離 × 每格單價），而位移是藍圖存下來的東西 → 成本與放在哪裡無關。
static func cost(bp: Dictionary) -> Dictionary:
	var ore := 0
	var alloy := 0
	for n: Dictionary in bp.get("nodes", []):
		var t := String(n["type"])
		ore += NodeDefs.cost(t)
		alloy += NodeDefs.alloy_cost(t)
	for w: Array in bp.get("conduits", []):
		ore += Build.conduit_cost(_at(w[0]), _at(w[1]))
	return {"ore": ore, "alloy": alloy}


## 藍圖 → `BuildController.apply_ops()` 的指令陣列，放在 `origin` 這一格。
## **節點全部排在導管之前**：`lay_conduit()` 要求兩端都已經有節點。
static func ops_at(bp: Dictionary, origin: Vector2i) -> Array:
	var ops: Array = []
	for n: Dictionary in bp.get("nodes", []):
		ops.append(["place", String(n["type"]), origin + _at(n["at"])])
	for w: Array in bp.get("conduits", []):
		ops.append(["conduit", origin + _at(w[0]), origin + _at(w[1])])
	return ops


## 藍圖佔用的格（畫預覽框用）。
static func cells_at(bp: Dictionary, origin: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n: Dictionary in bp.get("nodes", []):
		out.append(origin + _at(n["at"]))
	return out


static func _at(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))
