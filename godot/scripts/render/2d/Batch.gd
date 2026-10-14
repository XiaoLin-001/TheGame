extends RefCounted
## 把一堆同色的圖形併成**一個**繪圖指令（B3.15，RG-184）。
##
## 靜態層（網格、路徑暈、路徑帶）一張圖要幾百個 `draw_colored_polygon()`／`draw_line()`——
## 每個都是引擎側的一個指令、一次 draw call。第 10 關靜態層就占了近 300 個 draw call、
## 約一半的渲染 CPU 時間，而那一層**整局不會變**。併起來之後是一個三角形陣列加一個線段陣列。
##
## 畫面與逐個畫**逐像素相同**（`qa/check.py shots` 0 差）：同樣的頂點、同樣的顏色，只是一次送出。
## 前提是**同色的圖形之間不互相疊**（疊了就會多混一次色）——路徑暈的格子與路徑帶的多邊形各自互不相疊。


## 一堆**凸**多邊形、同一個顏色 → 一個三角形陣列指令（扇形三角化；凸多邊形的覆蓋範圍與耳切法相同）。
static func fills(ci: CanvasItem, polys: Array, col: Color) -> void:
	if polys.is_empty():
		return
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for poly: PackedVector2Array in polys:
		var base := pts.size()
		pts.append_array(poly)
		for i in range(1, poly.size() - 1):
			idx.append(base)
			idx.append(base + i)
			idx.append(base + i + 1)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


## 一堆**線段**（每兩個點一段）、同色同寬 → 一個指令。
static func lines(ci: CanvasItem, segments: PackedVector2Array, col: Color, width: float) -> void:
	if segments.size() >= 2:
		ci.draw_multiline(segments, col, width)
