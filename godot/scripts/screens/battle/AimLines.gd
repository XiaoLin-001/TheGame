extends RefCounted
## 瞄準線的資料（B4.5）：每座**有目標**的塔此刻看著誰、多遠、中間有沒有被地形擋住。
##
## 從 `Overlay2D` 拆出來是為了能在沒有 autoload 的測試裡驗它（`Overlay2D` 讀 `Hooks`，`--script` 模式下載不起來）：
## 這裡只問 `SessionState`（`s`）與舞台契約（`Stage.sight_blocked()`），沒有任何畫面或 autoload 相依。
##
## 目標選擇與 `BattleController._fire()` 是**同一組函式**（最前＝路徑進度最大；稜鏡走最多敵人的那條軸，取軸上最遠的那一隻當線的終點），
## 所以畫的就是它下一發實際會打的那一隻，不是另一套猜測。潮鳴與霜礁（光環，沒有目標）不在內。

const Combat := preload("res://scripts/sim/Combat.gd")
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")


## `[{id, cell, foe（敵人索引）, dist（格，塔格心到目標所在格心）, blocked}]`，依 `s.nodes` 的順序。
static func targets(s: RefCounted, stage: Control) -> Array:
	var out: Array = []
	if s == null or s.enemies.is_empty():
		return out
	var cells := Combat.enemy_cells(s.enemies, s.path)
	for n: Dictionary in s.nodes:
		var type := String(n["type"])
		var def := NodeDefs.of(type)
		if not def.get("tower", false) or float(def.get("rof", 0.0)) <= 0.0:
			continue
		var cell: Vector2i = n["cell"]
		var rng := Build.node_range(type, int(n.get("level", 0)))
		var t := -1
		if def.get("pierce", false):
			var far := -1.0
			for i: int in Combat.pierce_indices(cell, cells, rng):
				var d := Vector2(cells[i] - cell).length()
				if d > far:
					far = d
					t = i
		else:
			t = Combat.front_most(Combat.in_range_indices(cell, cells, rng), s.enemies)
		if t < 0:
			continue
		out.append({
			"id": int(n["id"]), "cell": cell, "foe": t, "dist": Vector2(cells[t] - cell).length(),
			"blocked": stage.sight_blocked(cell, t),
		})
	return out
