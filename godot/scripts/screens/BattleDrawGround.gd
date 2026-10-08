class_name BattleDrawGround
extends RefCounted
## 地面層繪圖：地貌、敵人路徑、橋、礦點、危險帶、框架遮罩。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Motion := preload("res://scripts/render/Motion.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Terrain := preload("res://scripts/render/Terrain.gd")

## 一格的四個角（格點偏移），順時鐘。與 `SIDES` 同序：`SIDES[i]` 是 `CORNERS[i]`
## 到 `CORNERS[i+1]` 那條邊的外向法線方向。
const CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)
]

## 四個鄰邊的方向（上、右、下、左）。
const SIDES: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]

## 一個格點周圍的四格。
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)
]

## 八方鄰居 ＋ 自己（walk-by 的 Chebyshev 距離 1）。
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## ★ 地貌（B3.13）。**畫在自己的一層**（`show_behind_parent` 的 Node2D），只在換圖時
## 重畫一次；之後每幀只改那一層的位置與縮放。十二張手作圖一張是 300–900 件，
## 64×40 的無盡圖上千件——每幀從 GDScript 重發一次 draw call，就是在 RG-8
## （渲染 23 FPS）那一筆帳上再加一筆。零件本身是純函式（`Terrain.build()`）。
var terrain_layer: Node2D = null

var _terrain_parts: Array = []

var _terrain_id: String = "<none>"

## 一格的四角多邊形，外緣帶抖動（`Shapes.band_jitter`）。**只有路徑帶用它**
## （侵蝕暈走 `_cell_quad`，理由見 `_draw_path`）。
##
## **抖動掛在格點上**：相鄰兩格共用的角落算出同一個偏移，所以帶子不會裂開。
## 內部格點（四周四格都在 `solid` 裡）不偏移，否則帶子中間會出現縫。
##
## ★ **外凸的轉角磨掉尖角**（B2.9，§7.2 A-2 沒做完的那一半）。
##   §1.6 的原文是「抖動 ＋ **轉角改圓弧或磨掉尖角**」，而 B2.4.3 只做了抖動：
##   帶子的邊緣不再筆直，但**每一個轉彎仍然是硬 90°**，而轉角正是「這是機器畫的」
##   最強的訊號——直邊可以說成是水流的方向，直角不行。
##
##   做法是**倒角**：一個只有這一格碰得到的格點（四周只有自己是路）是外凸角，
##   在那裡吐兩個點而不是一個，沿兩條邊各退 `BAND_CHAMFER`。
##   凹角（四周三格是路）不動——凹角是兩條帶子交會的內側，磨它只會開一個洞。
## 倒角吃掉一格的多少（比例，不是像素）。**比例才會隨縮放一起長**——
## 寫死 7px 的第一版在 fit 倍率下只改了 30 個像素，在 300% 下更是看不見，
## 而「看不見的東西等於沒做」是 §7.3 C-2 自己的判準。
const BAND_CHAMFER := 0.3

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## 放大之後地圖比框架大，多出來的部分要被切掉，否則會爬到頂欄與建造欄底下。
## 直接畫四塊不透明的邊條當遮罩——`Control.clip_contents` 夾的是**整個滿版
## 節點**（＝整個畫面），對「只夾住框架」這件事沒有用，而為此把 1500 行的
## 繪圖搬進一個子節點，換到的只是同一個結果。
func draw_frame_matte() -> void:
	var f := BattleCamera.FRAME
	var w := battle.size.x
	var h := battle.size.y
	for r: Rect2 in [
		Rect2(0.0, 0.0, w, f.position.y),                                  # 上
		Rect2(0.0, f.end.y, w, maxf(0.0, h - f.end.y)),                    # 下
		Rect2(0.0, f.position.y, f.position.x, f.size.y),                  # 左
		Rect2(f.end.x, f.position.y, maxf(0.0, w - f.end.x), f.size.y),    # 右
	]:
		if r.size.x > 0.0 and r.size.y > 0.0:
			battle.draw_rect(r, Palette.BG_DEEP)


## 敵人路徑（`20_ART_DIRECTION.md` §1.6、§7.1 A-2／C-1）。
##
## **兩層，由外而內**：
##   ① **侵蝕暈**（C-1）＝ 路徑外一格。它同時是**敵人 walk-by 的傷害半徑**
##      （`10_GDD.md` §3.5：每 tick 傷害相鄰 1 格內的建築）。氣氛與規則同一個
##      元素——一個元素答兩題，和來襲箭羽是同一條理由（§1.6）。
##   ② **路徑帶本身**。
##
## ★ **只有路徑帶抖動，侵蝕暈是直的**（使用者 2026-08-06 拍板）。
##   第一版兩層都抖，讀起來是「兩條扭來扭去的東西」——而這兩層**要答的問題不同**：
##     · 路徑帶講**氣氛**（潮＝混沌，§0 的視覺論題）→ 抖動。
##     · 侵蝕暈講**規則**（我的建築要退開幾格）→ 一條抖動的線量不出格數。
##   規則層走格線是對的：它讓玩家用格子數邊界，而格子正是他放建築的單位。
func draw_path() -> void:
	var pathset: Dictionary = battle.s.sets["path"]
	# 暈這一層的實心區 ＝ 暈 ∪ 路徑。
	var solid: Dictionary = _danger_cells(pathset)
	solid.merge(pathset)
	# ① 侵蝕暈：路徑外一格。**淡到不搶戲**（0.13）——它是底噪不是訊息，
	#    玩家要讀的是「我的建築壓在這一圈裡就會被啃」，不是「這裡有東西」。
	#
	# ★ **整片畫（暈 ∪ 路徑），不是只畫外圈那一環**（B2.4.2 code review 抓到）。
	#   只畫環的話，路徑帶抖出去的那 4px 會蓋不到暈，交界露出背景。整片畫則
	#   路徑帶直接疊在暈上面，不管抖多少都不可能有縫。
	var halo := Palette.alpha(Palette.TIDE_DEEP, 0.13)
	# ★ 外緣描一條線（使用者拍板：「要能讀出傷害半徑」）。
	#   **只有填色是不夠的**——一塊淡淡的顏色說得出「這附近危險」，說不出
	#   「危險到哪裡為止」，而後者才是玩家要下的那個決定（建築要退開幾格）。
	#   線只描**最外圈**，所以它是一條輪廓不是第二條帶子。
	var edge := Palette.alpha(Palette.TIDE_DEEP, 0.5)
	for c: Vector2i in solid:
		var quad := _cell_quad(c)
		battle.draw_colored_polygon(quad, halo)
		# 這一邊的鄰居不在實心區 ＝ 它是最外圈。
		for i in 4:
			if not solid.has(c + SIDES[i]):
				battle.draw_line(quad[i], quad[(i + 1) % 4], edge, 1.0)
	# ② 路徑帶本身，疊在暈上面。0.45 疊在 0.13 上 ≈ 0.52。
	var band := Palette.alpha(Palette.TIDE_DEEP, 0.45)
	for c: Vector2i in battle.s.path:
		battle.draw_colored_polygon(_band_quad(c, pathset), band)
	_draw_incoming()
	for c: Vector2i in battle.s.map.get("crossings", []):
		_draw_crossing(c)


## 地貌層跟著視野走；換圖（地圖 id 變了）才重建零件並重畫那一層。
func sync_terrain() -> void:
	if terrain_layer == null:
		return
	terrain_layer.position = battle.cam.map_origin()
	terrain_layer.scale = Vector2(battle.cam.zoom, battle.cam.zoom)
	var map_id := String(battle.s.map.get("id", ""))
	if map_id != _terrain_id:
		_terrain_id = map_id
		_terrain_parts = Terrain.build(battle.s.map, Shapes.GRID, 1)
		terrain_layer.queue_redraw()


## 地貌層的 `draw`：地的底色 ＋ 裝飾（地圖座標，縮放由那一層自己的 transform 帶）。
func paint_terrain() -> void:
	var size: Vector2i = battle.s.map["size"]
	terrain_layer.draw_rect(Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID), Terrain.ground(battle.s.map))
	Terrain.paint(terrain_layer, _terrain_parts)


## 路徑外一格（Chebyshev 距離 1），**不含路徑本身**。回傳的是**集合**不是陣列。
##
## ＝ `10_GDD.md` §3.5 的 walk-by 傷害範圍，不是另外發明的一個半徑。對得上的是
## `BattleController.BLAST_CELLS`（Chebyshev ≤ 1 的九格）與 `Tide.BLAST = 1`。
##
## ⚠ **它講的是「建築（節點）」，不是導管**（B2.4.2 code review 抓到的一條真的
##   矛盾，結論是修措辭不是修畫面）。兩條規則在同一片像素上都成立：
##     · **節點沒有任何免疫** → 蓋在這一圈裡就是會被啃，暈說的是實話。
##     · **導管在橋與引道上免疫**（`Tide.immune_indices()`，`RAMP = 1`），
##       而那幾格正好落在這一圈裡。
##   所以**不要**在橋兩側把暈挖一個缺口去「修正」它——那會讓一個蓋在缺口裡的
##   中繼看起來安全，而它會被啃。導管的那半邊由**橋的圖形**負責講（§1.6：
##   「架高」是「橋上導管不受攻擊」的唯一解釋），兩個元素各講各的那一半。
##
## ★ **回傳集合是這支函式的重點**（B2.4.2 code review 抓到）：第一版回傳陣列，
##   於是「這一格是不是暈」在別處只能用一支 `_is_danger()` 重跑一次 3×3 掃描——
##   同一個 3×3 迴圈寫了兩遍（重複程式碼），而且它落在 `_draw()` 的內圈裡。
##   實際成本是每幀約 45,000 次查表，**而我在這裡寫的註解說「760 次」**——
##   那個數字只算了這支函式自己，沒算下游。回傳集合之後查表變 O(1)，
##   整條路徑層降到每幀約 6,500 次，`_is_danger()` 整支刪掉。
##
##   教訓與 `benchmarks-need-their-own-assertions` 同一條：**註解裡的效能宣稱
##   如果沒有量過，它就只是一個願望。** 這裡的數字是照實際呼叫次數推的。
##
## 每幀重算而不快取：快取要跟著地圖切換失效，而那是一個會忘記的鉤子。
func _danger_cells(pathset: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var size: Vector2i = battle.s.map["size"]
	for c: Vector2i in battle.s.path:
		for d: Vector2i in NEIGHBOURS:
			var n := c + d
			if pathset.has(n) or out.has(n):
				continue
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
				continue
			out[n] = true
	return out


## 一格的四角多邊形，**貼齊格線**。角的順序與 `SIDES` 對得上（第 i 邊 ＝ i→i+1）。
func _cell_quad(c: Vector2i) -> PackedVector2Array:
	var quad := PackedVector2Array()
	for corner: Vector2i in CORNERS:
		quad.append(battle.cam.world(c + corner))
	return quad


func _band_quad(c: Vector2i, solid: Dictionary) -> PackedVector2Array:
	# ① 先把四個（抖動過的）角算出來。
	var base := PackedVector2Array()
	for corner: Vector2i in CORNERS:
		var g := c + corner
		var w := battle.cam.world(g)
		if not _interior_vertex(g, solid):
			w += Shapes.band_jitter(g.x, g.y)
		base.append(w)
	# ② 再倒角。**沿著實際的邊 `lerp`**，不是沿著「名目上的格子方向」推一段固定長度。
	#
	#   ⚠ B2.9 的第一版是後者，而那會產生**自我相交的多邊形**：偏移量由
	#   `GRID × zoom` 算，起點卻是抖動過的角，兩者對不起來時兩個倒角點會交叉，
	#   Godot 的三角化當場失敗（`Invalid polygon data`）。放大鏡頭時每一幀噴
	#   一百多條——**而 fit 倍率下一條都不噴，所以 B2.9 的驗收完全沒看到**。
	#   走 `lerp` 之後兩個點必定落在自己那條邊上，`0.3 + 0.3 < 1` 就結構上不可能相交。
	var quad := PackedVector2Array()
	for i in CORNERS.size():
		var g := c + CORNERS[i]
		if not _outer_corner(g, solid):
			quad.append(base[i])
			continue
		var prev: Vector2 = base[(i + CORNERS.size() - 1) % CORNERS.size()]
		var next: Vector2 = base[(i + 1) % CORNERS.size()]
		quad.append(base[i].lerp(prev, BAND_CHAMFER))
		quad.append(base[i].lerp(next, BAND_CHAMFER))
	return quad


## 這個格點是不是**外凸角**（四周四格裡只有一格是路）。
## 凹角（三格是路）回 false——那是兩段帶子交會的內側，磨它會開一個洞。
func _outer_corner(g: Vector2i, solid: Dictionary) -> bool:
	var n := 0
	for d: Vector2i in AROUND:
		if solid.has(g + d):
			n += 1
	return n == 1


## 這個格點是不是內部格點（四周四格都在 `solid` 裡）。
func _interior_vertex(g: Vector2i, solid: Dictionary) -> bool:
	for d: Vector2i in AROUND:
		if not solid.has(g + d):
			return false
	return true


## ★ 來襲方向（`20_ART_DIRECTION.md` §1.6）。一條帶子只說「這裡是路」，
## **沒說潮從哪邊來**——而那是新玩家的第一個問題，也決定所有擺位。
## 順著箭羽走就找得到核心，一個元素答兩題（`50_QA_PLAN.md` §4.4）。
func _draw_incoming() -> void:
	var col := Palette.alpha(Palette.TIDE_MAGENTA, 0.35)
	var i := 2
	while i < battle.s.path.size() - 1:
		var here: Vector2i = battle.s.path[i]
		var dir := Vector2(battle.s.path[i + 1] - here).normalized()
		var back := -dir * 5.0
		var wing := dir.orthogonal() * 5.0
		var tip := battle.cam.center(here) + dir * 4.0
		battle.draw_line(tip, tip + back + wing, col, 2.0)
		battle.draw_line(tip, tip + back - wing, col, 2.0)
		i += 4


## 跨越點（橋）：**「架高」必須用畫的說清楚**——它是「橋上導管不受攻擊」
## 這條規則的唯一解釋（`20_ART_DIRECTION.md` §1.6）。硬性要求：一眼可辨。
##
## ★ B2.4.2（§7.1 B-1）：三個元素**本來就都在**，問題是強度與語彙——
##   ① 落影內縮 3px、alpha 0.55 → fit 倍率下幾乎看不到。改成**滿格 ＋ 往下偏移**，
##      投影偏移才是「這東西浮在上面」的視覺線索（一圈等距的暗邊只是描邊）。
##   ② 引道是**直線延長 6px**，不是 §1.6 寫的 45°。而 45° 是秩序側的既有語彙
##      （導管只走 90°/45°，§7.2）——用它，橋才接得回玩家自己的線。
func _draw_crossing(cell: Vector2i) -> void:
	var p := battle.cam.world(cell)
	var g := Shapes.GRID
	var path: Dictionary = battle.s.sets["path"]
	var horizontal := path.has(cell + Vector2i(1, 0)) or path.has(cell + Vector2i(-1, 0))
	var c := Palette.ORDER_CYAN
	# 落影：滿格、往行進方向的**側邊**偏 4px。有偏移才讀得出高度。
	var drop := Vector2(0, 4) if horizontal else Vector2(4, 0)
	# alpha 0.55 而不是 0.7：§1.6 要的是「橋下留**可見的**路徑帶陰影」——
	# 陰影要看得見，但帶子也要還在。真正讓它讀成「架高」的是**偏移**不是深度。
	battle.draw_rect(
		Rect2(p + drop, Vector2(g, g)), Palette.alpha(Palette.BG_DEEP, 0.55)
	)
	if horizontal:
		# 橋面沿垂直方向（導管要南北橫越）。
		for dx: float in [7.0, g - 7.0]:
			battle.draw_line(p + Vector2(dx, -6), p + Vector2(dx, g + 6), c, 3.0)
		for dy: float in [-6.0, g + 6.0]:
			battle.draw_line(p + Vector2(4, dy), p + Vector2(g - 4, dy), c, 2.0)
		# ★ 45° 引道：橋頭往外張開，把橋面接回地面高度。
		for dy: float in [-6.0, g + 6.0]:
			var away := signf(dy)
			for dx: float in [7.0, g - 7.0]:
				var out_x := -6.0 if dx < g * 0.5 else 6.0
				battle.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + out_x, dy + away * 6.0), c, 2.0
				)
	else:
		for dy: float in [7.0, g - 7.0]:
			battle.draw_line(p + Vector2(-6, dy), p + Vector2(g + 6, dy), c, 3.0)
		for dx: float in [-6.0, g + 6.0]:
			battle.draw_line(p + Vector2(dx, 4), p + Vector2(dx, g - 4), c, 2.0)
		for dx: float in [-6.0, g + 6.0]:
			var away := signf(dx)
			for dy: float in [7.0, g - 7.0]:
				var out_y := -6.0 if dy < g * 0.5 else 6.0
				battle.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + away * 6.0, dy + out_y), c, 2.0
				)


func draw_ore_cells() -> void:
	var occupied: Dictionary = battle.s.occupied()
	for c: Vector2i in battle.s.map.get("ore", []):
		if occupied.has(c):
			continue  # 蓋上採集器後由節點填實
		battle.draw_arc(battle.cam.center(c), 10.0, 0.0, TAU, 24, Palette.ORDER_DIM, 2.0)


## ★ 潮鳴的場（B1.8，`20_ART_DIRECTION.md` §1.6）。
##
## **它是全案唯一 `rof = 0` 的塔**：不產生開火線、不播開火音，而每秒吃 9 能量。
## B1.7 之前它在畫面上一個回饋都沒有——玩家無從確認自己花 90 礦砂買的東西
## 有沒有在工作，而「塔在交戰時每秒吃電」正是本作的核心取捨（`10_GDD.md` §7.4）。
##
## 三個刻意的決定：
##   ① **只在交戰時畫**。光環本來就只在射程內有敵人時啟動；恆亮的圈會讓
##      「現在到底有沒有在吃電」這件事反而讀不出來。
##   ② **透明度跟著能量滿足率走**。電不夠時控場真的比較弱（§7.4），
##      圈跟著淡下去，因果就在同一個畫面上。
##   ③ 半徑是**實際射程**（5 格＝160px），和交戰環的 15px 差一個數量級——
##      「同一個位置上的兩個訊息，換顏色不夠，要換形狀」（§4.3b）。
func draw_fields() -> void:
	for n: Dictionary in battle.s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		if not def.has("slow") or not battle.engaged.get(int(n["id"]), false):
			continue
		var k := clampf(
			float((battle.s.rates["satisfaction"] as Dictionary).get(n["id"], 1.0)), 0.0, 1.0
		)
		# ★ 權重是實看調出來的（B1.8）。第一版是 `pulse01(...) * 0.5`，alpha 落在
		#   0.23–0.50——在 `bg.panel` 上那條線**讀起來是灰的不是青的**，整張全景圖
		#   上幾乎看不見（第一張驗收截圖當場抓到）。青色要到 0.6 以上才讀得出色相。
		#
		#   ★ 調的是**下限**不是振幅：`TL_SHOT` 凍結在單一 tick，而脈動的相位由
		#     tick 決定——驗收截圖剛好落在波谷（tick 1556 → alpha 0.48）。
		#     谷底讀得出來，整條曲線就都讀得出來；只拉振幅會讓它一半時間是隱形的。
		var a := Motion.pulse01(battle.s.tick_count, Motion.AMBIENT, 0.72) * 0.92 * k
		battle.draw_arc(
			battle.cam.center(n["cell"]), float(def.get("range", 0.0)) * Shapes.GRID, 0.0, TAU, 64,
			Palette.alpha(Palette.ORDER_CYAN, a), 2.0
		)
