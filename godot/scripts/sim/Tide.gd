extends RefCounted
## 敵潮的推進與 walk-by 破壞（`10_GDD.md` §3.5）。
##
## **純函式、零副作用、零 RNG。** 不引用 autoload。
## 回傳「發生了什麼」，由 `game/BattleController.gd` 決定要怎麼改狀態。
##
## ── 這支檔案在守的三條設計 ──────────────────────────────────────────
## ① **永不停步**：推進與破壞是兩件互不影響的事。沒有索敵、沒有停頓、
##    沒有任何建築能改變一隻敵人的到達時間——這是「丟一排中繼當肉盾」
##    這條迷宮塔防後門被堵死的地方（砍案清單）。
## ② **只有核心讓它們駐足**：走到路徑終點就停下來打核心，直到核心歸零。
## ③ **橋（含引道）上的導管免疫**：見 `immune_indices()`。

const TICK := 0.1
## walk-by 的破壞半徑：相鄰 1 格（Chebyshev 距離）。
const BLAST := 1
## 橋的免疫沿導管向兩側各延伸幾格（＝引道）。見 `immune_indices()`。
const RAMP := 1


## 推進一隻敵人。回傳新的 `progress`（單位：路徑格）。
## **不看任何建築**——這正是「永不停步」的實作面貌。
static func advance(progress: float, speed: float, path_len: int) -> float:
	return minf(progress + speed * TICK, float(path_len - 1))


## 敵人此刻所在的格。
static func cell_of(path: Array, progress: float) -> Vector2i:
	if path.is_empty():
		return Vector2i.ZERO
	return path[clampi(int(floor(progress)), 0, path.size() - 1)]


## 走到終點了嗎？到了就停下來打核心（唯一會讓它駐足的目標）。
static func at_core(progress: float, path_len: int) -> bool:
	return progress >= float(path_len - 1) - 0.0001


## 在破壞半徑內嗎？Chebyshev 距離 ≤ 1（八方相鄰）。
static func in_blast(enemy_cell: Vector2i, target: Vector2i) -> bool:
	return maxi(absi(enemy_cell.x - target.x), absi(enemy_cell.y - target.y)) <= BLAST


## ★ 一條導管上「不受攻擊」的格索引（`10_GDD.md` §3.5）。
##
## 免疫的不只是跨越點那一格，而是**跨越點 ±1 格**——上橋與下橋的引道。
## 只免疫橋面那一格的話這條規則等於不存在：敵人走在路徑格上、破壞半徑 1 格，
## 而導管垂直穿過路徑必然佔用「橋 ＋ 兩側各一格」，兩側正好都在半徑內，
## **每一條過橋的線都會在引道被打斷**，橋就從安全動線變成純裝飾。
static func immune_indices(cells: Array, crossings: Dictionary) -> Dictionary:
	var immune: Dictionary = {}
	for i in cells.size():
		if not crossings.has(cells[i]):
			continue
		for d in range(-RAMP, RAMP + 1):
			var j := i + d
			if j >= 0 and j < cells.size():
				immune[j] = true
	return immune


## 這條導管會不會被站在 `enemy_cell` 的敵人打到？
## 免疫格（橋與引道）**完全不計入**——一條只在橋上靠近路徑的線是全程安全的。
static func conduit_hit(cells: Array, crossings: Dictionary, enemy_cell: Vector2i) -> bool:
	var immune := immune_indices(cells, crossings)
	for i in cells.size():
		if immune.has(i):
			continue
		if in_blast(enemy_cell, cells[i]):
			return true
	return false
