class_name Shapes
extends RefCounted
## 20_ART_DIRECTION.md §1.4／§1.5 裡「有公式」的部分。
##
## 本批只放已經有明確規格、且下一批就要用的東西：網格與導管線寬。
## 節點／敵潮／跨越點的實際繪圖函式排在 B0.3（那時才有東西要畫），
## 現在先建檔案不先建函式 —— 沒有呼叫者的繪圖 helper 只是猜測。

## 地圖網格。所有玩家建築嚴格對齊（§1.5）。
const GRID := 32.0


## 導管線寬 = 2 + 6 × (flow / scale)，範圍 2–8px。
##
## **這是遊戲最重要的資訊視覺化：線的粗細就是流量。**
##
## ★ `scale` 是**全遊戲的最大 cap**（滿級導管），不是這條線自己的 cap。
## B1.1 之前的分母是自己的 cap，也就是「飽和度」——那讓**加粗一條線會讓它變細**
## （分母變大），而按鈕就叫「加粗」。使用者實看後的原話：「有時候升級的管道
## 卻比沒升級的還小」「應該要是越大的流量管道越粗」。
##
## 分母改成固定的最大 cap 之後：粗細在全圖上可以互相比較（同樣的粗代表同樣的
## 流量，不管那條線升到幾級），而**飽和度整個交給顏色**（`Palette.conduit()`）。
## 兩個視覺通道從此各講一件事，不再重複。
static func conduit_width(flow: float, scale: float) -> float:
	if scale <= 0.0:
		return 2.0
	return 2.0 + 6.0 * clampf(flow / scale, 0.0, 1.0)


## ★ 可讀性地板（B1.2.2）。**視覺編碼是在 32px 的格子上校準與驗收的**
## （線寬 2–8px、三態徽章、射程圈，B0.6 的 `TL_NAKED` 讀圖紀錄）。
##
## 地圖框架固定之後，格子的像素大小 ＝ `GRID × fit_zoom`，也就是**圖越大格越小**。
## 24px 是 32 的四分之三：低於它，8px 的滿載線寬只剩 6px、徽章開始糊成一團，
## 「一眼看出瓶頸」（R-3）就不再是驗過的事。
##
## 這不是硬性禁令，是一條**要重新驗收才能跨過的線**：真的需要 40×40 的圖，
## 就先拿那張圖跑一次 `TL_NAKED` 讀圖，把結論寫進 `50_QA_PLAN.md`。
const MIN_READABLE_CELL := 24.0


## 一張地圖剛好填滿框架的縮放倍率。取兩軸較小值——較大值會讓另一軸溢出，
## 而「進場就看得到全貌」是框架存在的理由。
##
## 純函式放在這裡而不是畫面層：`campaign_test` 要拿它算每一關的格子大小，
## 而測試不開視窗。
static func fit_zoom(map_cells: Vector2i, frame: Vector2) -> float:
	var px := Vector2(map_cells) * GRID
	if px.x <= 0.0 or px.y <= 0.0:
		return 1.0
	return minf(frame.x / px.x, frame.y / px.y)


## 這張圖在框架裡的一格會有幾個像素。
static func fit_cell_px(map_cells: Vector2i, frame: Vector2) -> float:
	return GRID * fit_zoom(map_cells, frame)


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
