extends Control
## 2D 覆蓋層：畫在**螢幕座標**的那幾樣東西——能量列、小地圖、邊緣箭頭（`20_ART_DIRECTION.md` §1.8）。
##
## 它們不屬於「地圖怎麼畫」，所以和 `Stage2D` 分開：換成 3D 舞台之後這一層**原封不動**，
## 只是它問視野的對象從 2D 的 `Stage2D` 變成 `Stage3D`（`view_world_rect()`／`to_screen()`／
## `center_view_on()` 都是舞台 API）。小地圖與箭頭的點擊也在這裡（`guide_click()`）：
## 它們是大圖平移唯一的**純左鍵**動線（中鍵拖曳在觸控上不存在，R-16）。

const SessionState := preload("res://scripts/game/SessionState.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const Stage := preload("res://scripts/screens/battle/Stage.gd")
const Prof := preload("res://scripts/core/Prof.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 舞台（只認 `Stage.gd` 的契約，不認 2D）。
var stage: Stage = null


## 小地圖（B2.1b、`20_ART_DIRECTION.md` §1.8）。**只在地圖大過框架時出現**
## ——戰役全部一屏可見，問題節點就在畫面上，多一個浮層只是多一塊遮擋。
const MINIMAP_MAX := Vector2(232.0, 140.0)

const MINIMAP_PAD := 12.0

## 邊緣箭頭上限。**十個箭頭等於沒有箭頭**（§2 反模式：資訊過載）。
const ARROW_MAX := 3

const ARROW_SIZE := 11.0

## 箭頭的命中半徑。P3 手機移植預留條款要求 ≥ 44×44 px，所以半徑取 22。
const ARROW_HIT := 22.0

## 小地圖拖曳中。按住不放時視野持續跟著游標走。
var mini_drag: bool = false

## ★ 小地圖的剩餘顯示秒數（B2.1d.1，使用者指定）。**不常駐**——它蓋在地圖
## 右下角，常駐等於那一塊永遠點不到（使用者：「有些地方會點不到」）。
## 縮放或平移時出現，靜止 `MINI_HOLD` 秒後自己退場。
var mini_ttl: float = 0.0

const MINI_HOLD := 3.0

## 最後這段時間用來淡出，不要用消失的。
const MINI_FADE := 0.5


func _ready() -> void:
	# 同 `Stage2D`：滿版、不吃滑鼠，點擊由畫面層的 `_gui_input` 統一接。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 視野一動，小地圖就現身（並重新計時）。
	stage.view_moved.connect(func() -> void: mini_ttl = MINI_HOLD)


## 畫的順序：箭頭 → 小地圖 → 能量列。**這一層是 `Stage2D` 的後一個子節點**，
## 所以整層都蓋在遮罩（`_draw_frame_matte`）之上。
func _draw() -> void:
	Prof.mark()
	_draw_arrows()
	_draw_minimap()
	_draw_energy_bar()
	Prof.lap("overlay")


## ★ 小地圖倒數。`TL_SHOT` 下**不倒數**——截圖落在第幾秒取決於這台機器
##   跑了幾幀，會倒數的話同一組參數在不同機器上會拍出「有／沒有小地圖」
##   兩種圖，截圖就不能拿來回歸比對了（和模擬凍結同一條理由）。
func tick(delta: float) -> void:
	if mini_ttl > 0.0 and Hooks.shot_path == "":
		mini_ttl = maxf(0.0, mini_ttl - delta)
		if mini_ttl <= 0.0:
			scr.redraw()


# ── 大圖導引：小地圖與邊緣箭頭（B2.1b，`20_ART_DIRECTION.md` §1.8）────────
#
# 大圖模式的 R-3 驗收是「**瓶頸節點即使不在畫面內也能在 30 秒內被找到**」。
# 兩個通道分工明確，不是互為備援：
#   小地圖 → 「全局現在長什麼樣？我在哪？」常駐、靜態。
#   邊緣箭頭 → 「現在有東西壞了，在畫面外哪一邊？」打斷式。
# 兩者都可點，點了把視野移過去——這也是大圖平移唯一的**純左鍵**動線
# （中鍵拖曳在觸控上不存在，R-16）。


## 「問題」不新發明判定，就是既有的兩件事，依嚴重度排序：
##   ① 正在被 walk-by 啃的節點（`_threat`，和主畫面的四角括號同一份判定）
##   ② `缺料`／`滿溢`（`node_state`，和三態徽章同一份判定）
## 排序決定 `ARROW_MAX` 砍掉的是哪幾個——被啃的永遠留著。
func _problem_cells() -> Array[Vector2i]:
	var hurt: Array[Vector2i] = []
	var stuck: Array[Vector2i] = []
	var state: Dictionary = s.rates["node_state"]
	for n: Dictionary in s.nodes:
		var c: Vector2i = n["cell"]
		if stage.threat.has(c):
			hurt.append(c)
		elif int(state.get(int(n["id"]), SessionState.NORMAL)) != SessionState.NORMAL:
			stuck.append(c)
	hurt.append_array(stuck)
	return hurt


## 小地圖的位置：框架**右下角**內側——離建造欄（左）與能量列（上）最遠的角。
## 尺寸依地圖長寬比縮進 `MINIMAP_MAX`，所以它永遠和地圖同比例（不同比例的
## 縮圖上，「我在哪」那個框會說謊）。
func minimap_rect() -> Rect2:
	var m := Vector2(s.map["size"])
	var k := minf(MINIMAP_MAX.x / m.x, MINIMAP_MAX.y / m.y)
	var sz := m * k
	return Rect2(stage.FRAME.end - sz - Vector2(MINIMAP_PAD, MINIMAP_PAD), sz)


func _draw_minimap() -> void:
	if not stage.oversized() or mini_ttl <= 0.0:
		return
	# ★ 最後 `MINI_FADE` 秒淡出。**整體透明度乘在每一筆上**，退場時底板、
	#   路徑、視野框一起淡——只淡其中幾樣會出現「框還在、底板不見了」。
	var fade := clampf(mini_ttl / MINI_FADE, 0.0, 1.0)
	var r := minimap_rect()
	# ★ 底板往外長，**外框畫在 `r` 上**（B2.1d）。舊版把框也畫在 `box` 上，
	#   於是推到底時視野框離可見的邊還有 5px ——使用者回報「小地圖滑到底
	#   不會貼邊」。框就是地圖的邊界，底板只是讓它在遊戲畫面上讀得出來。
	draw_rect(r.grow(5.0), Palette.alpha(Palette.BG_PANEL, 0.96 * fade))
	draw_rect(r, Palette.alpha(Palette.BORDER_STRONG, fade), false, 1.0)
	# 世界座標 → 小地圖座標。
	var k := r.size.x / (float(s.map["size"].x) * Shapes.GRID)
	var cell := maxf(1.0, Shapes.GRID * k)

	for c: Vector2i in s.path:
		draw_rect(
			Rect2(r.position + Vector2(c) * cell, Vector2(cell, cell)),
			Palette.alpha(Palette.TIDE_DEEP, fade)
		)
	# 玩家節點：小地圖上讀的是**產線的形狀**，不是個別節點，所以一律同一個點。
	for n: Dictionary in s.nodes:
		draw_rect(
			Rect2(r.position + Vector2(n["cell"]) * cell, Vector2(cell, cell)),
			Palette.alpha(Palette.ORDER_CYAN, fade)
		)
	# 問題標記：**比節點大一倍** ＋ 脈動。要在一堆青點裡被一眼挑出來，
	# 只換顏色不夠（§4.3b）。
	var pulse := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.45)
	for c: Vector2i in _problem_cells():
		var at := r.position + Vector2(c) * cell - Vector2(cell, cell) * 0.5
		draw_rect(
			Rect2(at, Vector2(cell, cell) * 2.0),
			Palette.alpha(Palette.WARN_ORANGE, pulse * fade)
		)
	# 視野框：「我在哪」——這是小地圖與一張縮圖的唯一差別。
	var vw := stage.view_world_rect()
	draw_rect(
		Rect2(r.position + vw.position * k, vw.size * k).intersection(r),
		Palette.alpha(Palette.ORDER_BRIGHT, fade), false, 1.0
	)


## 邊緣箭頭：畫在框架內緣，指向畫面外的問題。
##
## 只畫**不在畫面內**的——在畫面內的問題本來就看得到，再加一個箭頭是雜訊。
func _draw_arrows() -> void:
	if not stage.oversized():
		return
	var a := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.5)
	for hit: Array in _arrow_hits():
		var at: Vector2 = hit[0]
		var dir: Vector2 = hit[1]
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			at + dir * ARROW_SIZE,
			at - dir * ARROW_SIZE * 0.6 + perp * ARROW_SIZE * 0.75,
			at - dir * ARROW_SIZE * 0.6 - perp * ARROW_SIZE * 0.75,
		]), Palette.alpha(Palette.WARN_ORANGE, a))


## 箭頭的位置、方向與目標格：`[[螢幕位置, 單位方向, 目標格], ...]`。
## **繪圖與命中判定共用這一支**——兩份會漂掉，而漂掉的症狀是「看得到但點不到」。
func _arrow_hits() -> Array:
	var out: Array = []
	var vw := stage.view_world_rect()
	var mid := stage.FRAME.position + stage.FRAME.size * 0.5
	# 框架內緣，留出箭頭自己的半徑，否則尖端會被邊緣切掉。
	var inner := stage.FRAME.grow(-(ARROW_SIZE + 6.0))
	for c: Vector2i in _problem_cells():
		if out.size() >= ARROW_MAX:
			break
		var w := stage.center(c)
		if vw.has_point(w):
			continue
		var dir := (stage.to_screen(w) - mid)
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		# 從框架中心往那個方向射到內緣：兩軸各算一次，取先撞到的那一個。
		var tx := INF if is_zero_approx(dir.x) else (inner.size.x * 0.5) / absf(dir.x)
		var ty := INF if is_zero_approx(dir.y) else (inner.size.y * 0.5) / absf(dir.y)
		out.append([mid + dir * minf(tx, ty), dir, c])
	return out


## 導引的點擊。回傳「有沒有吃掉這一次點擊」——吃掉了就不可以再當成蓋節點，
## 否則點小地圖會在它底下的那一格蓋出東西來。
func guide_click(pos: Vector2) -> bool:
	if not stage.oversized():
		return false
	for hit: Array in _arrow_hits():
		if pos.distance_to(hit[0] as Vector2) <= ARROW_HIT:
			stage.center_view_on(hit[2] as Vector2i)
			return true
	# ★ **看不見就不攔截**（B2.1d.1）。小地圖蓋在地圖右下角，常駐攔截等於
	#   那一塊永遠蓋不了東西——使用者回報「有些地方會點不到」。
	if mini_ttl <= 0.0 or not minimap_rect().grow(5.0).has_point(pos):
		return false
	# 按下就開始拖曳；放開才結束（見 `_gui_input`）。單擊仍然等於「跳一次」，
	# 因為按下的當下就已經 seek 過一次了。
	mini_drag = true
	mini_seek(pos)
	return true


## 把小地圖上的一點換算成地圖格，並把視野**平滑**移過去。
func mini_seek(pos: Vector2) -> void:
	var r := minimap_rect()
	var k := r.size.x / (float(s.map["size"].x) * Shapes.GRID)
	stage.center_view_on(Shapes.to_grid((pos - r.position) / k))


## ★ 能量列（`10_GDD.md` §6.2 硬性要求 1）：**全畫面最醒目的元件，而且是一條
## 圖形不是一串數字**——長度即資訊，所以它在 `TL_NAKED` 下要留著。
## 琥珀＝供給、右側橙色＝短少的部分（脈動）、細刻度＝需求落在哪裡。
func _draw_energy_bar() -> void:
	var r: Dictionary = s.rates
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var span := maxf(1.0, maxf(supply, demand))
	# ★ 跨滿**框架**而不是跨滿地圖（B1.2.2）：框架恆定，所以這條「全畫面最醒目
	#   的元件」在每一關都是同一個長度，長度即資訊那句話才跨關成立。
	var w := stage.FRAME.size.x
	var at := Vector2(stage.FRAME.position.x, stage.FRAME.position.y - 12.0)
	# ★ B3.11：一圈深色的底框——琥珀條和頂欄的字都亮，中間要有一條暗線分開。
	draw_rect(
		Rect2(at - Vector2(1.0, 1.0), Vector2(w + 2.0, 10.0)), Palette.alpha(Palette.BG_DEEP, 0.75)
	)
	draw_rect(Rect2(at, Vector2(w, 8.0)), Palette.BG_RAISED)
	draw_rect(Rect2(at, Vector2(w * supply / span, 8.0)), Palette.ENERGY_AMBER)
	if demand > supply:
		# 脈動走 `Motion`（§4.1 時長階、§4.4 可跳過）。B1.6 之前這裡是
		# `sin(tick * 0.4)`、敵人是 `sin(tick * 0.25)`——兩個係數沒有任何理由
		# 不同，看起來卻像兩件不同的事，而且都繞過了 `reduce_motion`。
		var pulse := Motion.pulse01(s.tick_count, Motion.AMBIENT * 0.5, 0.55)
		var x := w * supply / span
		draw_rect(
			Rect2(at + Vector2(x, 0.0), Vector2(w * demand / span - x, 8.0)),
			Palette.alpha(Palette.WARN_ORANGE, pulse)
		)
	draw_rect(Rect2(at + Vector2(w * demand / span - 1.0, -3.0), Vector2(2.0, 14.0)),
		Palette.TEXT_PRIMARY)
