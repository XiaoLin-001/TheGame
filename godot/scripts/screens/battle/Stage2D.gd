extends "res://scripts/screens/battle/Stage.gd"
## 2D 舞台：把局面（`SessionState`）畫成一張俯視的格子地圖，並回答「螢幕上這一點是哪一格」。
##
## 它實作 `Stage.gd` 的契約。
## 這個檔案裡**只有 2D 專屬的東西**：用 `_draw()` 畫的每一層、`draw_set_transform` 的縮放與平移、
## 格子 ↔ 像素的換算。局內畫面與 HUD 看不到它們。
##
## 舞台**不擁有任何遊戲規則，也不改局面**——它只讀 `s`。所有繪圖都在**格為單位的地圖座標**裡做，
## 縮放與平移交給最前面那一個 `draw_set_transform`，所以每一支 `_draw_*` 都不知道縮放存在。
##
## ★ **結構（B3.15，RG-184）**：這個節點自己只畫**會隨幀變**的東西——敵人、彈丸與特效、選取、游標、階段色調。
##   其餘都是它的子節點（`StageLayer`，`show_behind_parent`，座標同為地圖座標），**加入的順序就是繪圖順序**：
##   地貌 → 網格與路徑 → 礦點與場 → 導管（每條一個畫布項）→ 流動珠（一個 `MultiMesh`）→ 節點落影 → 節點塔身（每座一個畫布項）。
##   每一件**只在自己的簽章變了才重畫**（`_process()` 裡的 `_sync_*()`）；沒變的那一件引擎直接重播上次記下的指令。
##   ⚠ **簽章要收齊畫它會讀的每一個輸入**——`TL_CLICKTEST` 的 `cache` 段落逐項驗，
##   並拿「逐件累積的畫面」對「整張重畫的畫面」逐像素比。新增一個會改動畫面的建造動作，要在 `SessionState.rev` 加一。

const SessionState := preload("res://scripts/game/SessionState.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const Glyphs := preload("res://scripts/render/2d/Glyphs.gd")
const Foes := preload("res://scripts/render/2d/Foes.gd")
const Terrain := preload("res://scripts/render/2d/Terrain.gd")
const StageLayer := preload("res://scripts/screens/battle/StageLayer.gd")
const Batch := preload("res://scripts/render/2d/Batch.gd")
const Prof := preload("res://scripts/core/Prof.gd")


## ★ 開打漣漪的壽命（秒，B3.11）。號令音 `wave_start` 有 1.7 秒，漣漪比它短——
## 它只負責「潮從**這裡**進來」那一眼，說完就讓位給敵人本體。
const RIPPLE_SEC := 1.2

# ── 路徑層的格子偏移（B2.4.2）。**常數，不在 `_draw()` 的內圈裡重建陣列。** ──
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

## 流動珠（`20_ART_DIRECTION.md` §1.4a）：珠距、每單位流率的行進速度（px/秒）、
## 低於此流率就完全不畫。20/秒的幹線 ＝ 120 px/秒，一格 32px 約走四分之一秒。
const BEAD_GAP := 20.0

const BEAD_SPEED := 6.0

const BEAD_MIN_RATE := 0.05

## 珠子 `MultiMesh` 一個實例的 float 數：2D 變換 8 ＋ 顏色 4。
const BEAD_FLOATS := 12

const BEAD_SEGMENTS := 64

## 每秒收斂比率。14 在 60fps 下約 4 幀走完八成——快到不覺得延遲，
## 又慢到看得出是「滑過去」而不是「跳過去」（使用者要的是後者的反面）。
const PAN_EASE := 14.0

## 縮放上限＝**下限**的幾倍。
##
## ★ 下限在 B2.1b 從「就是 fit」改成 `max(fit, 可讀性地板)`：
##   一屏可見的圖（全部戰役關卡）fit 本來就在地板之上 → 行為完全不變；
##   大過一屏的圖（無盡）fit 會讓一格掉到 24px 以下，而那正是 RG-59 說
##   「要重新驗收才能跨過」的線——**縮到看得見全圖但讀不出瓶頸，等於
##   把 R-3 的驗收轉包給玩家**。所以無盡看全圖的地方是小地圖，不是主畫面。
const ZOOM_MAX_MULT := 3.0

## 本幀每隻敵人身上的光環 `Vector2(減速, 破甲)`，與 `s.enemies` 同索引。
## 和 `_engaged` 一樣是**繪圖層自己算的**：模擬層每 tick 都在算同一份，
## 但它只把結果用在傷害上、沒有留下來，而畫面要畫的是「誰被抓住了」。
var _auras: Array = []

## 本幀每隻敵人所在的格（與 `s.enemies` 同索引）、id → 索引、「這一 tick 被打中的
## 敵人 id」。三者都是**純渲染推導**（B3.11／B3.12，彈丸落點與受擊一閃用），
## 不新增任何模擬狀態。
var _enemy_cells: Array = []

var _enemy_index: Dictionary = {}

var _hit_ids: Dictionary = {}

## ★ 地貌（B3.13）。**畫在自己的一層**（`show_behind_parent` 的 Node2D），只在換圖時
## 重畫一次；之後每幀只改那一層的位置與縮放。十二張手作圖一張是 300–900 件，
## 64×40 的無盡圖上千件——每幀從 GDScript 重發一次 draw call，就是在 RG-8
## （渲染 23 FPS）那一筆帳上再加一筆。零件本身是純函式（`Terrain.build()`）。
var terrain_layer: StageLayer = null

## ★ 其餘的快取層（B3.15）。簽章與重畫時機見 `_process()`。
var _static_layer: StageLayer = null

var _flow_layer: StageLayer = null

## ★ 逐件快取（B3.15）：每座節點兩個畫布項（落影、塔身）、每條導管一個，**各自**只在自己的簽章變了才重畫。
## 一個 tick 裡通常只有少數幾件真的變了（受傷、換徽章、流量改了），其餘零成本。
var _conduit_group: StageLayer = null

var _node_shadow_group: StageLayer = null

var _node_body_group: StageLayer = null

## 節點 id → `NodeRec`、導管 id → `ConduitRec`。
var _node_recs: Dictionary = {}

var _conduit_recs: Dictionary = {}

## 上一次同步逐件快取時的簽章；`_elem_sid` ＝ 那些畫布項屬於哪一局（換局就整批丟掉）。
var _world_key: Array = []

var _elem_sid: int = 0

var _bead_layer: StageLayer = null

## 流動珠：一個 `MultiMesh`（每顆兩個實例）與它的緩衝區，見 `_update_beads()`。
var _bead_mm: MultiMesh = null

var _bead_buf: PackedFloat32Array = PackedFloat32Array()


var _layers: Array[StageLayer] = []

## 本 tick 的流動珠規格（`_bead_specs()`）。
var _bead_specs_cache: Array = []

## 上一次推導 `engaged`／`threat`／`_auras` 的內容簽章。
var _derived_key: Array = []

## 選取與游標底下的東西**每幀**都要畫，但它們問的問題（誰在餵這座塔電、游標壓在哪條線上、落點預覽）
## 只隨 tick、建造與游標改變——算一次留著（B3.15）。
var _chain_key: Array = []

var _chain: Dictionary = {}

var _hover_key: Array = []

var _hover_wire: int = -1

var _preview_key: Array = []

var _preview: Dictionary = {}


## 一座節點在逐件快取裡的紀錄：它的兩個畫布項、上一次畫的簽章，與那一次建好的幾何。
class NodeRec extends RefCounted:
	var node: Dictionary = {}
	var shadow = null
	var body = null
	var sig: Array = []
	var parts: Array = []
	var at: Vector2 = Vector2.ZERO
	var sc: float = 1.0


## 一條導管的紀錄：畫布項、簽章，與畫它所需要的兩個推導值（流量、終點缺不缺電）。
class ConduitRec extends RefCounted:
	var c: Dictionary = {}
	var item = null
	var sig: Array = []
	var flow: float = 0.0
	var starving: bool = false

var _terrain_parts: Array = []

var _terrain_id: String = "<none>"

## ★ 本幀「畫不出圖形」的節點類型（B2.4.6）。`_node_geometry()` 每漏一種
## 就往這裡記一筆，`TL_CLICKTEST` 拿它當斷言。**這不是防禦性程式碼，是一支感測器**
## ——漏掉一種的後果是那座塔在地圖上完全隱形（蓋得下去、會開火、會吃電、會被
## 打壞，就是看不見），而十五支測試沒有一支會紅：它們驗數值與流量，沒有一支看畫面。
var _no_glyph: Dictionary = {}


func _ready() -> void:
	# 滿版、不吃滑鼠：事件一律落到畫面層的 `_gui_input`。**命中區與繪圖是兩件事**——
	# 少了這一行，這個滿版的 `Control` 會把整張地圖的點擊吃掉（B0.7.2 的缺陷換了個地方重演）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ★ 快取層（B3.13 起地貌、B3.15 起其餘）：**加入的順序就是繪圖順序**，全部畫在本體之後面——
	#   本體只畫會隨**幀**變的東西（敵人、特效、選取、遮罩）。
	#   地貌 → 網格與路徑 → 礦點與場 → 導管 → 流動珠 → 節點落影 → 節點塔身
	#   （落影全部在塔身之前：B3.11 的兩趟規則，一座塔的影子不准壓在鄰居的塔身上）。
	terrain_layer = _add_layer(_paint_terrain)
	_static_layer = _add_layer(_paint_static)
	_flow_layer = _add_layer(_paint_flow)
	_conduit_group = _add_layer(Callable())
	_bead_layer = _add_layer(Callable())
	_bead_mm = MultiMesh.new()
	_bead_mm.transform_format = MultiMesh.TRANSFORM_2D
	_bead_mm.use_colors = true
	_bead_mm.mesh = _unit_circle()
	var beads := MultiMeshInstance2D.new()
	beads.multimesh = _bead_mm
	_bead_layer.add_child(beads)
	_node_shadow_group = _add_layer(Callable())
	_node_body_group = _add_layer(Callable())


## ★ 視野緩動（B2.1d）。指數收斂與幀率無關——`1-exp(-k*dt)` 在 30fps 與
##   144fps 下走完同一段路，`lerp(_, k*dt)` 不會。這只動**畫面**，
##   不碰模擬：`pan` 不進 `state_hash()`，也不影響任何 tick。
func tick_view(delta: float) -> void:
	if not pan.is_equal_approx(pan_goal):
		pan = pan.lerp(pan_goal, 1.0 - exp(-PAN_EASE * delta))
		if pan.distance_to(pan_goal) < 0.5:
			pan = pan_goal
		scr.redraw()


# ── 視野：框架、fit、縮放、平移（B1.2.2）─────────────────────────────

## 縮放下限。一屏可見的圖就是 fit；大過一屏的圖是**可讀性地板**（24px／格）。
##
## `_fit` 這個欄位名沿用下來（它是「全景」鈕與縮放夾限共用的那一個值），
## 但語意在 B2.1b 之後是「看得最遠的倍率」，不一定看得到全圖。
func _fit_zoom() -> float:
	return maxf(
		Shapes.fit_zoom(s.map["size"], FRAME.size),
		Shapes.MIN_READABLE_CELL / Shapes.GRID
	)


## 地圖在目前倍率下裝不進框架嗎？＝ 需不需要小地圖與邊緣箭頭。
## **一屏可見的地圖一律 false**，所以戰役關卡不會多出這兩塊遮擋。
func oversized() -> bool:
	var px := Vector2(s.map["size"]) * Shapes.GRID * zoom
	return px.x > FRAME.size.x + 0.5 or px.y > FRAME.size.y + 0.5


## 進場（與「全景」鈕）的視野：fit ＋ 居中。
func reset_view() -> void:
	fit = _fit_zoom()
	zoom = fit
	pan = Vector2.ZERO
	pan_goal = Vector2.ZERO
	view_moved.emit()
	# ★ `TL_FOCUS="x,y,zoom"`：拍特效的近照（B1.6）。**不會在真實遊玩中生效**
	#   ——它只在有鉤子時存在，而有鉤子時存檔已經是唯讀的。
	if Hooks.focus.x >= 0:
		zoom = clampf(fit * Hooks.focus_zoom, fit, fit * ZOOM_MAX_MULT)
		var px := Vector2(s.map["size"]) * Shapes.GRID
		pan_to((px * 0.5 - center(Hooks.focus)) * zoom, true)


## 地圖左上角在螢幕上的位置。**框架內居中**，放大後由 `_pan` 帶著走。
func _map_origin() -> Vector2:
	var px := Vector2(s.map["size"]) * Shapes.GRID * zoom
	return FRAME.position + (FRAME.size - px) * 0.5 + pan


## 放大之後地圖比框架大，平移要有邊界——不然可以把地圖整片拖出畫面，
## 然後玩家會以為遊戲壞了。夾住之後框架永遠被地圖蓋滿。
func _clamp_pan() -> void:
	var px := Vector2(s.map["size"]) * Shapes.GRID * zoom
	var slack := (px - FRAME.size) * 0.5
	pan.x = clampf(pan.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	pan.y = clampf(pan.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))
	pan_goal.x = clampf(pan_goal.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	pan_goal.y = clampf(pan_goal.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))


## 設定平移目標。`immediate` 為真時當場到位——中鍵拖曳、縮放錨定、
## 以及所有測試斷言都走這條（斷言要驗的是「目標對不對」，不是「補間跑完沒」）。
func pan_to(p: Vector2, immediate: bool = false) -> void:
	# 視野一動，小地圖就現身（並重新計時）——覆蓋層聽 `view_moved`。
	view_moved.emit()
	pan_goal = p
	if immediate or Motion.reduce:
		pan = p
	_clamp_pan()
	scr.redraw()


## 平移一個相對量。滑鼠中鍵拖曳：直接拖曳不走緩動，手指到哪畫面就該到哪（B2.1d）。
func pan_by(rel: Vector2) -> void:
	pan_to(pan + rel, true)


## 讓補間立刻走完。測試專用——把「動畫還沒到」和「算錯位置」分開。
func _settle_view() -> void:
	pan = pan_goal
	_clamp_pan()
	scr.redraw()


## 縮放。`anchor` 是螢幕上要固定不動的那一點（滑鼠位置或框架中心）——
## 少了它，滾輪縮放會把玩家正在看的東西推出畫面。
func zoom_by(mult: float, anchor: Vector2) -> void:
	var before := zoom
	zoom = clampf(zoom * mult, fit, fit * ZOOM_MAX_MULT)
	if is_equal_approx(before, zoom):
		return
	# ★ 讓 `anchor` 底下的那一格在縮放前後**待在原地**。
	#
	#   B1.2.2 的版本寫成 `_pan += (anchor - _map_origin()) * (1 - k)`，錯了兩層：
	#     ① `_map_origin()` 讀的是**已經更新過**的 `_zoom`，量到的是新原點不是舊的；
	#     ② 更根本地，`_map_origin()` 本來就把地圖置中，那一半的位移是縮放自己
	#        帶來的、不該再由 pan 補一次。
	#   兩個加起來的結果是：**按一次「＋」畫面就甩到左上角，而且 pan 當場撞上夾限、
	#   再也拖不動。** `_view_selftest` 當時只斷言「倍率有變大」與「pan 夾得住」，
	#   兩條都還是綠的——這個缺陷是 B1.3.1 加中鍵平移自檢時，
	#   `mid_pan=false` 把它逼出來的。
	#
	#   所以直接照定義寫：新原點 = anchor − k × (anchor − 舊原點)，pan 就是它和
	#   置中位置的差。看得懂比省一行重要。
	var m := Vector2(s.map["size"]) * Shapes.GRID
	var origin_before := FRAME.position + (FRAME.size - m * before) * 0.5 + pan
	var k := zoom / before
	pan_to(
		anchor - (anchor - origin_before) * k
		- (FRAME.position + (FRAME.size - m * zoom) * 0.5),
		true
	)
	scr.refresh_zoom()
	scr.redraw()


## 螢幕像素 → 格號。**縮放與平移的反變換就在這一行**，命中判定與繪圖
## 因此永遠對得起來（各寫一份的那一天，滑鼠就會差半格）。
func cell_at(pos: Vector2) -> Vector2i:
	return Shapes.to_grid((pos - _map_origin()) / zoom)


## 螢幕像素 → **格為單位的浮點座標**（整數＝格中心）。
func point_at(pos: Vector2) -> Vector2:
	return (pos - _map_origin()) / (Shapes.GRID * zoom) - Vector2(0.5, 0.5)


func in_map(c: Vector2i) -> bool:
	var size: Vector2i = s.map["size"]
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


# ── 繪圖 ──────────────────────────────────────────────────────────────

func _draw() -> void:
	Prof.mark()
	var size: Vector2i = s.map["size"]
	var rect := Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID)

	# ★ 這裡只剩**會隨幀變**的東西，而且全部在**格為單位的地圖座標**裡做，縮放與平移交給這一個
	#   變換（B1.2.2）。所以底下每一支 `_draw_*` 都不知道縮放存在——
	#   縮放要是滲進 9 支繪圖函式裡，每加一種圖形就要記得乘一次倍率。
	#   文字不受影響：`_draw()` 裡沒有任何 `draw_string`，HUD 全是 Control 子節點。
	#
	# ★ B3.15：地貌、網格、路徑、礦點、導管、節點、流動珠都**不在這裡畫**了——它們各是一個快取層
	#   （`StageLayer`），簽章沒變就不重畫。`_process()` 負責把那幾層與 `engaged`／`threat` 對到本 tick。
	draw_set_transform(_map_origin(), 0.0, Vector2(zoom, zoom))
	_place_layers()
	Prof.lap("stage.layers")
	# 這兩份要看**本幀**的敵人與彈丸（受擊一閃、彈丸落點），而不是上一個 tick 的。
	_enemy_index = _index_enemies()
	_hit_ids = _hit_ids_of()
	Prof.lap("stage.derive")
	_draw_enemies()
	Prof.lap("stage.enemies")
	_draw_ripple()
	_draw_shots()
	_draw_bursts()
	_draw_shields()
	Prof.lap("stage.fx")
	_draw_selection()
	_draw_hover()
	Prof.lap("stage.sel_hover")
	# 階段色調（`10_GDD.md` §6.2 硬性要求 4）：**不看計時器也知道自己在哪個階段**。
	# 蓋在最上層而不是墊在底下——墊底的話節點與敵人會把它整片蓋掉。
	draw_rect(rect, Palette.alpha(
		Palette.WARN_ORANGE if s.phase == "wave" else Palette.ORDER_CYAN,
		0.10 if s.phase == "wave" else 0.03
	))

	# ── 回到螢幕座標 ──────────────────────────────────────────────────
	# 導引與能量列畫在遮罩**之後**（它們的職責就是講「框架外面有什麼」，被遮罩蓋掉
	# 等於整個功能不存在）——所以它們在 `Overlay2D`，那一層是這一層的後一個子節點。
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_frame_matte()
	Prof.lap("stage.tint_matte")


# ── 快取層（B3.15）────────────────────────────────────────────────────

func _add_layer(painter: Callable) -> StageLayer:
	var layer := StageLayer.new()
	layer.painter = painter
	layer.show_behind_parent = true
	add_child(layer)
	_layers.append(layer)
	return layer


## 每幀（在任何一層重畫之前）：把「本 tick 的推導值」與各層的簽章對好。
##
## ★ **為什麼是 `_process` 而不是 `_draw`**：各層的 `_draw` 與本體的 `_draw` 在同一次排程裡跑，
##   順序不保證——節點讀 `engaged`／`threat`，如果它們在本體的 `_draw` 裡才算，
##   節點可能讀到上一個 tick 的值（`TL_SHOT` 凍結時就會永遠停在空的）。`_process` 一定先於所有 `_draw`。
##
## 簽章：
##   · 靜態層（網格、路徑）  ＝ 局 ＋ 地圖。換圖或重來才重畫。
##   · 導管、節點（逐件）    ＝ **每一件自己的簽章**：節點＝（級數、血量、充能、交戰、受威脅、三態徽章）；
##                             導管＝（級數、流量、終點缺不缺電、受損程度、縮放——刻度與描邊跟著倍率）。
##                             `_sync_*()` 只在 tick／建造／縮放有變時逐件對一遍，簽章沒變的那一件一個指令都不重發。
##   · 流動珠                ＝ 每幀推位置（位置是 tick ＋ 幀內插值的函式），規格（哪幾條線、什麼色、多大）隨 tick。
func _process(_delta: float) -> void:
	if s == null:
		return
	Prof.mark()
	_derive()
	_place_layers()
	var sid: int = s.get_instance_id()
	var map_id := String(s.map.get("id", ""))
	if map_id != _terrain_id:
		_terrain_id = map_id
		_terrain_parts = Terrain.build(s.map, Shapes.GRID, 1)
		terrain_layer.invalidate()
	terrain_layer.refresh([sid, map_id])
	_static_layer.refresh([sid, map_id])
	Prof.lap("proc.stage_layers")
	# 導管與節點的簽章在**每一件**身上，這裡只決定「要不要去逐件對一遍」——tick、建造、縮放有變才對。
	var world_key := [sid, s.tick_count, s.rev, zoom, Motion.reduce]
	if world_key != _world_key:
		_world_key = world_key
		if sid != _elem_sid:
			_clear_elements()
			_elem_sid = sid
		_flow_layer.repaint()
		_sync_conduits()
		Prof.lap("proc.sync_conduits")
		_sync_nodes()
		Prof.lap("proc.sync_nodes")
		_bead_specs_cache = _bead_specs()
		_size_beads()
		Prof.lap("proc.bead_specs")
	_update_beads()
	Prof.lap("stage.beads")


## 把各層對到目前的視野。
func _place_layers() -> void:
	var origin := _map_origin()
	for layer: StageLayer in _layers:
		layer.place(origin, zoom)


## 本 tick 的推導值：敵人所在的格、交戰、光環、受威脅的格。
## 敵人的格算一次給三個人用（交戰、光環、被啃判定）——同一幀各算一次的那一天，
## 就會有一個用到的是上一幀的位置。它們只隨 tick 與建造改變，所以簽章沒變就不重算。
func _derive() -> void:
	var key := [s.get_instance_id(), s.tick_count, s.rev]
	if key == _derived_key:
		return
	_derived_key = key
	var cells := Combat.enemy_cells(s.enemies, s.path)
	engaged = Combat.engaged(s.nodes, cells)
	_auras = Combat.auras(s.nodes, cells, s.rates["satisfaction"])
	threat = _threat_cells(cells)
	# ★ B3.11：敵人的格留給 `_draw_enemies()` 讀（受擊一閃是純渲染推導：剛生出來那幾發的落點）。
	_enemy_cells = cells


## 丟掉所有快取：下一幀整個重畫。
func invalidate() -> void:
	for layer: StageLayer in _layers:
		layer.invalidate()
	_derived_key = []
	_world_key = []
	_forget_signatures()


## 靜態層：網格與敵人路徑。**只在換圖時重畫。**
func _paint_static(ci: CanvasItem) -> void:
	Prof.mark()
	var size: Vector2i = s.map["size"]
	# 網格只畫在地圖範圍內：畫到浮層底下會讓「哪裡可以蓋」變得曖昧。
	Shapes.draw_grid(ci, Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID))
	_draw_path(ci)
	Prof.lap("layer.static")


## 礦點與場：隨 tick 與建造重畫（礦點被佔住就不畫；場的脈動由 tick 決定）。導管與節點是逐件的，見 `_sync_*()`。
func _paint_flow(ci: CanvasItem) -> void:
	Prof.mark()
	_draw_ore_cells(ci)
	_draw_fields(ci)
	Prof.lap("layer.flow")


## 目前看得到的世界座標矩形。小地圖的視野框與「這個問題在不在畫面內」
## 都從這裡算——**只有一份**，兩者不可能各算各的而對不起來。
func view_world_rect() -> Rect2:
	var o := _map_origin()
	return Rect2((FRAME.position - o) / zoom, FRAME.size / zoom)


## 把某一格移到畫面中央（小地圖與箭頭的「一鍵跳」）。
## 與 `TL_FOCUS` 走同一條算式——兩份會漂掉。
func center_view_on(c: Vector2i, immediate: bool = false) -> void:
	var px := Vector2(s.map["size"]) * Shapes.GRID
	pan_to((px * 0.5 - center(c)) * zoom, immediate)


## 放大之後地圖比框架大，多出來的部分要被切掉，否則會爬到頂欄與建造欄底下。
## 直接畫四塊不透明的邊條當遮罩——`Control.clip_contents` 夾的是**整個滿版
## 節點**（＝整個畫面），對「只夾住框架」這件事沒有用，而為此把 1500 行的
## 繪圖搬進一個子節點，換到的只是同一個結果。
func _draw_frame_matte() -> void:
	var f := FRAME
	var w := size.x
	var h := size.y
	for r: Rect2 in [
		Rect2(0.0, 0.0, w, f.position.y),                                  # 上
		Rect2(0.0, f.end.y, w, maxf(0.0, h - f.end.y)),                    # 下
		Rect2(0.0, f.position.y, f.position.x, f.size.y),                  # 左
		Rect2(f.end.x, f.position.y, maxf(0.0, w - f.end.x), f.size.y),    # 右
	]:
		if r.size.x > 0.0 and r.size.y > 0.0:
			draw_rect(r, Palette.BG_DEEP)


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
func _draw_path(ci: CanvasItem) -> void:
	var pathset: Dictionary = s.sets["path"]
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
	# ★ B3.15：這一層整局不變，所以**併成幾個指令**（`Batch`）而不是每格一個——暈的格子互不相疊、
	#   外緣線只貼在暈的邊上，先畫完全部的暈再畫全部的線，畫面逐像素相同。
	var halo_cells: Array = []
	var edges := PackedVector2Array()
	for c: Vector2i in solid:
		var quad := _cell_quad(c)
		halo_cells.append(quad)
		# 這一邊的鄰居不在實心區 ＝ 它是最外圈。
		for i in 4:
			if not solid.has(c + SIDES[i]):
				edges.append(quad[i])
				edges.append(quad[(i + 1) % 4])
	Batch.fills(ci, halo_cells, halo)
	Batch.lines(ci, edges, edge, 1.0)
	# ② 路徑帶本身，疊在暈上面。0.45 疊在 0.13 上 ≈ 0.52。
	var band := Palette.alpha(Palette.TIDE_DEEP, 0.45)
	var band_cells: Array = []
	for c: Vector2i in s.path:
		band_cells.append(_band_quad(c, pathset))
	Batch.fills(ci, band_cells, band)
	_draw_incoming(ci)
	for c: Vector2i in s.map.get("crossings", []):
		_draw_crossing(ci, c)


## 地貌層的 `draw`：地的底色 ＋ 裝飾（地圖座標，縮放由那一層自己的 transform 帶）。
func _paint_terrain(ci: CanvasItem) -> void:
	var size: Vector2i = s.map["size"]
	ci.draw_rect(Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID), Terrain.ground(s.map))
	Terrain.paint(ci, _terrain_parts)


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
	var size: Vector2i = s.map["size"]
	for c: Vector2i in s.path:
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
		quad.append(_world(c + corner))
	return quad


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


func _band_quad(c: Vector2i, solid: Dictionary) -> PackedVector2Array:
	# ① 先把四個（抖動過的）角算出來。
	var base := PackedVector2Array()
	for corner: Vector2i in CORNERS:
		var g := c + corner
		var w := _world(g)
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
func _draw_incoming(ci: CanvasItem) -> void:
	var col := Palette.alpha(Palette.TIDE_MAGENTA, 0.35)
	var strokes := PackedVector2Array()
	var i := 2
	while i < s.path.size() - 1:
		var here: Vector2i = s.path[i]
		var dir := Vector2(s.path[i + 1] - here).normalized()
		var back := -dir * 5.0
		var wing := dir.orthogonal() * 5.0
		var tip := center(here) + dir * 4.0
		strokes.append(tip)
		strokes.append(tip + back + wing)
		strokes.append(tip)
		strokes.append(tip + back - wing)
		i += 4
	Batch.lines(ci, strokes, col, 2.0)


## 跨越點（橋）：**「架高」必須用畫的說清楚**——它是「橋上導管不受攻擊」
## 這條規則的唯一解釋（`20_ART_DIRECTION.md` §1.6）。硬性要求：一眼可辨。
##
## ★ B2.4.2（§7.1 B-1）：三個元素**本來就都在**，問題是強度與語彙——
##   ① 落影內縮 3px、alpha 0.55 → fit 倍率下幾乎看不到。改成**滿格 ＋ 往下偏移**，
##      投影偏移才是「這東西浮在上面」的視覺線索（一圈等距的暗邊只是描邊）。
##   ② 引道是**直線延長 6px**，不是 §1.6 寫的 45°。而 45° 是秩序側的既有語彙
##      （導管只走 90°/45°，§7.2）——用它，橋才接得回玩家自己的線。
func _draw_crossing(ci: CanvasItem, cell: Vector2i) -> void:
	var p := _world(cell)
	var g := Shapes.GRID
	var path: Dictionary = s.sets["path"]
	var horizontal := path.has(cell + Vector2i(1, 0)) or path.has(cell + Vector2i(-1, 0))
	var c := Palette.ORDER_CYAN
	# 落影：滿格、往行進方向的**側邊**偏 4px。有偏移才讀得出高度。
	var drop := Vector2(0, 4) if horizontal else Vector2(4, 0)
	# alpha 0.55 而不是 0.7：§1.6 要的是「橋下留**可見的**路徑帶陰影」——
	# 陰影要看得見，但帶子也要還在。真正讓它讀成「架高」的是**偏移**不是深度。
	ci.draw_rect(
		Rect2(p + drop, Vector2(g, g)), Palette.alpha(Palette.BG_DEEP, 0.55)
	)
	if horizontal:
		# 橋面沿垂直方向（導管要南北橫越）。
		for dx: float in [7.0, g - 7.0]:
			ci.draw_line(p + Vector2(dx, -6), p + Vector2(dx, g + 6), c, 3.0)
		for dy: float in [-6.0, g + 6.0]:
			ci.draw_line(p + Vector2(4, dy), p + Vector2(g - 4, dy), c, 2.0)
		# ★ 45° 引道：橋頭往外張開，把橋面接回地面高度。
		for dy: float in [-6.0, g + 6.0]:
			var away := signf(dy)
			for dx: float in [7.0, g - 7.0]:
				var out_x := -6.0 if dx < g * 0.5 else 6.0
				ci.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + out_x, dy + away * 6.0), c, 2.0
				)
	else:
		for dy: float in [7.0, g - 7.0]:
			ci.draw_line(p + Vector2(-6, dy), p + Vector2(g + 6, dy), c, 3.0)
		for dx: float in [-6.0, g + 6.0]:
			ci.draw_line(p + Vector2(dx, 4), p + Vector2(dx, g - 4), c, 2.0)
		for dx: float in [-6.0, g + 6.0]:
			var away := signf(dx)
			for dy: float in [7.0, g - 7.0]:
				var out_y := -6.0 if dy < g * 0.5 else 6.0
				ci.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + away * 6.0, dy + out_y), c, 2.0
				)


func _draw_ore_cells(ci: CanvasItem) -> void:
	var occupied: Dictionary = s.occupied()
	for c: Vector2i in s.map.get("ore", []):
		if occupied.has(c):
			continue  # 蓋上採集器後由節點填實
		ci.draw_arc(center(c), 10.0, 0.0, TAU, 24, Palette.ORDER_DIM, 2.0)


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
func _draw_fields(ci: CanvasItem) -> void:
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		if not def.has("slow") or not engaged.get(int(n["id"]), false):
			continue
		var k := clampf(
			float((s.rates["satisfaction"] as Dictionary).get(n["id"], 1.0)), 0.0, 1.0
		)
		# ★ 權重是實看調出來的（B1.8）。第一版是 `pulse01(...) * 0.5`，alpha 落在
		#   0.23–0.50——在 `bg.panel` 上那條線**讀起來是灰的不是青的**，整張全景圖
		#   上幾乎看不見（第一張驗收截圖當場抓到）。青色要到 0.6 以上才讀得出色相。
		#
		#   ★ 調的是**下限**不是振幅：`TL_SHOT` 凍結在單一 tick，而脈動的相位由
		#     tick 決定——驗收截圖剛好落在波谷（tick 1556 → alpha 0.48）。
		#     谷底讀得出來，整條曲線就都讀得出來；只拉振幅會讓它一半時間是隱形的。
		var a := Motion.pulse01(s.tick_count, Motion.AMBIENT, 0.72) * 0.92 * k
		ci.draw_arc(
			center(n["cell"]), float(def.get("range", 0.0)) * Shapes.GRID, 0.0, TAU, 64,
			Palette.alpha(Palette.ORDER_CYAN, a), 2.0
		)


## 一條導管：受損光暈、線本體、等級刻度。`flow`／`starving` 是這一 tick 的推導值（`_sync_conduits()` 算好給它）。
func _draw_conduit(ci: CanvasItem, c: Dictionary, flow: float, starving: bool) -> void:
	var bonus := float(s.mods["cap_bonus"])
	var cap := Build.conduit_cap(int(c["level"]), bonus)
	# 線寬的分母是**全遊戲的最大 cap**，不是這條線自己的——粗細因此在
	# 全圖上可以互相比較，而且加粗一條線之後它會真的變粗（B1.1 使用者回報）。
	var w := Shapes.conduit_width(flow, Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus))
	# 受損：先鋪一圈 warn.orange 光暈。**線被打斷之前要先看得出它在挨打**，
	# 否則產能中斷對玩家來說會是憑空發生的。
	if float(c["hp"]) < 40.0:
		var hurt := 1.0 - float(c["hp"]) / 40.0
		ci.draw_line(
			center(c["a"]), center(c["b"]),
			Palette.alpha(Palette.WARN_ORANGE, 0.25 + 0.55 * hurt), w + 6.0
		)
	ci.draw_line(center(c["a"]), center(c["b"]), Palette.conduit(flow, cap, starving), w)
	# 升級過的幹線在端點加刻度，讓「我升過這條」在無數值下也看得見。
	# **垂直短刻線，不是圓點**：圓點會和流動珠混成同一個東西，而兩者語意相反
	# （固定的線材等級 vs 變動的流量）——`20_ART_DIRECTION.md` §1.4a。
	var pa := center(c["a"])
	var pb := center(c["b"])
	var perp := (pb - pa).normalized().orthogonal()
	# ★ B1.6.1：刻度必須**明確伸出管緣**。原本固定 ±5px，而滿載的管子
	#   本身就有 8px 寬——刻度只比它寬一點點，畫成近白青之後讀起來是
	#   「管子這裡破了一個洞」（使用者回報「有破圖」）。
	#   現在長度跟著線寬走並固定外露 3px，而且貼在起點端而不是線長 12%
	#   那個沒有意義的位置：等級是這條線的屬性，標在接頭上才讀得出來。
	var reach := w * 0.5 + 3.0
	var tick_w := maxf(1.5, 2.0 / maxf(0.2, zoom))
	var step := maxf(3.0, 4.0 / maxf(0.2, zoom))
	# 起點要**閃過節點自己的圖形**：節點最大到半徑 13（碎浪的外框），
	# 貼太近就被畫在它底下看不見（第一版貼 6px，截圖當場抓到）。
	# 短線上再夾一次，免得刻度跑過中點看起來像掛在另一端。
	var span := pa.distance_to(pb)
	var head := minf(17.0, span * 0.32)
	for i in range(int(c["level"])):
		var at := pa + (pb - pa).normalized() * (head + step * float(i))
		ci.draw_line(at - perp * reach, at + perp * reach, Palette.ORDER_BRIGHT, tick_w)


## ★ 本 tick 的流動珠規格（B3.15）：每一列 `[起點, 單位方向, 線長, 半徑, 描邊半徑, 淨流量, 相位偏移, 顏色]`。
##
## 珠子**每幀都在動**，但「哪幾條線上有珠子、什麼顏色、多寬」只隨 tick 與建造改變——
## 所以規格在快取層失效時算一次（`_process()`），每幀只拿它推位置（`_update_beads()`）。
func _bead_specs() -> Array:
	var specs: Array = []
	var flows: Dictionary = s.rates["conduit_flow"]
	var nets: Dictionary = s.rates["conduit_net"]
	var bonus := float(s.mods["cap_bonus"])
	var cap_max := Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus)
	# ★ 描邊是**螢幕固定粗細**（B1.6.1）。原本是固定 +1.2 地圖 px：在 r=1.4 的
	#   細線上，光暈佔了直徑的 46%，讀起來是「管子上的洞」而不是「在跑的東西」；
	#   而放大到 300% 時它又變成一圈很粗的黑框。1px 螢幕在任何倍率下都只是描邊。
	var edge := 1.0 / maxf(0.2, zoom)
	for c: Dictionary in s.conduits:
		# ★ 流動珠：礦砂／能量／合金各一列，各自往自己的淨流向跑（§1.4a）。
		var net: Vector3 = (nets as Dictionary).get(c["id"], Vector3.ZERO)
		# 只有一種資源在跑時**走線的正中央**：多數導管都是這種，
		# 硬要分排會讓珠子懸在細線外面，看起來像掉出來的東西。
		# 三種同時跑的線（熔爐那條）中間讓給合金，礦砂與能量各退一邊。
		# ★ B1.6.1：珠子**一律走中線**，多種資源沿長度錯開相位，不再各佔一排。
		#
		# 原本是垂直偏移 `w * 0.45 + 1.0`，而它沒有夾在管子裡：8px 寬的線上
		# 偏移 4.6 ＋ 珠半徑 2.6 ＋ 光暈 1.2 ＝ 8.4，遠超過半寬 4——**珠子兩側
		# 都掛在管子外面**，看起來像從管子裡漏出來的（使用者回報「有破圖」）。
		#
		# 夾住偏移不是辦法：真的夾進去之後三排珠子會擠成一團更難讀。
		# 改成共用中線、**相位錯開**：白、琥珀、紫依序前進，位置不再承載資訊
		# （那本來也不是它該講的事），顏色照樣分得出是哪一種資源。
		var lanes: Array = []
		for pair: Array in [
			[net.x, Palette.TEXT_PRIMARY], [net.y, Palette.ENERGY_AMBER],
			[net.z, Palette.ALLOY_VIOLET],
		]:
			if absf(float(pair[0])) >= BEAD_MIN_RATE:
				lanes.append(pair)
		if lanes.is_empty():
			continue
		var w := Shapes.conduit_width(float(flows.get(c["id"], 0.0)), cap_max)
		var pa := center(c["a"])
		var pb := center(c["b"])
		var span := pa.distance_to(pb)
		if span < 1.0:
			continue
		var u := (pb - pa) / span
		# 珠子大小跟著線寬走：這樣它**強化**「線寬＝流量」而不是把線戳成虛線。
		# 固定大小的珠子在 2px 的細線上會蓋掉整條線，粗細那條資訊就沒了（R-3）。
		# ★ 上限收到半寬：珠子不得比管子胖，否則它就是「管子上的腫塊」。
		var r := clampf(w * 0.30, 1.4, w * 0.5)
		# 礦砂珠用 `text.primary`（近白）而不是 `order.bright`：導管本身就是亮青，
		# 亮青珠子在亮青線上只讀得出「這裡有個洞」，讀不出「有東西在跑」。
		# 能量珠的琥珀、合金珠的紫本來就與線色分屬不同色相，維持配色紀律 2。
		for i in lanes.size():
			var lane_phase := float(i) / float(lanes.size())
			specs.append([pa, u, span, r, r + edge, float(lanes[i][0]), lane_phase * BEAD_GAP, lanes[i][1]])
	return specs


## ★ 流動珠（`20_ART_DIRECTION.md` §1.4a）。線寬與顏色說的是「這條線有多滿」，
## 沒有任何元素在說「東西正在動」——一張靜態的粗線看起來是接線圖，不是產線。
##
## **這不是實體物品搬運。** 珠子的位置由已解出的流率 ＋ 經過的模擬秒數推算，
## 模擬層一無所知，珠子不參與任何判定（`10_GDD.md` §3.1 鎖定：流量網路）。
## 一旦它變成有位置有狀態的實體，`O(物品數)` 的效能與確定性負債就回來了。
##
## `amount` 帶號：正＝沿 a→b、負＝反向。速度 ∝ 流率，間距固定。
## 相位偏移（規格的 `off`）：多種資源在同一條線上時用它錯開，
## 於是白、琥珀、紫依序前進而不是疊在一起（B1.6.1）。
##
## ★ B3.15：**整個珠子層是一個 `MultiMesh`**。原本每顆珠子兩次 `draw_circle`
##   （RG-184：第 10 關約 600 次、每幀 4 ms 的 GDScript 與近千個 draw call）；
##   現在每顆是**兩個實例**（先深色描邊、再本色，順序與原本逐顆交錯的畫法相同），
##   GDScript 只把位置寫進一塊緩衝區，一次交給引擎，一個 draw call。圓是同一個 64 邊扇形。
func _update_beads() -> void:
	var specs := _bead_specs_cache
	if specs.is_empty():
		if _bead_mm.visible_instance_count != 0:
			_bead_mm.visible_instance_count = 0
		return
	# 相位用模擬秒數推（tick 數 ＋ 幀內插值），不用系統時間：
	# 渲染可以不確定，但別引入新的亂數源。`TL_SHOT` 下模擬凍結 → 珠子也凍結。
	var t: float = (float(s.tick_count) + scr.accum / BattleController.TICK) * BattleController.TICK
	var buf := _bead_buf
	var n := 0
	for sp: Array in specs:
		var a: Vector2 = sp[0]
		var u: Vector2 = sp[1]
		var span: float = sp[2]
		var r: float = sp[3]
		var ro: float = sp[4]
		var oc: Color = Palette.BG_DEEP
		var col: Color = sp[7]
		var x := fposmod(t * float(sp[5]) * BEAD_SPEED + float(sp[6]), BEAD_GAP)
		while x < span:
			var px := a.x + u.x * x
			var py := a.y + u.y * x
			# **深色描邊是這個元素能被看見的唯一原因**：導管本身就是亮青，
			# 亮青珠子畫在亮青線上等於沒畫（使用者實看 B0.6 時反映的正是這件事）。
			var o := n * BEAD_FLOATS
			buf[o] = ro
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 3] = px
			buf[o + 4] = 0.0
			buf[o + 5] = ro
			buf[o + 6] = 0.0
			buf[o + 7] = py
			buf[o + 8] = oc.r
			buf[o + 9] = oc.g
			buf[o + 10] = oc.b
			buf[o + 11] = oc.a
			o += BEAD_FLOATS
			buf[o] = r
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 3] = px
			buf[o + 4] = 0.0
			buf[o + 5] = r
			buf[o + 6] = 0.0
			buf[o + 7] = py
			buf[o + 8] = col.r
			buf[o + 9] = col.g
			buf[o + 10] = col.b
			buf[o + 11] = col.a
			n += 2
			x += BEAD_GAP
	_bead_mm.visible_instance_count = n
	_bead_mm.buffer = buf


## 規格換了之後，把緩衝區與 `MultiMesh` 的容量對到最壞情況（每條線每個相位都塞滿）。只增不減。
func _size_beads() -> void:
	var need := 0
	for sp: Array in _bead_specs_cache:
		need += 2 * (int(float(sp[2]) / BEAD_GAP) + 1)
	if need <= _bead_mm.instance_count:
		return
	var cap := maxi(64, _bead_mm.instance_count)
	while cap < need:
		cap *= 2
	_bead_mm.instance_count = cap
	_bead_buf.resize(cap * BEAD_FLOATS)


## 單位圓（半徑 1 的 64 邊扇形）。`draw_circle` 用的是同一種分割，所以珠子與原本幾乎逐像素相同（32 張截圖裡只有兩張各差圓邊緣 1 個像素——實例變換在 GPU 上算）。
func _unit_circle() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	pts.resize(BEAD_SEGMENTS + 1)
	for i in BEAD_SEGMENTS:
		var ang := TAU * float(i) / float(BEAD_SEGMENTS)
		pts[i] = Vector2(cos(ang), sin(ang))
		idx.append(i)
		idx.append((i + 1) % BEAD_SEGMENTS)
		idx.append(BEAD_SEGMENTS)
	pts[BEAD_SEGMENTS] = Vector2.ZERO
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## ★ 逐件快取的同步（B3.15）：**只在 tick、建造或縮放有變時跑**，把每一件的簽章對一遍，
## 簽章變了的那幾件才重畫。簽章要**收齊畫它會讀的每一個輸入**——少收一個，症狀就是那個輸入改了而畫面沒跟上
## （`TL_CLICKTEST` 的 `cache` 段落拿「逐件累積出來的畫面」對「全部重畫的畫面」逐像素比，守的就是這件事）。
func _sync_nodes() -> void:
	var node_state: Dictionary = s.rates["node_state"]
	var seen := 0
	for n: Dictionary in s.nodes:
		var id := int(n["id"])
		var rec: NodeRec = _node_recs.get(id)
		if rec == null:
			rec = _new_node_rec(n)
			_node_recs[id] = rec
		seen += 1
		var type := String(n["type"])
		var hot: bool = threat.has(n["cell"])
		# 圖形只讀（級數、血量、儲槽的充能、tick）；**tick 只有核心的心跳與受威脅的括號在用**，
		# 其餘的塔把 tick 放進簽章只會讓它每個 tick 白畫一次。
		var sig: Array = [
			int(n.get("level", 0)), float(n["hp"]),
			float(n.get("charge", 0.0)) if type == "silo" else 0.0,
			bool(engaged.get(int(n["id"]), false)), hot,
			int(node_state.get(id, SessionState.NORMAL)),
			s.tick_count if (hot or type == "core") else 0, Motion.reduce,
		]
		if sig == rec.sig:
			continue
		rec.sig = sig
		_node_geometry(rec)
		rec.shadow.repaint()
		rec.body.repaint()
	if seen != _node_recs.size():
		var live: Dictionary = {}
		for n: Dictionary in s.nodes:
			live[int(n["id"])] = true
		for id: int in _node_recs.keys():
			if not live.has(id):
				var rec: NodeRec = _node_recs[id]
				rec.shadow.queue_free()
				rec.body.queue_free()
				_node_recs.erase(id)


func _sync_conduits() -> void:
	var flows: Dictionary = s.rates["conduit_flow"]
	var sat: Dictionary = s.rates["satisfaction"]
	# 「這條線的終點是哪個節點」建一次索引：每條線各掃一次節點是 O(導管 × 節點)——
	# 壓力場景（2045 條 × 547 座）光這一項就是每幀約 50 ms。
	var node_at: Dictionary = {}
	for n: Dictionary in s.nodes:
		node_at[n["cell"]] = int(n["id"])
	for c: Dictionary in s.conduits:
		var id := int(c["id"])
		var rec: ConduitRec = _conduit_recs.get(id)
		if rec == null:
			rec = _new_conduit_rec(c)
			_conduit_recs[id] = rec
		var flow := float(flows.get(id, 0.0))
		var to_id: int = node_at.get(c["b"], -1)
		var starving: bool = to_id >= 0 and float(sat.get(to_id, 1.0)) < 0.95 and flow > 0.0
		# 受損光暈只在血量低於 40 時畫，所以簽章裡的血量在 40 以上一律當 40。
		var sig: Array = [int(c["level"]), flow, starving, minf(float(c["hp"]), 40.0), zoom]
		if sig == rec.sig:
			continue
		rec.sig = sig
		rec.flow = flow
		rec.starving = starving
		rec.item.repaint()
	if _conduit_recs.size() != s.conduits.size():
		var live: Dictionary = {}
		for c: Dictionary in s.conduits:
			live[int(c["id"])] = true
		for id: int in _conduit_recs.keys():
			if not live.has(id):
				var rec: ConduitRec = _conduit_recs[id]
				rec.item.queue_free()
				_conduit_recs.erase(id)


## 新增一件：畫布項**接在群組最後面**，所以樹的順序永遠等於 `s.nodes`／`s.conduits` 的順序
## （節點只會尾端新增、原地移除），也就是原本逐件呼叫的繪圖順序。
func _new_node_rec(n: Dictionary) -> NodeRec:
	var rec := NodeRec.new()
	rec.node = n
	rec.shadow = StageLayer.new()
	rec.shadow.painter = _paint_node_shadow.bind(rec)
	_node_shadow_group.add_child(rec.shadow)
	rec.body = StageLayer.new()
	rec.body.painter = _paint_node_body.bind(rec)
	_node_body_group.add_child(rec.body)
	return rec


func _new_conduit_rec(c: Dictionary) -> ConduitRec:
	var rec := ConduitRec.new()
	rec.c = c
	rec.item = StageLayer.new()
	rec.item.painter = _paint_conduit.bind(rec)
	_conduit_group.add_child(rec.item)
	return rec


## 簽章變了就重建這一座的幾何（建一次，落影與塔身兩個畫布項共用）。
func _node_geometry(rec: NodeRec) -> void:
	var n := rec.node
	rec.at = center(n["cell"])
	rec.parts = Glyphs.build_for(n, rec.at, s.tick_count)
	if rec.parts.is_empty():
		# 對不到的型別＝隱形的塔。記下來讓 `_glyph_selftest` 變紅（B2.4.6）。
		_no_glyph[String(n["type"])] = true
		return
	rec.sc = Glyphs.scale_for(n)


## 換局、或要整批重畫時，丟掉所有逐件的畫布項。
func _clear_elements() -> void:
	for rec: NodeRec in _node_recs.values():
		rec.shadow.queue_free()
		rec.body.queue_free()
	for rec: ConduitRec in _conduit_recs.values():
		rec.item.queue_free()
	_node_recs.clear()
	_conduit_recs.clear()


## 讓下一次同步把每一件都重畫一遍（只清簽章，畫布項留著）。
func _forget_signatures() -> void:
	for rec: NodeRec in _node_recs.values():
		rec.sig = []
	for rec: ConduitRec in _conduit_recs.values():
		rec.sig = []


func _paint_conduit(ci: CanvasItem, rec: ConduitRec) -> void:
	Prof.mark()
	_draw_conduit(ci, rec.c, rec.flow, rec.starving)
	Prof.lap("paint.conduit")


## 落影：**全部節點的落影在全部塔身之前**（B3.11）——一座塔的影子偏出格線那兩個像素只准壓在背景與導管上，
## 不准壓在鄰居已經畫好的血條與徽章上（`Shapes.SHADOW_OFF` 的原註；`body_extent()` 守的正是那一格）。
## 兩個群組各是一層，所以這條順序是結構保證的，不是靠呼叫順序。
func _paint_node_shadow(ci: CanvasItem, rec: NodeRec) -> void:
	if rec.parts.is_empty():
		return
	Prof.mark()
	_scaled(ci, rec.at, rec.sc, true)
	Glyphs.paint_shadows(ci, rec.parts)
	_scaled(ci, rec.at, rec.sc, false)
	Prof.lap("paint.node")


func _paint_node_body(ci: CanvasItem, rec: NodeRec) -> void:
	if rec.parts.is_empty():
		return
	Prof.mark()
	var nd := rec.node
	var p := rec.at
	var full := NodeDefs.hp(String(nd["type"]))
	var lv := int(nd.get("level", 0))
	# ★ B3.10：血條也夾在半格內——它畫在塔身下緣，跟著沒有上限的體積通道長
	#   就會落進下面那一格（塔身本身由 `Shapes.fit_scale()` 夾住）。
	var bar_sc := minf(Shapes.level_scale(lv), Shapes.GRID * 0.5 / 15.0)
	if float(nd["hp"]) < full:
		# **血條不是圓環**：儲槽的充能也是琥珀色圓弧，兩個圓弧疊在同一顆
		# 12px 的節點上肉眼分不出來。形狀不同才分得開。
		var frac := clampf(float(nd["hp"]) / full, 0.0, 1.0)
		var bar := Vector2(24.0, 3.0)
		var bar_at := p + Vector2(-bar.x * 0.5, 15.0 * bar_sc)
		ci.draw_rect(Rect2(bar_at, bar), Palette.alpha(Palette.BG_DEEP, 0.8))
		ci.draw_rect(Rect2(bar_at, Vector2(bar.x * frac, bar.y)), Palette.WARN_ORANGE)
	_scaled(ci, p, rec.sc, true)
	Glyphs.paint_bodies(ci, rec.parts, p)
	_scaled(ci, p, rec.sc, false)
	_draw_threat(ci, nd["cell"], p)
	_draw_engaged(ci, nd, p)
	# ★ B3.9.3：零件長在塔身周圍而不是頭上那一條帶子，所以缺料徽章（y −16 起）
	#   不必再讓位——它是**地圖上唯一指出瓶頸的元素**。
	_draw_badge(ci, nd, p)
	Prof.lap("paint.node")


## ★ 「以某一格為中心放大 `sc` 倍」的畫布變換，開／關（B3.9.2a）。
##
## ⚠ **`draw_set_transform()` 是取代，不是疊加**（使用者回報「升級完之後鼠標跟
##   遊戲指定的格子會有 offset，升級的東西會不見」）。B3.9 這裡直接蓋掉了
##   `_draw()` 開頭那一層地圖變換（原點＋縮放），於是①升過級的塔畫到別的地方去，
##   ②還原成**單位矩陣**使那一幀後面畫的每一樣東西都少掉原點與縮放。
##   算式收在 `Shapes.level_xform()`（`hud_test` 釘著），這裡只負責開與關——
##   而**關一定要關回地圖那一層**，不是關回單位矩陣。
##   `sc == 1.0`（0 級、預覽）時兩邊都是空操作。
func _scaled(ci: CanvasItem, p: Vector2, sc: float, on: bool) -> void:
	if sc == 1.0:
		return
	# ★ B3.15：圖層（`StageLayer`）自己的 transform 已經帶著原點與縮放，所以這裡只剩「以 p 為中心放大 sc 倍」；
	#   本體（`ci == self`，擺放預覽走這條）的地圖變換則在 `_draw()` 開頭，要連同原點一起重組。
	if ci == self:
		if on:
			draw_set_transform_matrix(Shapes.level_xform(_map_origin(), zoom, p, sc))
		else:
			draw_set_transform(_map_origin(), 0.0, Vector2(zoom, zoom))
	elif on:
		ci.draw_set_transform_matrix(Shapes.level_xform(Vector2.ZERO, 1.0, p, sc))
	else:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ★ 一座節點**畫成什麼樣子**——只看型別，不看它蓋起來沒有（B3.4）。
##
## 擺放預覽走的是它：十四種節點各有自己的幾何，抄一份的下場是日後加第十五種時
## 只有一邊記得加——而漏掉的那一邊**症狀是隱形而不是報錯**（`_no_glyph` 就是
## 為此而生）。B3.11 起幾何本身在 `Glyphs.build()`（純函式，名冊與標題畫面也用
## 同一份），這裡只剩「建、縮放、上色」三步。
##
## `n` 只需要 `type`；`hp`／`charge`／`level` 缺了就當作滿血、空槽、0 級。
func _draw_node_body(n: Dictionary, p: Vector2) -> void:
	var parts: Array = Glyphs.build_for(n, p, s.tick_count)
	if parts.is_empty():
		_no_glyph[String(n["type"])] = true
		return
	var sc := Glyphs.scale_for(n)
	_scaled(self, p, sc, true)
	Glyphs.paint(self, parts, p)
	_scaled(self, p, sc, false)


## ★ 交戰指示：**琥珀＝能量**（配色紀律 2）。有環＝這座塔本 tick 正在吃電。
## 它只講「在不在吃電」；「吃不吃得飽」由三態徽章講（B0.6 前這裡還多畫一段
## 橙色缺口弧，那和 `缺料` 徽章編碼的是同一件事，留一個就好）。
func _draw_engaged(ci: CanvasItem, n: Dictionary, p: Vector2) -> void:
	if engaged.get(int(n["id"]), false):
		# ★ B3.9：半徑跟著級數長，否則滿級的塔會把環頂穿。
		# ★ B3.10：但夾在半格內——它是交戰指示不是射程圈，越過格線就變成
		#   「這一格和隔壁那一格都在吃電」。
		ci.draw_arc(p, minf(15.0 * Shapes.level_scale(int(n.get("level", 0))), Shapes.GRID * 0.5),
			0.0, TAU, 32, Palette.ENERGY_AMBER, 2.0)


## ★ 節點三態徽章（`10_GDD.md` §3.1）。**`正常` 不畫任何東西**——徽章是例外
## 標記，一屏 14 個節點全掛上「我很好」等於把要找的那兩個埋進雜訊裡。
## 靠**形狀**分辨而不只是顏色：倒三角＝空的（缺料）、正三角＝滿的（滿溢）。
##
## ★ **缺料再分兩種**（B2.4.8，遊玩測試 P2-1）：倒三角＝缺礦砂、閃電＝缺電。
##   舊版兩種共用一個橙色倒三角，於是這個「地圖上唯一指出瓶頸的元素」
##   說得出誰在餓、說不出餓的是什麼——而那正是全案核心命題的那一刀。
##   形狀與顏色**同時**不同（§1.6 說換顏色不夠、要換形狀，這裡兩個都換）：
##   閃電走 `energy.amber`，因為 §1.1 配色紀律 2 說琥珀專屬於能量——
##   這一次那條紀律是在幫忙，不是在擋路。
func _draw_badge(ci: CanvasItem, n: Dictionary, p: Vector2) -> void:
	match int((s.rates["node_state"] as Dictionary).get(int(n["id"]), SessionState.NORMAL)):
		SessionState.STARVED:
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-7, -25), p + Vector2(7, -25), p + Vector2(0, -16)
			]), Palette.WARN_ORANGE)
		SessionState.STARVED_POWER:
			# 五點折線的閃電。**不用描邊**：14px 高的東西加外框只會糊掉。
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(2, -27), p + Vector2(-6, -19), p + Vector2(-1, -19),
				p + Vector2(-3, -13), p + Vector2(6, -22), p + Vector2(1, -22),
			]), Palette.ENERGY_AMBER)
		SessionState.OVERFLOW:
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -25), p + Vector2(7, -16), p + Vector2(-7, -16)
			]), Palette.ORDER_BRIGHT)


## 開火線。留 `SHOT_TTL` 個 tick 並隨之淡出——瞬間閃一下的線等於沒畫。
## ★ 四種開火形態（B1.6.3，`20_ART_DIRECTION.md` §1.7）：彈丸＝物理、光束＝能量、
## 濺射環、回收珠。**形態由 `NodeDefs` 既有的機制欄位推導，不新增美術欄位。**
## 琥珀專屬於能量這個**資源**（§1.1 配色紀律），所以能量傷害用形狀（光束）不用
## 顏色講；回收者那顆琥珀珠是唯一的例外，而它是對的：那顆珠真的是能量，正在流回電網。
##
## ★ B3.11 補上開火的**兩端**：砲口一閃（`_shot_muzzle`）與命中一濺（`_shot_impact`）。
##   原本一發彈丸是「憑空出現、憑空消失」——出手與落點都沒有回饋，玩家看得到線，
##   看不到「打到了」。兩者都是 0.2 秒、十來個像素的東西，`reduce` 時不畫（§4.4）。
func _draw_shots() -> void:
	var frac: float = scr.accum / BattleController.TICK
	for sh: Dictionary in s.shots:
		# 沒有 `by` 的一律當錨（`TL_CLICKTEST` 手塞的那一發）。
		var def := NodeDefs.of(String(sh.get("by", "anchor")))
		var a := center(sh["from"])
		# ★ 落點鎖定敵人本體（B3.12，`_shot_anchor()`）。B3.11 吸附到「那一格裡的
		#   敵人」還不夠：彈丸活 3 個 tick，敵人這期間走出那一格就退回了格心。
		var b := _shot_anchor(sh, "target", "prog", "to")
		var t := Motion.progress(BattleController.SHOT_TTL, int(sh["ttl"]), frac)
		var fade := 1.0 - t
		var beam: bool = bool(def.get("pierce", false))
		_shot_muzzle(a, t, beam)
		if beam:
			_shot_beam(a, b, fade)
			continue
		_shot_bolt(a, b, t, fade)
		_shot_impact(b, t)
		# 濺射環只掛在這一發濺射的**第一筆**記錄上（`BattleController`），
		# 所以這裡畫幾次就是幾發，不會被打中的隻數放大。
		if sh.has("splash_at"):
			_shot_splash(
				_shot_anchor(sh, "splash_target", "splash_prog", "splash_at"),
				t, fade, float(def.get("splash", 0.0))
			)
		if float(def.get("reclaim", 0.0)) > 0.0:
			_shot_reclaim(a, b, t)


## 一發的落點（B3.12）。**鎖定敵人本體**：記錄裡有 `target`（敵人 id）就畫在那一隻
## **此刻**的位置——彈丸活 3 個 tick，敵人在這期間會走出原本那一格，退回格心的話
## 彈頭與火花就落在它身後半格到一格（使用者回報「特效跑掉、不往敵人身上打」）。
## 那一隻已經死了就畫在它**被打中時**的位置（`prog`，碎片爆也在那裡）；
## 兩者都沒有（`TL_CLICKTEST` 手塞的那一發）才退回格心。
func _shot_anchor(sh: Dictionary, id_key: String, prog_key: String, cell_key: String) -> Vector2:
	if sh.has(id_key):
		var i: int = _enemy_index.get(int(sh[id_key]), -1)
		if i >= 0 and i < s.enemies.size():
			return _enemy_pos(s.enemies[i], i)
	if sh.has(prog_key):
		return _path_px(float(sh[prog_key]))
	return center(sh[cell_key])


## id → `s.enemies` 索引，每幀建一次（B3.12）。彈丸記的是 id（敵人會死、陣列會縮），
## 畫的時候要找得到那一隻此刻在哪。
func _index_enemies() -> Dictionary:
	var out: Dictionary = {}
	for i in s.enemies.size():
		out[int((s.enemies[i] as Dictionary)["id"])] = i
	return out


## 砲口閃光：出手那一瞬在塔上開一顆亮青的菱形，半個 `SHOT_TTL` 內收掉。
## 菱形是秩序側的語彙（四個角、對齊軸），和敵人那邊的圓形閃光分得開。
## 光束（稜鏡）多一圈柔光——它的出手是「整條亮起」，源頭要更亮一點才讀得出方向。
func _shot_muzzle(a: Vector2, t: float, beam: bool) -> void:
	if Motion.reduce or t >= 0.5:
		return
	var k := 1.0 - t / 0.5
	if beam:
		draw_circle(a, 4.0 + 4.0 * k, Palette.alpha(Palette.ORDER_BRIGHT, 0.35 * k))
	draw_colored_polygon(
		Shapes.ngon(a, 3.0 + 5.0 * k, 4, 0.0), Palette.alpha(Palette.ORDER_BRIGHT, 0.85 * k)
	)


## 命中火花：彈丸抵達的那一刻在落點炸開一顆四角星，擴張並淡出。
## 起點在 `t = 0.6`——`ease_out_cubic(0.6) ≈ 0.94`，彈頭已經貼到目標。
func _shot_impact(b: Vector2, t: float) -> void:
	if Motion.reduce or t < 0.6:
		return
	var k := (1.0 - t) / 0.4
	var r := 3.0 + 6.0 * (1.0 - k)
	draw_colored_polygon(
		Shapes.star(b, r, r * 0.4, 4, PI * 0.25), Palette.alpha(Palette.ORDER_BRIGHT, 0.9 * k)
	)


## 能量貫穿（稜鏡）：**整條線一次亮到底**，寬度 3→1 衰減。
## 貫穿本來就是「這條軸線上的都被打到」，光束是它唯一誠實的畫法。
## 同一 tick 會有多發（每個目標一發）疊在同一條軸線上——那不是缺陷，
## 疊出來的亮度差正好說明「近的那幾隻被打得比較集中」。
func _shot_beam(a: Vector2, b: Vector2, fade: float) -> void:
	draw_line(a, b, Palette.alpha(Palette.ORDER_BRIGHT, 0.10 + 0.18 * fade), 6.0)
	draw_line(a, b, Palette.alpha(Palette.ORDER_BRIGHT, 0.35 + 0.65 * fade), 1.0 + 2.0 * fade)


## 物理彈丸（錨／回收者／碎浪）：**短促實心的一段沿線飛行**，不是整條線亮起。
## 「有質量的東西飛過去」和「一束光」的差別全在這裡——整條線亮起讀起來
## 永遠是能量，不管畫成什麼顏色。
func _shot_bolt(a: Vector2, b: Vector2, t: float, fade: float) -> void:
	var dir := (b - a)
	var len := dir.length()
	if len < 0.001:
		return
	dir /= len
	# 彈丸長度上限 14px：短程時不可以比整條彈道還長，否則它就變回一條線了。
	var bolt := minf(14.0, len * 0.45)
	var head := a + dir * (bolt + (len - bolt) * Motion.ease_out_cubic(t))
	draw_line(head - dir * bolt, head, Palette.alpha(Palette.ORDER_CYAN, 0.45 + 0.55 * fade), 3.0)


## 濺射（碎浪）：命中點一圈**擴張環**，半徑就是資料裡的 `splash` 格。
## ★ 這個範圍原本玩家**完全看不到**——碎浪比錨貴、吃三座錨的電，
## 而它唯一的賣點（打到一整段隊列）在畫面上沒有任何證據。
func _shot_splash(at: Vector2, t: float, fade: float, splash: float) -> void:
	var r := splash * Shapes.GRID * Motion.ease_out_cubic(t)
	draw_arc(at, r, 0.0, TAU, 28, Palette.alpha(Palette.ORDER_CYAN, 0.15 + 0.45 * fade), 2.0)


## 回收（回收者）：命中後一顆 `energy.amber` 珠**回流到塔**。
## 方向是反的——它送回來的東西才是這座塔存在的理由（§7.4「打破峰值約束
## 的鑰匙」）。走 `t` 的後半段：先看到打中，才看到收回來，因果順序不能反。
func _shot_reclaim(a: Vector2, b: Vector2, t: float) -> void:
	if t < 0.4:
		return
	var k := (t - 0.4) / 0.6
	draw_circle(b.lerp(a, Motion.ease_out_cubic(k)), 3.0, Palette.alpha(Palette.ENERGY_AMBER, 1.0 - k))


## 敵潮屬於**混沌**側（`20_ART_DIRECTION.md` §0）：不規則凸包、不對齊網格、
## 呼吸式脈動。玩家的一切則是正圓正方、嚴格對齊——這個對比就是主題本身。
## ★ B3.12：幾何搬進 `render/2d/Foes.gd`（純函式、全由機制欄位推導；`hud_test` 量它
##   的行進軸 footprint）。這裡只剩**狀態**：受擊亮階、被光環抓住的青圈、血量弧
##   ——三者各答一題、形狀各不相同（§4.3b）。
func _draw_enemies() -> void:
	var now := _time_s()
	# ★ B3.15：視野外的敵人不畫（放大看大圖時，其餘的敵人白白建幾何、白白發指令）。
	#   邊距收得比最大的敵人（半徑約 14）加血量弧寬鬆；一屏可見的戰役關卡這條永遠為真。
	var view := view_world_rect().grow(48.0)
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		var def := Enemies.of(String(e["type"]))
		var p := _enemy_pos(e, i)
		if not view.has_point(p):
			continue
		var r := float(def.get("radius", 9.0))
		# ★ 受擊一閃（B3.11）：這一 tick 有彈落在它身上，本體往亮階推 0.2 秒。
		#   純渲染推導（`_hit_ids`），仍在品紅色相內、不動用橙（§1.7）。
		var hit: bool = _hit_ids.has(int(e["id"]))
		var parts: Array = Foes.build(def, int(e["id"]), p, _enemy_dir(e, i), now, hit)
		Foes.paint(self, parts)
		# ★ 被潮鳴抓住的敵人：輪廓描一圈 `order.cyan`（B1.8）。**標在敵人身上而不是
		#   塔上**——減速作用在它身上，標在這裡因果才讀得出來。
		var slow := 0.0 if i >= _auras.size() else (_auras[i] as Vector2).x
		if slow > 0.01:
			for rim: PackedVector2Array in Foes.outlines(parts):
				draw_polyline(rim, Palette.alpha(Palette.ORDER_CYAN, 0.35 + 1.4 * slow), 2.0)
		# 血量弧。★ 分母是這一隻的 `max_hp`（無盡曲線 × 難度層乘過的），不是表上的原值
		#   ——原本讀表值，第 10 波之後血 2.5 倍的敵人要掉到表值以下才開始有弧。
		var frac := float(e["hp"]) / maxf(1.0, float(e.get("max_hp", def.get("hp", 1.0))))
		if frac < 1.0:
			draw_arc(p, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 20, Palette.TIDE_DEEP, 2.0)


## 這一 tick 被打中的敵人（B3.11，B3.12 改成以 **id** 為鍵）：剛生出來（`ttl` 還滿
## 或剛減一格）的那幾發的目標。0.2 秒的亮階，和碎片爆一樣是渲染層的事，不進
## `state_hash()`。沒有 `target` 的那一發（`TL_CLICKTEST` 手塞的）退回「那一格裡的第一隻」。
func _hit_ids_of() -> Dictionary:
	var out: Dictionary = {}
	for sh: Dictionary in s.shots:
		if int(sh["ttl"]) < BattleController.SHOT_TTL - 1:
			continue
		if sh.has("target"):
			out[int(sh["target"])] = true
			continue
		var i := _enemy_cells.find(sh["to"])
		if i >= 0 and i < s.enemies.size():
			out[int((s.enemies[i] as Dictionary)["id"])] = true
	return out


## ★ 開打的漣漪（B3.11）。號令有聲音（`wave_start`）但畫面上沒有對應物：
## 潮從入口湧進來那一刻，在路徑起點放兩圈擴張的品紅環——它答的是「潮從**哪裡**
## 進來」，新玩家的第一個問題（§1.6 來襲箭羽的同一題，這是它的動態版）。
## 零 RNG、由 `phase_time` 驅動；`reduce` 時不畫（§4.4）。只在 wave 的前 1.2 秒存在。
func _draw_ripple() -> void:
	if Motion.reduce or s.phase != "wave" or s.path.is_empty():
		return
	var age: float = float(s.phase_time) + scr.accum
	if age > RIPPLE_SEC:
		return
	var at := center(s.path[0])
	for lag: float in [0.0, 0.25]:
		var k := clampf((age - lag) / (RIPPLE_SEC - lag), 0.0, 1.0)
		if k <= 0.0:
			continue
		var e := Motion.ease_out_cubic(k)
		draw_arc(
			at, 6.0 + 46.0 * e, 0.0, TAU, 32,
			Palette.alpha(Palette.TIDE_MAGENTA, (1.0 - k) * 0.7), 3.0 - 1.5 * k
		)


## ★ 「正在被啃」的格（B1.6，§4.3「一定要動」清單）。
##
## 敵人 walk-by 每 tick 傷害相鄰 1 格（`Tide.BLAST`），但在畫面上**那一刻完全
## 沒有表現**——節點的血條會慢慢變短，而玩家不知道「現在」有東西在被吃。
## 這裡把模擬層每 tick 都在做的同一份判定畫出來，不新增任何狀態。
func _threat_cells(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in cells:
		for dx in range(-Tide.BLAST, Tide.BLAST + 1):
			for dy in range(-Tide.BLAST, Tide.BLAST + 1):
				out[c + Vector2i(dx, dy)] = true
	return out


## 正在被啃的節點：脈動的**四角括號**。
##
## ★ **形狀必須和「交戰中」的圓環分得開**（第一版就是圓環，截圖當場抓到——
## 交戰環是琥珀圓環、受擊環是橙色圓環，兩個疊在同一顆 12px 的節點上肉眼
## 分不出來）。這是這個專案第二次踩同一個坑：B0.6 的「血條不是圓環」也是
## 因為儲槽充能弧與血條弧撞在一起。**同一個位置上的兩個訊息，換顏色不夠，
## 要換形狀。**
func _draw_threat(ci: CanvasItem, cell: Vector2i, p: Vector2) -> void:
	if not threat.has(cell):
		return
	var a := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.3)
	var col := Palette.alpha(Palette.WARN_ORANGE, a)
	var h := Shapes.GRID * 0.5 - 1.0   # 半格：括號貼著這一格的邊界
	var arm := 6.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := p + Vector2(sx * h, sy * h)
			ci.draw_line(corner, corner - Vector2(sx * arm, 0.0), col, 2.0)
			ci.draw_line(corner, corner - Vector2(0.0, sy * arm), col, 2.0)


## ★ 碎片爆（B1.6）。規格直接來自 `20_ART_DIRECTION.md` §161 的反模式清單：
## **「爆炸不用 200 顆粒子。用 3–5 個幾何碎片＋一次縮放閃光」**。
##
## 碎片的形狀服從核心視覺命題（§0 秩序 vs 混沌）——這不是裝飾選擇：
##   `chaos`（敵人消散）＝**不規則三角碎片**、品紅、往外飛並旋轉
##   `order`（建築破裂）＝**正方碎片**、青、往外飛但**不旋轉**（秩序連壞掉都是方的）
## 兩種都配一次縮放閃光環：混沌用實心淡去、秩序用線框擴張。
##
## 零 RNG（`Motion.fragment_dir` 由來源 id 決定方向），所以重播與每日挑戰
## 看到的是同一場爆炸。
## ★ 屏障擋格（B2.1d，使用者指定「類似盾牌隔檔」）。
##
## 畫成**面向來向的一段弧**＋一次白閃：盾牌的語彙是「擋住」，不是「爆開」，
## 所以用弧線而不是圓（圓已經是碎片爆的語彙，兩者不能混）。
## 弧的張角隨減傷比例變大——擋掉四成和擋掉九成看得出差別。
##
## **只在能量傷害被吃掉時出現**，所以它同時回答了「為什麼我打不動」：
## 玩家看到盾就知道換物理傷害的塔（§3.5 的剋制表）。
func _draw_shields() -> void:
	var frac: float = scr.accum / BattleController.TICK
	for sh: Dictionary in s.shields:
		var t := Motion.progress(int(sh["life"]), int(sh["ttl"]), frac)
		var at: Vector2 = (
			Vector2(sh["at"] as Vector2i) * Shapes.GRID
			+ Vector2(Shapes.GRID, Shapes.GRID) * 0.5
		)
		var e := Motion.ease_out_cubic(t)
		# ★ **六邊形的護盾泡**，不是一段弧。
		#   第一版畫成朝 +X 的弧：在 32px 的格子上和敵人自己的輪廓分不開，
		#   而且「朝右」對一隻正在往下走的敵人沒有意義（我手上只有格子，
		#   沒有傷害來向）。改成封閉的六邊形之後**與方向無關**，
		#   而且六邊形是本作既有的「硬」語彙（甲殼就是六邊形，§1.7）。
		var r := Shapes.GRID * (0.62 + 0.22 * e)
		var poly := PackedVector2Array()
		for i in 7:
			var a := TAU * float(i) / 6.0 - PI / 2.0
			poly.append(at + Vector2(cos(a), sin(a)) * r)
		draw_polyline(poly, Palette.alpha(Palette.ORDER_BRIGHT, (1.0 - t) * 0.95), 3.0)
		# 擋掉越多，泡越實：40% 與 90% 看得出差別。
		var fill := clampf(float(sh["frac"]), 0.0, 1.0)
		draw_polyline(poly, Palette.alpha(Palette.ORDER_CYAN, (1.0 - t) * 0.45 * fill), 7.0)
		# 起手一瞬的白閃，讓「就是現在被擋了一下」讀得出來。
		if t < 0.35:
			draw_circle(at, Shapes.GRID * 0.30, Palette.alpha(Palette.ORDER_BRIGHT, (0.35 - t) * 1.6))


func _draw_bursts() -> void:
	var frac: float = scr.accum / BattleController.TICK
	for b: Dictionary in s.bursts:
		var life := int(b["life"])
		var t := Motion.progress(life, int(b["ttl"]), frac)
		# 玩家操作之外的系統事件，用 ease-out：一開始炸得快，尾巴慢慢淡（§4.2）。
		var e := Motion.ease_out_cubic(t)
		var at: Vector2 = (b["at"] as Vector2) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5
		var chaos: bool = String(b["kind"]) == "chaos"
		var col := Palette.TIDE_MAGENTA if chaos else Palette.ORDER_CYAN
		var seed_id := int(b["seed"])

		# ── 一次縮放閃光 ──────────────────────────────────────────────
		var flash := Palette.alpha(col, (1.0 - t) * (0.55 if chaos else 0.75))
		if chaos:
			draw_circle(at, 6.0 + 14.0 * e, flash)
		else:
			draw_arc(at, 4.0 + 18.0 * e, 0.0, TAU, 24, flash, 2.0)

		# ── 3–5 個幾何碎片 ────────────────────────────────────────────
		# 數量也由 id 決定（3/4/5 輪替），免得每一次爆炸的顆數都一樣。
		# ★ **數量不動**（§2 反模式清單擋著「200 顆粒子」），動的是**單片的尺寸、
		#   初速與明度**——§7.3 C-2：「3–5 個看不見的碎片等於沒做」。
		#   fit 倍率下一格只有 32px，原本 4–5px 的碎片是三個像素的事。
		var count := 3 + (absi(seed_id) % 3)
		for i in count:
			var dir := Motion.fragment_dir(seed_id, i, count)
			var p := at + dir * (10.0 + 34.0 * e)
			var r := (8.0 if chaos else 6.5) * (1.0 - 0.6 * t)
			# 生命前 30% 用亮階起亮再落回本色。**明度差在小尺寸下活得下來**——
			# 這正是 `tide.bright` 當初被建立的理由（§1.7），同一條經驗直接套用。
			var bright: Color = Palette.TIDE_BRIGHT if chaos else Palette.ORDER_BRIGHT
			var c := Palette.alpha(bright.lerp(col, minf(1.0, t / 0.3)), 1.0 - t)
			if chaos:
				# 不規則三角＋自轉：混沌連碎片都不對齊。
				var spin := float(seed_id) * 0.7 + t * 3.0
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(r * 1.4, 0).rotated(spin),
					p + Vector2(r, 0).rotated(spin + 2.3),
					p + Vector2(r * 0.8, 0).rotated(spin + 4.1),
				]), c)
			else:
				# 正方、不自轉：秩序的碎片仍然是軸對齊的方塊。
				draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), c)


## 敵人**此刻**的畫面位置（B3.12）。兩件事在這裡：
##   ① **置中於它的格**（`Tide.pos_of()`）：模擬用 `floor(progress)` 當格，原本的畫法
##      從格心往下一格插值——一隻 progress 3.9 的敵人畫在第 4 格正中央，而模擬、
##      射程判定、交戰括號都說它在第 3 格。塔看起來在打射程外的東西。
##   ② **tick 內外推**：模擬 10Hz、畫面 60Hz。原本敵人每 0.1 秒跳一次——§2.4 說的
##      「插值呈現」在敵人身上從來沒有實作（導管粗細有、敵人沒有）。用這一隻本 tick
##      的有效速度往前推 `_accum` 秒：`Tide.advance()` 就是這條線性式，所以到下一
##      tick 正好接上。夾在路徑終點（和模擬一樣不會衝過核心）；`TL_SHOT` 凍結時
##      `_accum` 恆為 0，同參數仍拍出同一張圖。
func _enemy_pos(e: Dictionary, i: int) -> Vector2:
	return _path_px(_enemy_prog(e, i))


## 這一隻此刻的 progress（外推過的）。減速讀本幀的 `_auras`，迅捷免疫（同模擬層）。
func _enemy_prog(e: Dictionary, i: int) -> float:
	var def := Enemies.of(String(e["type"]))
	var slow := 0.0 if i >= _auras.size() else (_auras[i] as Vector2).x
	if bool(def.get("swift", false)):
		slow = 0.0
	var ahead := float(def.get("speed", 1.0)) * (1.0 - slow) * minf(scr.accum, BattleController.TICK)
	return minf(float(e["progress"]) + ahead, float(s.path.size() - 1))


## 路徑上的連續位置 → 地圖 px。
func _path_px(prog: float) -> Vector2:
	return Tide.pos_of(s.path, prog) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 行進方向（單位向量），轉角處平滑過渡（`Tide.heading_of()`）。
func _enemy_dir(e: Dictionary, i: int) -> Vector2:
	return Tide.heading_of(s.path, _enemy_prog(e, i))


## tick 秒 ＋ tick 內已過的秒數：波動相位的時間軸（零 RNG，`TL_SHOT` 下凍結）。
func _time_s() -> float:
	return float(s.tick_count) * BattleController.TICK + minf(scr.accum, BattleController.TICK)


## ★ 被選取那一座：射程圈 ＋ **正在餵它電的那幾台**（B3.6）。
##
## 三個記號各答一個問題，而且**形狀各不相同**（§4.3b：同一張圖上的兩個訊息，
## 換顏色不夠）：
##   · 選取本身 ＝ 那一格的**方框**（和擺放預覽的框同一個語彙）
##   · 射程 ＝ 一個**圓弧**
##   · 供電來源 ＝ 來源那一格的**菱形**，加上沿途導管的高亮
##
## 供電鏈逆著本 tick 的**實際流向**走（`FlowNetwork.upstream_power()`），
## 不是「有沒有連著」——一座塔可能連著五條線而這一刻只有兩條在餵它。
func _draw_selection() -> void:
	# ★ 選著一條導管（B3.7）：把它整條描出來。用**外框而不是換色**——導管自己的
	#   顏色正在講流量與滿載（§1.4a），塗掉它等於為了指出一條線而讓它不能讀。
	var wi: int = scr.inspector.sel_wire_index()
	if wi >= 0:
		var sc: Dictionary = s.conduits[wi]
		var a := center(sc["a"])
		var b := center(sc["b"])
		# ⚠ **外框要明確伸出管緣**，而管緣的位置隨流量走（2–8px）。
		#   第一版寫死 ±7px，於是選一條滿載的幹線時外框正好壓在它自己的邊上——
		#   截圖當場看不出哪一條被選中。`_draw_conduit()` 的刻度在 B1.6.1 踩過
		#   一模一樣的坑，那裡的解法是 `w * 0.5 + 3`，這裡照抄。
		var bonus := float(s.mods["cap_bonus"])
		var w := Shapes.conduit_width(
			float((s.rates["conduit_flow"] as Dictionary).get(sc["id"], 0.0)),
			Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus)
		)
		var n := (b - a).normalized().orthogonal() * (w * 0.5 + 4.0)
		var t := (b - a).normalized() * (w * 0.5 + 4.0)
		draw_polyline(PackedVector2Array([
			a + n - t, b + n + t, b - n + t, a - n - t, a + n - t,
		]), Palette.ORDER_BRIGHT, 2.0)
		return
	if scr.selected.x < 0:
		return
	var n: Dictionary = s.node_at(scr.selected)
	if n.is_empty():
		return
	var c := center(scr.selected)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	draw_rect(Rect2(_world(scr.selected), g), Palette.ORDER_BRIGHT, false, 2.0)

	# ★ B3.8：圈要畫**升過的射程**。讀表上的原值會讓玩家看到一個和實際打得到
	#   的範圍不一樣的圈——而擺位正是他用這個圈在做的決定。
	var rng := Build.node_range(String(n["type"]), int(n.get("level", 0)))
	if rng > 0.0:
		# 半透明填色 ＋ 實線邊：只有邊的話，兩座塔的射程圈交疊時看不出誰罩到哪。
		draw_circle(c, rng * Shapes.GRID, Palette.alpha(Palette.ORDER_CYAN, 0.07))
		draw_arc(c, rng * Shapes.GRID, 0.0, TAU, 64, Palette.alpha(Palette.ORDER_BRIGHT, 0.7), 2.0)

	var chain_key: Array = [s.get_instance_id(), s.tick_count, s.rev, scr.selected]
	if chain_key != _chain_key:
		_chain_key = chain_key
		_chain = FlowNetwork.upstream_power(s.conduits, scr.energypanel.energy_net(), scr.selected, scr.energypanel.power_sources())
	var chain: Dictionary = _chain
	var lit: Dictionary = chain["conduits"]
	for ci in s.conduits.size():
		var cd: Dictionary = s.conduits[ci]
		if not lit.has(cd["id"]):
			continue
		draw_line(center(cd["a"]), center(cd["b"]),
			Palette.alpha(Palette.ENERGY_AMBER, 0.55), 6.0)
	# 來源畫琥珀菱形（琥珀專屬能量，§1.1 配色紀律 2）——它答的是「電從哪來」。
	for cell: Variant in (chain["sources"] as Dictionary):
		var sc := center(cell)
		draw_polyline(PackedVector2Array([
			sc + Vector2(0, -20), sc + Vector2(20, 0), sc + Vector2(0, 20),
			sc + Vector2(-20, 0), sc + Vector2(0, -20),
		]), Palette.ENERGY_AMBER, 2.5)


func _draw_hover() -> void:
	if not in_map(scr.hover):
		return
	var p := _world(scr.hover)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	# ★ 游標壓在導管上時，**不畫落點預覽，改把那條線點亮**（B3.7）。
	#   一次點擊只能做一件事，而畫面得先說出它會做哪一件——B3.4 才剛把落點預覽
	#   做成「畫那隻角色本人」，若它在會被導管攔下的地方照樣現身，那是畫面在說謊。
	var hover_wire: int = -1
	if scr.mode == scr.Mode.BUILD and scr.bp_index < 0 and scr.drag_from.x < 0:
		var hover_key: Array = [s.get_instance_id(), s.rev, scr.hover_p]
		if hover_key != _hover_key:
			_hover_key = hover_key
			_hover_wire = s.conduit_near(scr.hover_p, scr.WIRE_PICK)
		hover_wire = _hover_wire
	if hover_wire >= 0:
		var hc: Dictionary = s.conduits[hover_wire]
		draw_line(center(hc["a"]), center(hc["b"]),
			Palette.alpha(Palette.ORDER_BRIGHT, 0.45), 8.0)
	elif scr.mode == scr.Mode.BUILD and scr.build_type == "" and scr.bp_index < 0:
		# ★ B3.7.1：手上什麼都沒拿——**不畫落點預覽**。畫了就是承諾點下去會蓋東西，
		#   而這一刻不會。淡框仍然畫，游標在哪一格還是要看得見。
		draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	elif scr.mode == scr.Mode.BUILD:
		var preview_key: Array = [s.get_instance_id(), s.tick_count, s.rev, scr.build_type, scr.hover]
		if preview_key != _preview_key:
			_preview_key = preview_key
			_preview = BuildController.preview_place(s, scr.build_type, scr.hover)
		var pv: Dictionary = _preview
		var col: Color = Palette.OK_GREEN if pv["ok"] else Palette.WARN_ORANGE
		draw_rect(Rect2(p, g), Palette.alpha(col, 0.18))
		draw_rect(Rect2(p, g), col, false, 2.0)
		# ★ **手上那一隻長什麼樣子，就畫什麼樣子**（B3.4）。
		#
		# 原本這裡只有上面那個框，於是玩家在做全遊戲最主要的那個決定
		# （這一格擺誰）的當下，看到的是一個和別種節點一模一樣的方框。
		# §1.6 花了整節在講「形狀要說得出這隻角色是什麼」——梯形是打進地裡的樁、
		# 三角是稜鏡、四角爆散星是濺射——而那些形狀在**最需要它們的那一刻**缺席。
		#
		# 走 `_draw_node_body()`（和真的節點同一支函式），不另外畫一份：
		# 抄一份的下場是加第十五種節點時只有一邊記得加，而漏掉的那一邊
		# 症狀是隱形不是報錯（B2.4 中過三次，`_no_glyph` 就是為此而生）。
		_draw_node_body({"type": scr.build_type}, center(scr.hover))
		# 塔的射程要**在花錢之前**看得到——擺位是本作的主要決策，
		# 讓玩家蓋完才發現打不到路徑等於逼他拆（§3.5 塔的擺位）。
		var r := float(NodeDefs.of(scr.build_type).get("range", 0.0))
		if r > 0.0:
			draw_arc(
				center(scr.hover), r * Shapes.GRID, 0.0, TAU, 64,
				Palette.alpha(col, 0.45), 1.5
			)
	else:
		draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	# ★ 藍圖（B2.3）。框選中畫橡皮筋框；手上有藍圖時畫它的落點。
	if scr.bp_from.x >= 0:
		var lo := Vector2i(mini(scr.bp_from.x, scr.hover.x), mini(scr.bp_from.y, scr.hover.y))
		var hi := Vector2i(maxi(scr.bp_from.x, scr.hover.x), maxi(scr.bp_from.y, scr.hover.y))
		var rect := Rect2(_world(lo), Vector2(hi - lo + Vector2i.ONE) * Shapes.GRID)
		draw_rect(rect, Palette.alpha(Palette.ORDER_CYAN, 0.12))
		draw_rect(rect, Palette.ORDER_CYAN, false, 2.0)
	elif scr.bp_index >= 0:
		var list: Array = scr.bppanel.blueprints()
		if scr.bp_index < list.size():
			# **每一格各自上色**：綠＝放得下、橘＝這一格擋住了。整份一個顏色
			# 只能說「不行」，指不出是哪一格——而那正是玩家的下一步要知道的事。
			var chk := BuildController.blueprint_check(s, list[scr.bp_index], scr.hover)
			var bad: Dictionary = {}
			for c: Vector2i in (chk["blocked"] as Array):
				bad[c] = true
			for c: Vector2i in Blueprint.cells_at(list[scr.bp_index], scr.hover):
				var col: Color = Palette.WARN_ORANGE if bad.has(c) else Palette.OK_GREEN
				draw_rect(Rect2(_world(c), g), Palette.alpha(col, 0.22))
				draw_rect(Rect2(_world(c), g), col, false, 2.0)
	var cf: Vector2i = scr.drag_from
	if cf.x >= 0:
		draw_rect(Rect2(_world(cf), g), Palette.ORDER_BRIGHT, false, 2.0)
		_draw_connect_guides(cf)
		# ★ 預覽線依**合法性**上色。B0.7.2 之前不管連不連得成都畫一條亮線，
		#   那是在畫一條不可能存在的導管——玩家只能點下去才知道不行。
		var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, scr.hover, s.conduit_cells()
	)
		var legal: bool = code == Build.OK and not s.node_at(scr.hover).is_empty()
		draw_line(
			center(cf), center(scr.hover),
			Palette.alpha(Palette.OK_GREEN if legal else Palette.WARN_ORANGE, 0.7), 2.0
		)


## ★ 連線的八條方向導引（`10_GDD.md` §3.2「導管只能走水平／垂直／45°」）。
##
## 使用者回報「沒有辦法 45 度放置管道」——規則其實是通的，**難的是用肉眼在
## 網格上找出正斜角**（要 |dx| 恰好等於 |dy|）。一條規則如果只能靠試錯才知道
## 自己有沒有踩中，那它在體感上就等於壞掉。把八條合法方向直接畫出來，
## 「45°」從一句文字變成畫面上看得到的四條斜線。
func _draw_connect_guides(anchor: Vector2i) -> void:
	var from := center(anchor)
	var col := Palette.alpha(Palette.ORDER_DIM, 0.5)
	var size: Vector2i = s.map["size"]
	for d: Vector2i in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]:
		var end := anchor
		while in_map(end + d):
			end += d
		if end != anchor:
			draw_line(from, center(end), col, 1.0)


## ★ 地圖座標（格 × 32px），**不是螢幕座標**——縮放與平移由 `_draw()` 開頭
## 那一個 `draw_set_transform` 統一處理（B1.2.2）。
func _world(c: Vector2i) -> Vector2:
	return Shapes.to_world(c)


func center(c: Vector2i) -> Vector2:
	return _world(c) + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 地圖座標 → 螢幕座標。只有需要拿螢幕位置的地方才用（例：把浮層對到節點上）。
func to_screen(p: Vector2) -> Vector2:
	return _map_origin() + p * zoom
