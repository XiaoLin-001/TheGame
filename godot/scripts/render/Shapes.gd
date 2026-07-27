class_name Shapes
extends RefCounted
## 20_ART_DIRECTION.md §1.4／§1.5 裡「有公式」的部分。
##
## 本批只放已經有明確規格、且下一批就要用的東西：網格與導管線寬。
## 節點／敵潮／跨越點的實際繪圖函式排在 B0.3（那時才有東西要畫），
## 現在先建檔案不先建函式 —— 沒有呼叫者的繪圖 helper 只是猜測。

## 地圖網格。所有玩家建築嚴格對齊（§1.5）。
const GRID := 32.0


## 導管線寬 = 2 + 6 × (flow / cap)，範圍 2–8px。
##
## **這是遊戲最重要的資訊視覺化：線的粗細就是流量。** R-3 的可讀性驗收
## （`TL_NAKED=1` 遮掉所有數字後仍要能指出瓶頸）完全踩在這條公式上，
## 所以它寫成純函式、可被測試斷言，而不是散在繪圖程式碼裡的魔術數字。
static func conduit_width(flow: float, cap: float) -> float:
	if cap <= 0.0:
		return 2.0
	return 2.0 + 6.0 * clampf(flow / cap, 0.0, 1.0)


## 座標 ↔ 網格互換。
static func to_grid(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / GRID), floori(world.y / GRID))


static func to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID, cell.y * GRID)


## 網格線。1px、border.subtle、透明度 20%（§1.5）。
static func draw_grid(ci: CanvasItem, rect: Rect2) -> void:
	var c := Palette.alpha(Palette.BORDER_SUBTLE, 0.2)
	var x := floorf(rect.position.x / GRID) * GRID
	while x <= rect.end.x:
		ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), c, 1.0)
		x += GRID
	var y := floorf(rect.position.y / GRID) * GRID
	while y <= rect.end.y:
		ci.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), c, 1.0)
		y += GRID
