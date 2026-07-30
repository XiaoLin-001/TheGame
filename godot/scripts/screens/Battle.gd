extends Control
## 局內畫面（`10_GDD.md` §6.2：**全畫面地圖 ＋ 浮層**，不是三欄式）。
##
## B0.3 只做「建造與地圖」需要的部分：地圖繪製、四種建造模式、頂欄供需。
## 真正的 HUD（三態徽章、能量列脈動、提前召喚、局末結算）是 B0.6；
## 敵人與波次是 B0.4。**這一批要證明的是：線會亮、線會滿載、加粗會變粗。**

const SessionState := preload("res://scripts/game/SessionState.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const MapsData := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Score := preload("res://scripts/sim/Score.gd")
const CampaignData := preload("res://data/Campaign.gd")

## 地圖左上角。36×19 格 ×32px = 1152×608；左側 120px 留給建造欄，
## 浮層與地圖**不重疊**（RG-20 的先行實踐，正式驗收在 B0.6）。
## ★ 地圖框架（B1.2.2，使用者要求）。**玩家看到的地圖區域恆定**，不隨關卡
## 大小變動：進場時自動縮放到剛好填滿它，之後玩家自由縮放。
##
## 這比「地圖必須小到放得進一屏」好在兩件事：關與關之間的視覺尺度一致
## （20×12 的第 1 關不再只佔左上角一小塊），而且**地圖尺寸不再受畫面限制**
## ——它變成純粹的關卡設計參數。代價是**格子的像素大小會隨圖變大而變小**，
## 而線寬／徽章那套視覺編碼有一個可讀性地板（`50_QA_PLAN.md` RG-58）。
##
## x=120 讓出左側建造欄，y=56 讓出頂欄，下緣停在 660（底欄鈕在 668）。
const FRAME := Rect2(Vector2(120.0, 56.0), Vector2(1152.0, 604.0))
## 縮放上限＝ fit 的幾倍。下限就是 fit——比 fit 更小只是把地圖縮進框架裡的
## 一小塊，那正是這一批要修掉的東西。
const ZOOM_MAX_MULT := 3.0
const ZOOM_STEP := 1.25

## `10_GDD.md` §7.1。**只在準備期可用。**
const FAST_FORWARD_RATE := 4

## 流動珠（`20_ART_DIRECTION.md` §1.4a）：珠距、每單位流率的行進速度（px/秒）、
## 低於此流率就完全不畫。20/秒的幹線 ＝ 120 px/秒，一格 32px 約走四分之一秒。
const BEAD_GAP := 20.0
const BEAD_SPEED := 6.0
const BEAD_MIN_RATE := 0.05

## 能量收支面板的**固定列序**。列數與順序恆定，沒有值的列留在原位變暗，
## 面板才不會每個 tick 抖一次（B0.7.4）。`short0..2` 是餵不飽的節點清單。
const ENERGY_ROWS := [
	"gen", "silo_out", "reclaim", "sep1", "tower", "smelt", "silo_in", "sep2", "net",
	"short0", "short1", "short2", "tip", "tip2",
]
## 「餵不飽」最多列幾座，其餘收成一行「…還有 N 座」。
const SHORT_ROWS := 3

enum Mode { BUILD, CONNECT, UPGRADE, DEMOLISH, PAN }

var s: RefCounted = null

## ★ 這一局打的是哪一關（`data/Campaign.gd` 的一筆）。**空字典＝測試圖／沙盤**，
## 那條路徑沒有星等、沒有解鎖限制、也不寫存檔。
## 由呼叫端在 `add_child()` **之前**指派——`_ready()` 一進來就要用它。
var level: Dictionary = {}
## 回關卡選擇。測試圖沒有上一層，所以是 Callable 而不是寫死的場景切換。
var on_exit: Callable = Callable()

## 視野（B1.2.2）。`_fit` 是「剛好填滿框架」的倍率，也是縮放下限。
var _zoom: float = 1.0
var _fit: float = 1.0
## 平移（螢幕像素）。fit 時恆為 0（地圖與框架同大，居中就是全貌）。
var _pan: Vector2 = Vector2.ZERO
var _zoom_button: Button = null

var _mode: int = Mode.BUILD
var _build_type: String = "extractor"
var _connect_from: Vector2i = Vector2i(-1, -1)
var _hover: Vector2i = Vector2i(-999, -999)
var _accum: float = 0.0
var _message: String = ""

var _top: HBoxContainer = null
var _hint: Label = null
var _mode_buttons: Dictionary = {}
var _build_buttons: Dictionary = {}
var _ff_button: Button = null
var _summon_button: Button = null
var _over_panel: Control = null
var _prio_panel: Control = null
var _help_panel: Control = null
var _help_button: Button = null
## 說明面板是「自動開的」還是玩家自己開的。自動開的那一份在玩家放下第一個
## 節點時自己收起來——他已經證明會操作了，再擋著就只是擋著。
var _help_auto: bool = false
var _energy_panel: Control = null
var _energy_button: Button = null
var _energy_rows: Dictionary = {}
var _codex_button: Button = null
var _codex_panel: Control = null
var _codex_label: Label = null
var _codex_on: bool = true
var _prio_labels: Dictionary = {}
## 本幀交戰中的塔 `{id: Array}`。繪圖層自己算——它要畫的是「誰正在吃電」，
## 而模擬只留了一個座數（`rates.engaged`）。
var _engaged: Dictionary = {}


func _ready() -> void:
	theme = UiKit.theme()
	# ★ **`set_anchors_and_offsets_preset`，不是 `set_anchors_preset`。**
	# 後者只設錨點不動 offset，本節點的 `size` 一直是 **(0, 0)**——而
	# `_draw()` 用的是絕對座標、`CanvasItem` 的繪圖不受 Control 尺寸裁切，
	# 所以**畫面完全正常，但滑鼠命中區是空的**：整張地圖點不動（B0.7.2）。
	# 這是「看起來對」與「真的對」差最遠的一種缺陷。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s = SessionState.new()
	# `TL_PANEL=sandbox`：沙盤「靜水」（`data/Maps.gd`）。**合金那一列流動珠
	# 只有這張圖上有**——淺灘的示範佈局沒有熔爐，所以第三種資源的視覺編碼
	# 在任何既有截圖裡都不會出現，而沒被看過的編碼不算通過 R-3。
	_setup_session()
	_build_ui()
	# 截圖驗證要看得到「流動中的網路」，空地圖證明不了任何事——
	# **除了首次體驗**（`50_QA_PLAN.md` §4.4），那正好要看玩家真正的第一眼，
	# 所以 `TL_DEMO_TICKS=0` 的語意是「不要示範佈局」。
	if Hooks.panel in ["battle", "sandbox", "campaign"] and Hooks.demo_ticks > 0:
		_demo_layout()
	if Hooks.click_test:
		_click_selftest.call_deferred()


## 一局的起手。戰役關卡帶著自己的地圖與解鎖清單；沒有關卡就是測試圖／沙盤。
func _setup_session() -> void:
	if not level.is_empty():
		s.setup(level["map"], level["unlocked"])
	else:
		s.setup(MapsData.SANDBOX if Hooks.panel == "sandbox" else MapsData.SHOAL)
	_reset_view()


# ── 視野：框架、fit、縮放、平移（B1.2.2）─────────────────────────────

## 這張圖剛好填滿框架的倍率。取兩軸的**較小值**——較大值會讓另一軸溢出框架，
## 而「進場就看得到全貌」是這個框架存在的理由。
func _fit_zoom() -> float:
	return Shapes.fit_zoom(s.map["size"], FRAME.size)


## 進場（與「全景」鈕）的視野：fit ＋ 居中。
func _reset_view() -> void:
	_fit = _fit_zoom()
	_zoom = _fit
	_pan = Vector2.ZERO


## 地圖左上角在螢幕上的位置。**框架內居中**，放大後由 `_pan` 帶著走。
func _map_origin() -> Vector2:
	var px := Vector2(s.map["size"]) * Shapes.GRID * _zoom
	return FRAME.position + (FRAME.size - px) * 0.5 + _pan


## 放大之後地圖比框架大，平移要有邊界——不然可以把地圖整片拖出畫面，
## 然後玩家會以為遊戲壞了。夾住之後框架永遠被地圖蓋滿。
func _clamp_pan() -> void:
	var px := Vector2(s.map["size"]) * Shapes.GRID * _zoom
	var slack := (px - FRAME.size) * 0.5
	_pan.x = clampf(_pan.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	_pan.y = clampf(_pan.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))


## 縮放。`anchor` 是螢幕上要固定不動的那一點（滑鼠位置或框架中心）——
## 少了它，滾輪縮放會把玩家正在看的東西推出畫面。
func _zoom_by(mult: float, anchor: Vector2) -> void:
	var before := _zoom
	_zoom = clampf(_zoom * mult, _fit, _fit * ZOOM_MAX_MULT)
	if is_equal_approx(before, _zoom):
		return
	# 讓 anchor 在縮放前後對到同一個格：pan 補上原點的位移。
	var k := _zoom / before
	_pan += (anchor - _map_origin()) * (1.0 - k)
	_clamp_pan()
	_refresh_zoom()
	queue_redraw()


func _on_zoom(mult: float) -> void:
	_zoom_by(mult, FRAME.position + FRAME.size * 0.5)


func _on_zoom_reset() -> void:
	_reset_view()
	_refresh_zoom()
	queue_redraw()


func _refresh_zoom() -> void:
	if _zoom_button == null:
		return
	# TL_NAKED 遮所有數值標籤；縮放倍率也是數值。
	if Hooks.naked:
		_zoom_button.text = "全景"
		return
	_zoom_button.text = "全景 %d%%" % roundi(_zoom / maxf(0.0001, _fit) * 100.0)


## 這一局蓋得出哪些節點。**空的 `unlocked` ＝ 全部**（測試圖與沙盤）。
func _buildable() -> Array:
	var unlocked: Array = s.sets.get("unlocked", [])
	return NodeDefs.BUILDABLE if unlocked.is_empty() else unlocked


## ★ 輸入層自檢（`TL_CLICKTEST=1`）。**用合成的滑鼠事件真的走一次 Godot 的
## 輸入路由**——不是直接呼叫 `_act()`，那樣測不到 `mouse_filter` 這一層，
## 而 B0.7.2 的缺陷正好就在那一層（滿版 `Control` 預設 `STOP`，把事件吃掉，
## `_unhandled_input` 從來沒被呼叫過，地圖五批都點不動）。
##
## 這支自檢存在的意義就是「那個缺陷不會再發生一次而沒人知道」。
##
## ⚠ **必須開真視窗跑，`--headless` 過不了**：dummy display server 不做 GUI
## 滑鼠命中測試，`_gui_input` 完全不會被呼叫。它是唯一一個不能 headless 的
## 檢查——這也正是它抓得到的東西別的檢查都抓不到的原因。
##   `TL_CLICKTEST=1 TL_MUTE=1 <godot> --path godot --rendering-driver opengl3`
## 約 1 秒後自己退出（0 ＝ PASS）。
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# 有示範佈局在場時只驗浮層：地圖上的格子被佔走了，建造斷言本來就不成立。
	if s.nodes.size() > 1:
		_energy_button.button_pressed = true
		_on_codex_show("prism", _build_buttons["prism"])
		print("[TL_CLICKTEST] 示範佈局在場，只開浮層（建造斷言略過）")
		return
	var ore: Vector2i = (s.map["ore"] as Array)[0]
	var on_path: Vector2i = s.path[10]
	var before: int = s.nodes.size()

	_click(ore)
	for _i in 3:
		await get_tree().process_frame
	var placed: bool = s.nodes.size() == before + 1

	_click(on_path)          # 路徑格禁節點 → 要被擋下且**說明原因**
	for _i in 3:
		await get_tree().process_frame
	var rejected: bool = s.nodes.size() == before + 1 and _message.begins_with("✕")

	# ★ 45° 導管（使用者回報「沒辦法 45 度放置管道」）：在礦點的正斜角放一個
	#   中繼，切「連線」，點兩端。整條路徑都走真實輸入——包含按鈕。
	_press(_build_buttons["relay"])
	var from := Vector2i(10, 10)
	var to := Vector2i(13, 13)     # 正斜角，且遠離路徑（路徑走 y=4 與 x=30）
	_click(from)
	_click(to)
	for _i in 3:
		await get_tree().process_frame
	var diag_placed: bool = s.nodes.size() == before + 3
	_press(_mode_buttons[Mode.CONNECT])
	_click(from)
	_click(to)
	for _i in 3:
		await get_tree().process_frame
	var wired: bool = s.conduits.size() == 1

	# ★ 使用者回報：「45 度的線似乎沒辦法加粗」（B1.2.1）。一格長的 45°——
	#   兩個對角相鄰的節點之間——連一個中間格都沒有，舊的格子命中判定必然落空。
	#   這裡走完整輸入路徑：切「加粗」→ 點兩節點之間那個像素點 → 級數要真的變。
	_press(_build_buttons["relay"])
	_click(Vector2i(6, 12))
	_click(Vector2i(7, 13))
	for _i in 3:
		await get_tree().process_frame
	_press(_mode_buttons[Mode.CONNECT])
	_click(Vector2i(6, 12))
	_click(Vector2i(7, 13))
	for _i in 3:
		await get_tree().process_frame
	_press(_mode_buttons[Mode.UPGRADE])
	_click_at(_to_screen((_center(Vector2i(6, 12)) + _center(Vector2i(7, 13))) * 0.5))
	for _i in 3:
		await get_tree().process_frame
	var short_diag: int = s.conduit_near(Vector2(6.5, 12.5))
	var upgraded: bool = short_diag >= 0 and int((s.conduits[short_diag])["level"]) == 1
	_press(_mode_buttons[Mode.CONNECT])

	# 留一個懸而未決的起點，讓八條方向導引與「連不成」的橙色預覽線入鏡。
	_click(from)
	_hover = from + Vector2i(4, 3)     # 橫 4 直 3：正好不是 45°
	_refresh_hint()

	# ★ B1.1：建造欄從 8 顆長到 10 顆（＋熔爐＋碎浪），高度逼近底欄。
	#   **最後一顆鈕還點不點得到**是這件事唯一該問的問題——鈕被擠出畫面時
	#   `_draw()` 完全不會抱怨，就跟 B0.7.2 那個 size (0,0) 的 bug 一樣。
	#   碎浪要合金（帳上 0）→ 會被擋下，但**擋下的理由必須是「合金不夠」**，
	#   不能是「這顆鈕根本沒被按到」。
	var last_button: Button = _build_buttons[NodeDefs.BUILDABLE[NodeDefs.BUILDABLE.size() - 1]]
	var reachable: bool = last_button.global_position.y + 44.0 <= 668.0
	_press(last_button)
	_click(Vector2i(12, 12))
	for _i in 3:
		await get_tree().process_frame
	var alloy_gated: bool = _build_type == "breaker" and _message.contains("合金")

	# 三個浮層也走同一條真實路徑：按鈕 → 面板出現且有內容。
	_energy_button.button_pressed = true
	_on_codex_show("smelter", _build_buttons["smelter"])
	_prio_panel.visible = true
	await get_tree().process_frame
	var energy_ok: bool = (
		_energy_panel.visible and (_energy_rows["net"] as Label).text != ""
		and _energy_rows.has("smelt")
	)
	var codex_ok: bool = _codex_panel.visible and _codex_label.text.contains("熔爐")
	# 優先權面板 9 列雙欄：整張表要留在畫面內，且不得蓋掉能量面板。
	var prio_ok: bool = (
		_prio_panel.size.y > 0.0
		and _prio_panel.position.y + _prio_panel.size.y <= 668.0
		and _prio_panel.position.x + _prio_panel.size.x <= _energy_panel.position.x
	)

	# ★ 視野（B1.2.2）。四件事：進場就是 fit、fit 真的填滿框架、放大/全景走得通、
	#   平移夾得住。**縮放最容易壞的不是縮放本身，是命中判定跟著縮放走**——
	#   所以最後再用合成點擊蓋一個節點，確認放大後點到的還是同一格。
	var view_ok := await _view_selftest()

	var ok: bool = (
		placed and rejected and diag_placed and wired and upgraded
		and reachable and alloy_gated and energy_ok and codex_ok and prio_ok
		and view_ok
	)
	print("[TL_CLICKTEST] place=%s reject_path=%s diag_node=%s diag_conduit=%s diag_upgrade=%s last_btn=%s alloy_gate=%s energy=%s codex=%s prio=%s view=%s → %s" % [
		placed, rejected, diag_placed, wired, upgraded, reachable, alloy_gated,
		energy_ok, codex_ok, prio_ok, view_ok, "PASS" if ok else "FAIL"
	])
	# 同時給 `TL_SHOT` 時不退出，把畫面交給截圖鉤子——**有些狀態只有互動才到得了**
	# （浮層要按鈕才會開、簡介要 hover 才會浮），沒有這條就永遠拍不到它們。
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


## ★ 視野自檢（B1.2.2）。回傳全部通過與否，並**把畫面留在放大＋推到角落的
## 狀態**——那正是「遮罩有沒有真的切住框架」唯一拍得出來的畫面。
func _view_selftest() -> bool:
	var px := Vector2(s.map["size"]) * Shapes.GRID
	# ① 進場就是 fit，而且 fit 至少填滿一軸（另一軸留邊是長寬比不同，不是漏算）。
	var at_fit: bool = is_equal_approx(_zoom, _fit)
	var filled: bool = (
		is_equal_approx(px.x * _fit, FRAME.size.x) or is_equal_approx(px.y * _fit, FRAME.size.y)
	)
	var inside: bool = px.x * _fit <= FRAME.size.x + 0.5 and px.y * _fit <= FRAME.size.y + 0.5

	# ② 頂欄不能長到撞上縮放鈕（礦砂上萬之後那一排會變長）。
	var bar_clear: bool = _top.position.x + _top.size.x <= _zoom_button.get_parent().position.x

	# ③ 放大 → 倍率上升；「全景」→ 回到 fit 且平移歸零。
	_on_zoom(ZOOM_STEP)
	var zoomed_in: bool = _zoom > _fit
	_pan = Vector2(99999.0, 99999.0)
	_clamp_pan()
	var pan_clamped: bool = _pan.x <= (px.x * _zoom - FRAME.size.x) * 0.5 + 0.5
	_on_zoom_reset()
	var reset_ok: bool = is_equal_approx(_zoom, _fit) and _pan == Vector2.ZERO
	# 下限就是 fit：再按「−」也不該縮得比框架小。
	_on_zoom(1.0 / ZOOM_STEP)
	var floor_ok: bool = is_equal_approx(_zoom, _fit)

	# ④ ★ **放大之後命中判定還對得上**：這是縮放最容易靜靜壞掉的地方。
	#    放大兩級、把目標礦點平移到框架正中（玩家放大就是為了看某個東西），
	#    再點它——蓋出來的必須就是那一格，不是隔壁那一格。
	_on_zoom(ZOOM_STEP * ZOOM_STEP)
	_press(_build_buttons["extractor"])
	var target: Vector2i = (s.map["ore"] as Array)[1]
	var px_map := Vector2(s.map["size"]) * Shapes.GRID
	_pan = (px_map * 0.5 - _center(target)) * _zoom
	_clamp_pan()
	var before: int = s.nodes.size()
	_click(target)
	for _i in 3:
		await get_tree().process_frame
	var hit_ok: bool = s.nodes.size() == before + 1 and not s.node_at(target).is_empty()

	print("[TL_CLICKTEST/view] fit=%s fills=%s inside=%s bar_clear=%s zoom_in=%s pan_clamp=%s reset=%s floor=%s hit_after_zoom=%s　（fit=%.3f，格 %.1f px）" % [
		at_fit, filled, inside, bar_clear, zoomed_in, pan_clamped, reset_ok, floor_ok,
		hit_ok, _fit, Shapes.GRID * _fit
	])
	return (
		at_fit and filled and inside and bar_clear and zoomed_in
		and pan_clamped and reset_ok and floor_ok and hit_ok
	)


func _press(b: Button) -> void:
	b.button_pressed = true
	b.pressed.emit()


## GUI 的滑鼠路由要先有「游標在這裡」才認得出按下的是誰，所以**先送一個移動事件**。
## 走 `Input.parse_input_event()`（完整輸入管線）而不是 `Viewport.push_input()`：
## 後者繞過了一部分 GUI 狀態的建立，測不到真實玩家會走的那條路。
## ★ `_center()` 回的是**地圖座標**，合成滑鼠事件要的是**螢幕座標**——
## 中間差的就是縮放與平移那個變換（B1.2.2）。少了 `_to_screen()`，
## 這支自檢會點到旁邊那一格去，而畫面上一切看起來都正常。
func _click(cell: Vector2i) -> void:
	_click_at(_to_screen(_center(cell)))


## 像素座標版。**加粗要點的是兩個節點「之間」**，那不是任何一格的中心。
func _click_at(at: Vector2) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)


func _process(delta: float) -> void:
	# ★ `TL_SHOT` 下模擬凍結在 `_demo_layout()` 推完的那一格。否則截圖落在第幾
	# tick 取決於這台機器 3 秒內跑了幾幀——同一份佈局在不同機器上會拍出不同
	# 數字，截圖就不能拿來做回歸比對，也對不上 `TL_SIM=<同一個 N>` 的輸出。
	if Hooks.shot_path == "":
		_accum += delta
		# 快進＝**多跑幾個 tick**，不是把 tick 拉長。固定時間步不能動，
		# 否則同一組操作在不同倍率下會跑出不同結果（§2.4 確定性）。
		var mult: int = s.speed_mult if s.phase == "prep" else 1
		var guard := 0
		while _accum >= BattleController.TICK and guard < 8 * mult:
			for _i in mult:
				BattleController.step(s)
			_accum -= BattleController.TICK
			guard += mult
	if _help_auto and s.nodes.size() > 1:
		_help_auto = false
		_help_button.button_pressed = false  # → `toggled` → 面板收起
	_refresh_top()
	# 提示列每幀重算：它講的是**當前狀態**下的下一步，而狀態每 tick 都在變。
	# B0.7 之前它只在滑鼠移動時更新，於是「礦砂開始入帳了」「波次開打了」這類
	# 轉折要等玩家碰一下滑鼠才會反映——手不動的那幾秒，提示列是在說謊。
	_refresh_hint()
	_refresh_energy()
	_refresh_over()
	queue_redraw()


# ── 輸入 ──────────────────────────────────────────────────────────────

## ★ **必須是 `_gui_input`，不能是 `_unhandled_input`。**
##
## 本畫面是一個滿版的 `Control`，而 `Control.mouse_filter` 預設是 `STOP`：
## 它在 `_gui_input` 那一層就把滑鼠事件吃掉並標記為已處理，`_unhandled_input`
## **永遠不會被呼叫**。B0.3 到 B0.7.1 這條路徑一次都沒通過——
## 左欄的按鈕能按（它們是各自獨立的子 Control），但**地圖完全點不動**。
##
## 為什麼拖了五批才發現：所有自動化驗證走的都是 `TL_SIM`（不開視窗）與
## `TL_PANEL`＋示範佈局（用程式呼叫 `BuildController`，不經過輸入層），
## 而「絕不在沒有鉤子的情況下開視窗」這條紀律讓我也沒有手動點過。
## **整個輸入層在這之前是零覆蓋。** 對策：`TL_CLICKTEST=1`（見 `_click_selftest()`）。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# ★ 平移模式：按著左鍵拖。**用一個模式鈕而不是右鍵或中鍵**——手機移植
		#   預留條款 P3「操作不得只靠 hover／右鍵／鍵盤」，而拖曳在觸控上就是拖曳。
		if _mode == Mode.PAN and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_pan += mm.relative
			_clamp_pan()
			queue_redraw()
			return
		var c := _cell_at(mm.position)
		if c != _hover:
			_hover = c
			_refresh_hint()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# 滾輪縮放是桌面的便利，不是唯一的路：底欄有 ＋／−／全景 三顆鈕（P3）。
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_by(ZOOM_STEP, mb.position)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_by(1.0 / ZOOM_STEP, mb.position)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_act(_cell_at(mb.position), _point_at(mb.position))
	_refresh_hint()


## `point` 是**格為單位的浮點座標**（整數＝格中心）。加粗與拆除要用它才點得準：
## 好幾條線擠在同一個節點上時，格解析度分不出玩家指的是哪一條（B1.2.1）。
## 省略時退回格中心，`_click()` 那條合成輸入的路徑走這個預設。
func _act(cell: Vector2i, point: Vector2 = Vector2(-999, -999)) -> void:
	var p := Vector2(cell) if point.x < -900.0 else point
	match _mode:
		Mode.BUILD:
			_message = _text_of(BuildController.place(s, _build_type, cell))
		Mode.CONNECT:
			if s.node_at(cell).is_empty():
				_message = "連線模式：請點節點（先起點、後終點）"
			elif _connect_from.x < 0:
				_connect_from = cell
				_message = "起點已選：%s。再點一個節點拉線。" % _label_at(cell)
			else:
				_message = _text_of(BuildController.lay_conduit(s, _connect_from, cell))
				_connect_from = Vector2i(-1, -1)
		Mode.UPGRADE:
			var ci: int = s.conduit_near(p)
			if ci < 0:
				_message = "加粗模式：請點一段導管（不是節點）"
			else:
				_message = _text_of(BuildController.upgrade(s, ci))
		Mode.DEMOLISH:
			_message = _text_of(BuildController.demolish(s, cell, p))
		Mode.PAN:
			# 拖曳在 `_gui_input` 處理；單擊在這個模式下刻意什麼都不做——
			# 平移模式最重要的性質是「不會誤蓋東西」。
			_message = "移動模式：按著左鍵拖動地圖。要蓋東西請先切回左欄。"


func _text_of(code: String) -> String:
	return "✔ 完成" if code == Build.OK else "✕ " + BuildController.reason_text(code)


func _label_at(cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	return NodeDefs.label(String(n["type"])) if not n.is_empty() else "空地"


## 螢幕像素 → 格號。**縮放與平移的反變換就在這一行**，命中判定與繪圖
## 因此永遠對得起來（各寫一份的那一天，滑鼠就會差半格）。
func _cell_at(pos: Vector2) -> Vector2i:
	return Shapes.to_grid((pos - _map_origin()) / _zoom)


## 螢幕像素 → **格為單位的浮點座標**（整數＝格中心）。
func _point_at(pos: Vector2) -> Vector2:
	return (pos - _map_origin()) / (Shapes.GRID * _zoom) - Vector2(0.5, 0.5)


func _in_map(c: Vector2i) -> bool:
	var size: Vector2i = s.map["size"]
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


# ── 繪圖 ──────────────────────────────────────────────────────────────

func _draw() -> void:
	var size: Vector2i = s.map["size"]
	var rect := Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID)

	# ★ 全部的地圖繪圖都在**格為單位的地圖座標**裡做，縮放與平移交給這一個
	#   變換（B1.2.2）。所以底下每一支 `_draw_*` 都不知道縮放存在——
	#   縮放要是滲進 9 支繪圖函式裡，每加一種圖形就要記得乘一次倍率。
	#   文字不受影響：`_draw()` 裡沒有任何 `draw_string`，HUD 全是 Control 子節點。
	draw_set_transform(_map_origin(), 0.0, Vector2(_zoom, _zoom))
	draw_rect(rect, Palette.BG_PANEL)

	# 網格只畫在地圖範圍內：畫到浮層底下會讓「哪裡可以蓋」變得曖昧。
	Shapes.draw_grid(self, rect)

	_engaged = Combat.engaged(s.nodes, Combat.enemy_cells(s.enemies, s.path))
	_draw_path()
	_draw_ore_cells()
	_draw_conduits()
	_draw_nodes()
	_draw_enemies()
	_draw_shots()
	_draw_hover()
	# 階段色調（`10_GDD.md` §6.2 硬性要求 4）：**不看計時器也知道自己在哪個階段**。
	# 蓋在最上層而不是墊在底下——墊底的話節點與敵人會把它整片蓋掉。
	draw_rect(rect, Palette.alpha(
		Palette.WARN_ORANGE if s.phase == "wave" else Palette.ORDER_CYAN,
		0.10 if s.phase == "wave" else 0.03
	))

	# ── 回到螢幕座標 ──────────────────────────────────────────────────
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_frame_matte()
	_draw_energy_bar()


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


func _draw_path() -> void:
	# 敵人路徑屬於**混沌**側：低透明度帶狀底色（20_ART_DIRECTION.md §1.6）。
	var band := Palette.alpha(Palette.TIDE_DEEP, 0.45)
	for c: Vector2i in s.path:
		draw_rect(Rect2(_world(c), Vector2(Shapes.GRID, Shapes.GRID)), band)
	_draw_incoming()
	for c: Vector2i in s.map.get("crossings", []):
		_draw_crossing(c)


## ★ 來襲方向（`20_ART_DIRECTION.md` §1.6）。一條帶子只說「這裡是路」，
## **沒說潮從哪邊來**——而那是新玩家的第一個問題，也決定所有擺位。
## 順著箭羽走就找得到核心，一個元素答兩題（`50_QA_PLAN.md` §4.4）。
func _draw_incoming() -> void:
	var col := Palette.alpha(Palette.TIDE_MAGENTA, 0.35)
	var i := 2
	while i < s.path.size() - 1:
		var here: Vector2i = s.path[i]
		var dir := Vector2(s.path[i + 1] - here).normalized()
		var back := -dir * 5.0
		var wing := dir.orthogonal() * 5.0
		var tip := _center(here) + dir * 4.0
		draw_line(tip, tip + back + wing, col, 2.0)
		draw_line(tip, tip + back - wing, col, 2.0)
		i += 4


## 跨越點（橋）：**「架高」必須用畫的說清楚**——它是「橋上導管不受攻擊」
## 這條規則的唯一解釋（`20_ART_DIRECTION.md` §1.6）。硬性要求：一眼可辨。
func _draw_crossing(cell: Vector2i) -> void:
	var p := _world(cell)
	var g := Shapes.GRID
	# 橋下留可見的路徑帶陰影
	draw_rect(Rect2(p + Vector2(3, 3), Vector2(g - 6, g - 6)), Palette.alpha(Palette.BG_DEEP, 0.55))
	# 橋面：兩條 order.cyan 平行線，方向與路徑垂直（導管要橫越）
	var path: Dictionary = s.sets["path"]
	var horizontal := path.has(cell + Vector2i(1, 0)) or path.has(cell + Vector2i(-1, 0))
	var c := Palette.ORDER_CYAN
	if horizontal:
		# 橋面沿垂直方向（導管要南北橫越），兩端伸出格外＝架高的「引道」
		for dx: float in [7.0, g - 7.0]:
			draw_line(p + Vector2(dx, -6), p + Vector2(dx, g + 6), c, 3.0)
		# 橋頭：兩端各一條橫桿，把「這是一段結構」講清楚
		for dy: float in [-6.0, g + 6.0]:
			draw_line(p + Vector2(4, dy), p + Vector2(g - 4, dy), c, 2.0)
	else:
		for dy: float in [7.0, g - 7.0]:
			draw_line(p + Vector2(-6, dy), p + Vector2(g + 6, dy), c, 3.0)
		for dx: float in [-6.0, g + 6.0]:
			draw_line(p + Vector2(dx, 4), p + Vector2(dx, g - 4), c, 2.0)


func _draw_ore_cells() -> void:
	var occupied: Dictionary = s.occupied()
	for c: Vector2i in s.map.get("ore", []):
		if occupied.has(c):
			continue  # 蓋上採集器後由節點填實
		draw_arc(_center(c), 10.0, 0.0, TAU, 24, Palette.ORDER_DIM, 2.0)


func _draw_conduits() -> void:
	var flows: Dictionary = s.rates["conduit_flow"]
	var sat: Dictionary = s.rates["satisfaction"]
	for c: Dictionary in s.conduits:
		var cap := Build.conduit_cap(int(c["level"]))
		var flow := float(flows.get(c["id"], 0.0))
		var to_node: Dictionary = s.node_at(c["b"])
		var starving := (
			not to_node.is_empty() and float(sat.get(to_node["id"], 1.0)) < 0.95 and flow > 0.0
		)
		# 線寬的分母是**全遊戲的最大 cap**，不是這條線自己的——粗細因此在
		# 全圖上可以互相比較，而且加粗一條線之後它會真的變粗（B1.1 使用者回報）。
		var w := Shapes.conduit_width(flow, Build.conduit_cap(Build.CAP_MAX_LEVEL))
		# 受損：先鋪一圈 warn.orange 光暈。**線被打斷之前要先看得出它在挨打**，
		# 否則產能中斷對玩家來說會是憑空發生的。
		if float(c["hp"]) < 40.0:
			var hurt := 1.0 - float(c["hp"]) / 40.0
			draw_line(
				_center(c["a"]), _center(c["b"]),
				Palette.alpha(Palette.WARN_ORANGE, 0.25 + 0.55 * hurt), w + 6.0
			)
		draw_line(_center(c["a"]), _center(c["b"]), Palette.conduit(flow, cap, starving), w)
		# 升級過的幹線在端點加刻度，讓「我升過這條」在無數值下也看得見。
		# **垂直短刻線，不是圓點**：圓點會和流動珠混成同一個東西，而兩者語意相反
		# （固定的線材等級 vs 變動的流量）——`20_ART_DIRECTION.md` §1.4a。
		var pa := _center(c["a"])
		var pb := _center(c["b"])
		var perp := (pb - pa).normalized().orthogonal()
		for i in range(int(c["level"])):
			var at := pa.lerp(pb, 0.12 + 0.05 * float(i))
			draw_line(at - perp * 5.0, at + perp * 5.0, Palette.ORDER_BRIGHT, 2.0)
		# ★ 流動珠：礦砂／能量／合金各一列，各自往自己的淨流向跑（§1.4a）。
		var net: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		# 只有一種資源在跑時**走線的正中央**：多數導管都是這種，
		# 硬要分排會讓珠子懸在細線外面，看起來像掉出來的東西。
		# 三種同時跑的線（熔爐那條）中間讓給合金，礦砂與能量各退一邊。
		var lanes := 0
		for v: float in [net.x, net.y, net.z]:
			if absf(v) >= BEAD_MIN_RATE:
				lanes += 1
		var off := (w * 0.45 + 1.0) if lanes > 1 else 0.0
		# 礦砂珠用 `text.primary`（近白）而不是 `order.bright`：導管本身就是亮青，
		# 亮青珠子在亮青線上只讀得出「這裡有個洞」，讀不出「有東西在跑」。
		# 能量珠的琥珀、合金珠的鋼銀本來就與線色分屬不同色相，維持配色紀律 2。
		_draw_beads(pa, pb, net.x, Palette.TEXT_PRIMARY, -off, w)
		_draw_beads(pa, pb, net.y, Palette.ENERGY_AMBER, off, w)
		_draw_beads(pa, pb, net.z, Palette.ALLOY_VIOLET, 0.0, w)  # 合金恆走中線


## ★ 流動珠（`20_ART_DIRECTION.md` §1.4a）。線寬與顏色說的是「這條線有多滿」，
## 沒有任何元素在說「東西正在動」——一張靜態的粗線看起來是接線圖，不是產線。
##
## **這不是實體物品搬運。** 珠子的位置由已解出的流率 ＋ 經過的模擬秒數推算，
## 模擬層一無所知，珠子不參與任何判定（`10_GDD.md` §3.1 鎖定：流量網路）。
## 一旦它變成有位置有狀態的實體，`O(物品數)` 的效能與確定性負債就回來了。
##
## `amount` 帶號：正＝沿 a→b、負＝反向。速度 ∝ 流率，間距固定。
##
## ponytail: 每顆珠子兩個 `draw_circle` ＝ 每幀約 `導管數 × 線長/20 × 2` 次繪製。
## M0 一屏（13 條導管）約 500 次，無感；`30_TECH_DESIGN.md` §5 的壓力情境
## （2000 條導管）會爆到六位數。到那時改成單一 `draw_multiline` 批繪或
## 用 shader 把相位推進 GPU——**在量到之前不要先做**。
func _draw_beads(
	a: Vector2, b: Vector2, amount: float, col: Color, offset: float, width: float
) -> void:
	if absf(amount) < BEAD_MIN_RATE:
		return  # 沒在流動的線必須是靜止的——這是「哪裡斷了」最快的讀法
	var span := a.distance_to(b)
	if span < 1.0:
		return
	var u := (b - a) / span
	var side := u.orthogonal() * offset
	# 相位用模擬秒數推（tick 數 ＋ 幀內插值），不用系統時間：
	# 渲染可以不確定，但別引入新的亂數源。`TL_SHOT` 下模擬凍結 → 珠子也凍結。
	var t := (float(s.tick_count) + _accum / BattleController.TICK) * BattleController.TICK
	# 珠子大小跟著線寬走：這樣它**強化**「線寬＝流量」而不是把線戳成虛線。
	# 固定大小的珠子在 2px 的細線上會蓋掉整條線，粗細那條資訊就沒了（R-3）。
	var r := clampf(width * 0.32, 1.4, 3.0)
	var x := fposmod(t * amount * BEAD_SPEED, BEAD_GAP)
	while x < span:
		var p := a + u * x + side
		# **深色底是這個元素能被看見的唯一原因**：導管本身就是亮青，
		# 亮青珠子畫在亮青線上等於沒畫（使用者實看 B0.6 時反映的正是這件事）。
		draw_circle(p, r + 1.2, Palette.BG_DEEP)
		draw_circle(p, r, col)
		x += BEAD_GAP


func _draw_nodes() -> void:
	for n: Dictionary in s.nodes:
		var p := _center(n["cell"])
		var full := NodeDefs.hp(String(n["type"]))
		if float(n["hp"]) < full:
			# **血條不是圓環**：儲槽的充能也是琥珀色圓弧，兩個圓弧疊在同一顆
			# 12px 的節點上肉眼分不出來（本批截圖當場抓到）。形狀不同才分得開。
			var frac := clampf(float(n["hp"]) / full, 0.0, 1.0)
			var bar := Vector2(24.0, 3.0)
			var at := p + Vector2(-bar.x * 0.5, 15.0)
			draw_rect(Rect2(at, bar), Palette.alpha(Palette.BG_DEEP, 0.8))
			draw_rect(Rect2(at, Vector2(bar.x * frac, bar.y)), Palette.WARN_ORANGE)
		match String(n["type"]):
			"core":
				# 最大的幾何體，order.bright 描邊（§1.6）。
				draw_rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), Palette.BG_RAISED)
				draw_rect(
					Rect2(p - Vector2(15, 15), Vector2(30, 30)), Palette.ORDER_BRIGHT, false, 2.0
				)
				draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Palette.ORDER_BRIGHT)
			"extractor":
				draw_circle(p, 11.0, Palette.ORDER_CYAN)
				draw_arc(p, 11.0, 0.0, TAU, 24, Palette.ORDER_BRIGHT, 1.5)
			"generator":
				# 琥珀專屬於能量（§1.1 配色紀律 2）。
				draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), Palette.ENERGY_AMBER)
			"smelter":
				# 六邊形＝加工。合金銀是它的產物色，內圈琥珀講「它一直在吃電」
				# ——熔爐是全圖唯一待機也耗能的建築，那件事要看得出來。
				var hex := PackedVector2Array()
				for k in 6:
					hex.append(p + Vector2(12, 0).rotated(TAU * float(k) / 6.0))
				draw_colored_polygon(hex, Palette.ALLOY_STEEL)
				draw_circle(p, 5.0, Palette.ENERGY_AMBER)
			"relay":
				var d := PackedVector2Array([
					p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)
				])
				draw_colored_polygon(d, Palette.ORDER_DIM)
			"silo":
				var frac := float(n["charge"]) / maxf(1.0, float(NodeDefs.of("silo")["capacity"]))
				draw_arc(p, 12.0, 0.0, TAU, 32, Palette.ORDER_DIM, 2.0)
				if frac > 0.0:
					draw_arc(p, 12.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 32, Palette.ENERGY_AMBER, 4.0)
				# 四隻塔各給一個一眼可辨的幾何體（`20_ART_DIRECTION.md` §1.6）。
				# 全部嚴格對齊格中心——與敵潮的不規則凸包形成對比，那個對比就是主題。
			"anchor":
				draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), Palette.ORDER_CYAN)
			"prism":
				# 三角形＝稜鏡。合金銀把「它是最貴的那一座」講出來。
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -12), p + Vector2(11, 7), p + Vector2(-11, 7)
				]), Palette.ALLOY_STEEL)
			"knell":
				# 同心圓＝場。它不開火，畫成「發散」比畫成砲塔誠實。
				draw_arc(p, 11.0, 0.0, TAU, 28, Palette.ORDER_CYAN, 2.0)
				draw_arc(p, 5.0, 0.0, TAU, 20, Palette.ORDER_CYAN, 2.0)
			"reclaimer":
				draw_rect(Rect2(p - Vector2(10, 10), Vector2(20, 20)), Palette.ORDER_CYAN, false, 2.0)
				draw_circle(p, 6.0, Palette.ORDER_BRIGHT)
			"breaker":
				# 合金銀＝要合金才蓋得起（與稜鏡同一族），但形狀是**厚實方塊 ＋
				# 外框**：稜鏡是三角、碎浪是方——不靠顏色分辨（§1.6）。
				draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), Palette.ALLOY_STEEL)
				draw_rect(Rect2(p - Vector2(13, 13), Vector2(26, 26)), Palette.ALLOY_STEEL, false, 1.5)
		_draw_engaged(n, p)
		_draw_badge(n, p)


## ★ 交戰指示：**琥珀＝能量**（配色紀律 2）。有環＝這座塔本 tick 正在吃電。
## 它只講「在不在吃電」；「吃不吃得飽」由三態徽章講（B0.6 前這裡還多畫一段
## 橙色缺口弧，那和 `缺料` 徽章編碼的是同一件事，留一個就好）。
func _draw_engaged(n: Dictionary, p: Vector2) -> void:
	if _engaged.get(int(n["id"]), false):
		draw_arc(p, 15.0, 0.0, TAU, 32, Palette.ENERGY_AMBER, 2.0)


## ★ 節點三態徽章（`10_GDD.md` §3.1）。**`正常` 不畫任何東西**——徽章是例外
## 標記，一屏 14 個節點全掛上「我很好」等於把要找的那兩個埋進雜訊裡。
## 靠**形狀**分辨而不只是顏色：倒三角＝空的（缺料）、正三角＝滿的（滿溢）。
func _draw_badge(n: Dictionary, p: Vector2) -> void:
	match int((s.rates["node_state"] as Dictionary).get(int(n["id"]), SessionState.NORMAL)):
		SessionState.STARVED:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-7, -25), p + Vector2(7, -25), p + Vector2(0, -16)
			]), Palette.WARN_ORANGE)
		SessionState.OVERFLOW:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -25), p + Vector2(7, -16), p + Vector2(-7, -16)
			]), Palette.ORDER_BRIGHT)


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
	var w := FRAME.size.x
	var at := Vector2(FRAME.position.x, FRAME.position.y - 12.0)
	draw_rect(Rect2(at, Vector2(w, 8.0)), Palette.BG_RAISED)
	draw_rect(Rect2(at, Vector2(w * supply / span, 8.0)), Palette.ENERGY_AMBER)
	if demand > supply:
		# 脈動用 tick 數推，不用系統時間——渲染可以不確定，但別引入新的亂數源。
		var pulse := 0.55 + 0.45 * sin(float(s.tick_count) * 0.4)
		var x := w * supply / span
		draw_rect(
			Rect2(at + Vector2(x, 0.0), Vector2(w * demand / span - x, 8.0)),
			Palette.alpha(Palette.WARN_ORANGE, pulse)
		)
	draw_rect(Rect2(at + Vector2(w * demand / span - 1.0, -3.0), Vector2(2.0, 14.0)),
		Palette.TEXT_PRIMARY)


## 開火線。留 `SHOT_TTL` 個 tick 並隨之淡出——瞬間閃一下的線等於沒畫。
func _draw_shots() -> void:
	for sh: Dictionary in s.shots:
		var fade := float(sh["ttl"]) / float(BattleController.SHOT_TTL)
		draw_line(
			_center(sh["from"]), _center(sh["to"]),
			Palette.alpha(Palette.ORDER_BRIGHT, 0.25 + 0.6 * fade), 2.0
		)


## 敵潮屬於**混沌**側（`20_ART_DIRECTION.md` §0）：不規則凸包、不對齊網格、
## 呼吸式脈動。玩家的一切則是正圓正方、嚴格對齊——這個對比就是主題本身。
func _draw_enemies() -> void:
	for e: Dictionary in s.enemies:
		var def := Enemies.of(String(e["type"]))
		var p := _enemy_pos(e)
		var r := float(def.get("radius", 9.0))
		# 脈動用 tick 數推，不用系統時間——渲染可以不確定，但別引入新的亂數源。
		var pulse := 1.0 + 0.12 * sin(float(s.tick_count) * 0.25 + float(e["id"]))
		var pts := PackedVector2Array()
		for i in 9:
			var a := TAU * float(i) / 9.0
			# 每隻各自的不規則度，由 id 決定（同一隻永遠長同一個樣子）。
			# 值域收在 0.85–1.15：再寬就會有頂點塌進去，變成尖角旗子而不是水滴。
			var wobble := 1.0 + 0.15 * sin(float(e["id"]) * 3.7 + a * 2.0)
			pts.append(p + Vector2(cos(a), sin(a)) * r * pulse * wobble)
		draw_colored_polygon(pts, Palette.TIDE_MAGENTA)
		var frac := float(e["hp"]) / maxf(1.0, float(def.get("hp", 1.0)))
		if frac < 1.0:
			draw_arc(p, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 20, Palette.TIDE_DEEP, 2.0)


func _enemy_pos(e: Dictionary) -> Vector2:
	var prog := float(e["progress"])
	var i := clampi(int(floor(prog)), 0, s.path.size() - 1)
	var j := mini(i + 1, s.path.size() - 1)
	# 格與格之間插值：模擬是離散的，呈現不必是（60Hz 插值，§2.4）。
	return _center(s.path[i]).lerp(_center(s.path[j]), prog - float(i))


func _draw_hover() -> void:
	if not _in_map(_hover):
		return
	var p := _world(_hover)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	if _mode == Mode.BUILD:
		var pv := BuildController.preview_place(s, _build_type, _hover)
		var col: Color = Palette.OK_GREEN if pv["ok"] else Palette.WARN_ORANGE
		draw_rect(Rect2(p, g), Palette.alpha(col, 0.18))
		draw_rect(Rect2(p, g), col, false, 2.0)
		# 塔的射程要**在花錢之前**看得到——擺位是本作的主要決策，
		# 讓玩家蓋完才發現打不到路徑等於逼他拆（§3.5 塔的擺位）。
		var r := float(NodeDefs.of(_build_type).get("range", 0.0))
		if r > 0.0:
			draw_arc(
				_center(_hover), r * Shapes.GRID, 0.0, TAU, 64,
				Palette.alpha(col, 0.45), 1.5
			)
	else:
		draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	if _connect_from.x >= 0:
		draw_rect(Rect2(_world(_connect_from), g), Palette.ORDER_BRIGHT, false, 2.0)
		_draw_connect_guides()
		# ★ 預覽線依**合法性**上色。B0.7.2 之前不管連不連得成都畫一條亮線，
		#   那是在畫一條不可能存在的導管——玩家只能點下去才知道不行。
		var code: String = Build.can_connect(s.sets, s.conduit_keys(), _connect_from, _hover)
		var legal: bool = code == Build.OK and not s.node_at(_hover).is_empty()
		draw_line(
			_center(_connect_from), _center(_hover),
			Palette.alpha(Palette.OK_GREEN if legal else Palette.WARN_ORANGE, 0.7), 2.0
		)


## ★ 連線的八條方向導引（`10_GDD.md` §3.2「導管只能走水平／垂直／45°」）。
##
## 使用者回報「沒有辦法 45 度放置管道」——規則其實是通的，**難的是用肉眼在
## 網格上找出正斜角**（要 |dx| 恰好等於 |dy|）。一條規則如果只能靠試錯才知道
## 自己有沒有踩中，那它在體感上就等於壞掉。把八條合法方向直接畫出來，
## 「45°」從一句文字變成畫面上看得到的四條斜線。
func _draw_connect_guides() -> void:
	var from := _center(_connect_from)
	var col := Palette.alpha(Palette.ORDER_DIM, 0.5)
	var size: Vector2i = s.map["size"]
	for d: Vector2i in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]:
		var end := _connect_from
		while _in_map(end + d):
			end += d
		if end != _connect_from:
			draw_line(from, _center(end), col, 1.0)


## ★ 地圖座標（格 × 32px），**不是螢幕座標**——縮放與平移由 `_draw()` 開頭
## 那一個 `draw_set_transform` 統一處理（B1.2.2）。
func _world(c: Vector2i) -> Vector2:
	return Shapes.to_world(c)


func _center(c: Vector2i) -> Vector2:
	return _world(c) + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 地圖座標 → 螢幕座標。只有需要拿螢幕位置的地方才用（例：把浮層對到節點上）。
func _to_screen(p: Vector2) -> Vector2:
	return _map_origin() + p * _zoom


# ── 浮層 ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_top = UiKit.hbox(18)
	_top.position = Vector2(120, 14)
	add_child(_top)
	for i in 7:
		_top.add_child(UiKit.label("", 15, Palette.TEXT_PRIMARY, false))

	# ★ 縮放（B1.2.2）。放在頂欄右端那片空白——建造欄與底欄都已經滿了，
	#   而地圖右上角是縮放控制的慣例位置。**三顆鈕都是可點的**：滾輪只是
	#   桌面的便利，手機移植預留條款 P3 不許任何操作只有滾輪／右鍵一條路。
	var zoom_bar := UiKit.hbox(6)
	zoom_bar.position = Vector2(1072, 6)
	add_child(zoom_bar)
	for pair: Array in [["−", 1.0 / ZOOM_STEP], ["＋", ZOOM_STEP]]:
		var zb := Button.new()
		zb.text = String(pair[0])
		zb.pressed.connect(_on_zoom.bind(float(pair[1])))
		zoom_bar.add_child(UiKit.touchable(zb))
	_zoom_button = Button.new()
	# 倍率印在「全景」鈕上，不另給一個標籤——底欄與建造欄都沒有空位了，
	# 而「現在幾倍」與「回到全景」本來就是同一件事的兩面。
	_zoom_button.pressed.connect(_on_zoom_reset)
	zoom_bar.add_child(UiKit.touchable(_zoom_button))
	_refresh_zoom()

	# 間距 2 而不是 4：B1.1 起建造欄有 10 種節點＋3 個模式鈕，44px 的觸控高度
	# （手機移植前提，不能縮）乘 13 已經吃掉 572px，只剩間距可以讓。
	var col := UiKit.vbox(2)
	col.position = Vector2(8, 56)
	# 112 ＝ 剛好貼到地圖原點 x=120（`ORIGIN`）而不蓋住它。
	# 最長的一顆是「碎浪 140+60合」。
	col.custom_minimum_size = Vector2(112, 0)
	add_child(col)

	# ★ 全部 11 個鈕共用一個 `ButtonGroup`：任一時刻**恰好一個**是按下狀態，
	#   而那正好就是這個 UI 的真相（選了建造類型就是離開連線模式）。
	#   用 Godot 內建的 toggle 群組，不自己維護一套「哪個被選中」的高亮。
	#   B0.6 之前完全沒有選中指示——玩家只能從提示列的文字推自己在哪個模式。
	var group := ButtonGroup.new()
	# ★ 只列**這一關解鎖的**（`10_GDD.md` §7.9）。第 1 關給四顆鈕不是十顆——
	#   十顆對一個還不知道「電是流率」的人來說不是自由，是雜訊。
	#   一局之內這份清單不會變，所以鈕的位置仍然是固定的（R-15 的同一條理由）。
	for type: String in _buildable():
		# TL_NAKED 連造價都遮：它的語意是「隱藏所有數值標籤」，不是「隱藏狀態數值」。
		var b := _tool_button(group, (
			NodeDefs.label(type) if Hooks.naked
			else "%s %d%s" % [
				NodeDefs.label(type), NodeDefs.cost(type),
				"+%d合" % NodeDefs.alloy_cost(type) if NodeDefs.alloy_cost(type) > 0 else ""
			]
		))
		b.pressed.connect(_on_build_type.bind(type))
		# ★ 角色簡介：滑鼠停在鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
		b.mouse_entered.connect(_on_codex_show.bind(type, b))
		b.mouse_exited.connect(_on_codex_hide)
		_build_buttons[type] = b
		col.add_child(UiKit.touchable(b))
	(_build_buttons[_build_type] as Button).button_pressed = true

	col.add_child(_spacer(4))
	# ★ 四個動作鈕改**兩欄兩列**（B1.2.2）。加上「移動」之後單欄會滿：
	#   第 5 關的 10 顆建造鈕 ＋ 4 顆動作鈕 × 44px 觸控高度（手機移植前提，
	#   不能縮）＝ 646px，從 y=56 起算會撞到 y=668 的底欄。
	#   鈕被擠出畫面時 `_draw()` 完全不會抱怨——這正是 RG-47 在守的事。
	var modes := GridContainer.new()
	modes.columns = 2
	modes.add_theme_constant_override("h_separation", 2)
	modes.add_theme_constant_override("v_separation", 2)
	col.add_child(modes)
	for pair: Array in [
		[Mode.CONNECT, "連線"], [Mode.UPGRADE, "加粗"],
		[Mode.DEMOLISH, "拆除"], [Mode.PAN, "移動"],
	]:
		var b := _tool_button(group, String(pair[1]))
		b.custom_minimum_size = Vector2(54, 0)   # 兩欄要塞進 112px 的欄寬
		b.pressed.connect(_on_mode.bind(int(pair[0])))
		_mode_buttons[int(pair[0])] = b
		modes.add_child(UiKit.touchable(b))

	# 建造欄放不下八種節點再加動作鈕（8×44 已經吃掉 380px），
	# 所以時間流與面板開關搬到地圖下緣那條 56px 的空帶——那裡本來就空著。
	var bar := UiKit.hbox(8)
	bar.position = Vector2(8, 668)
	add_child(bar)
	_ff_button = Button.new()
	_ff_button.text = "快進 4×"
	_ff_button.pressed.connect(_on_fast_forward)
	bar.add_child(UiKit.touchable(_ff_button))
	_summon_button = Button.new()
	_summon_button.pressed.connect(_on_summon_now)
	bar.add_child(UiKit.touchable(_summon_button))
	# 抽屜開關本來就是一個開關：做成 toggle，按下狀態才**真的**等於「抽屜開著」。
	# 之前是普通按鈕，它拿到焦點時的外框看起來就像被選中，玩家會以為抽屜開了。
	var prio := Button.new()
	prio.text = "優先權"  # 底欄六個鈕，字都壓到最短——提示列要留得下兩行字

	prio.toggle_mode = true
	prio.toggled.connect(_on_toggle_priority)
	bar.add_child(UiKit.touchable(prio))
	_help_button = Button.new()
	_help_button.text = "說明"
	_help_button.toggle_mode = true
	_help_button.toggled.connect(_on_toggle_help)
	bar.add_child(UiKit.touchable(_help_button))

	_energy_button = Button.new()
	_energy_button.text = "能量"
	_energy_button.toggle_mode = true
	_energy_button.toggled.connect(_on_toggle_energy)
	bar.add_child(UiKit.touchable(_energy_button))
	_codex_button = Button.new()
	_codex_button.text = "圖鑑"
	_codex_button.toggle_mode = true
	_codex_button.button_pressed = true   # 預設開：它只在滑鼠停在建造鈕上時才出現
	_codex_button.toggled.connect(func(on: bool) -> void: _codex_on = on)
	bar.add_child(UiKit.touchable(_codex_button))

	_build_priority_panel()
	_build_energy_panel()
	_build_codex_panel()
	_build_help_panel()

	# 兩行：上行「下一步」、下行當下動作的細節。x 從 350 起，避開底欄那三個鈕。
	_hint = UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
	_hint.position = Vector2(520, 666)
	_hint.size = Vector2(755, 50)
	add_child(_hint)
	_refresh_hint()


## ★ 依**節點類型**的優先權面板（`10_GDD.md` §3.1）。
##
## 三件事是設計鎖死的，不要「順手」改掉：
##   ① **列固定、順序固定**（`NodeDefs.PRIORITY_ROWS`）——不可暫停的戰術動作
##      必須是一個手勢；滑桿會跑位就不是手勢了。
##   ② **沒有「每一座」的選項**——操作負擔不得隨建築數量成長（風險 R-1）。
##   ③ 預設收合。它是抽屜不是常駐欄（§6.2 全畫面地圖 ＋ 可收合浮層）。
func _build_priority_panel() -> void:
	var box := UiKit.panel()
	# B1.1 起 9 列：單欄 × 44px 觸控高度（手機移植前提，不能縮）放不進一屏，
	# 改**雙欄**——左生產、右防線（`NodeDefs.PRIORITY_SPLIT`），而那個分界
	# 正好就是這個面板在問的問題。
	#
	# 位置搬到畫面左下：能量面板佔右上（872..1264 × 96..416）、提示列佔
	# x ≥ 520 的底邊、底欄鈕佔 y ≥ 668——這一塊是唯一能讓兩張表同時開又
	# 互不相疊的地方。舊的 (1000, 330) 其實早就和能量面板疊了 66px。
	box.position = Vector2(128, 380)
	box.visible = false
	var outer := UiKit.vbox(4)
	box.add_child(outer)
	outer.add_child(UiKit.label("能量／礦砂不足時，誰先餓死", 14, Palette.TEXT_SECONDARY, false))
	var cols := UiKit.hbox(10)
	outer.add_child(cols)
	var lanes := [UiKit.vbox(4), UiKit.vbox(4)]
	cols.add_child(lanes[0])
	cols.add_child(lanes[1])
	# ★ 只列這一關蓋得出來的（核心永遠在，它不是玩家蓋的）。B1.2 起前幾關
	#   只解鎖四到六種節點，把另外五條永遠用不到的滑桿也列出來，就是把
	#   「這一格是我的戰術決定」稀釋成「這一排我看不懂」。**一局之內清單不變**，
	#   所以滑桿仍然恆在同一位置（R-1／R-15 要保的是那一件事）。
	var rows: Array = []
	for type: String in NodeDefs.PRIORITY_ROWS:
		if type == "core" or _buildable().has(type):
			rows.append(type)
	var split := 0
	for type: String in rows:
		if NodeDefs.PRIORITY_ROWS.find(type) < NodeDefs.PRIORITY_SPLIT:
			split += 1
	for i in rows.size():
		var type := String(rows[i])
		var row := UiKit.hbox(4)
		var name_label := UiKit.label(NodeDefs.label(type), 15, Palette.TEXT_PRIMARY, false)
		name_label.custom_minimum_size = Vector2(52, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		var down := Button.new()
		down.text = "◀"
		down.pressed.connect(_on_priority.bind(type, -1))
		row.add_child(UiKit.touchable(down))
		var value := UiKit.label("", 17, Palette.ENERGY_AMBER)
		value.custom_minimum_size = Vector2(24, 0)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		_prio_labels[type] = value
		var up := Button.new()
		up.text = "▶"
		up.pressed.connect(_on_priority.bind(type, 1))
		row.add_child(UiKit.touchable(up))
		(lanes[0] if i < split else lanes[1]).add_child(row)
	add_child(box)
	_prio_panel = box
	_refresh_priority()


## ★ 操作說明抽屜（`50_QA_PLAN.md` §4.4）。
##
## **它存在的理由是一句實測回饋**：使用者拿到 B0.7 的 build，第一句話是
## 「你沒教我要怎麼操作」。當時提示列只講「下一步的目標」，從頭到尾沒有任何
## 地方講過「蓋東西」＝左欄選一種、再左鍵點地圖——那是一條靠試錯才學得到的規則，
## 而試錯要花掉的正是那 60 秒準備期。
##
## **預設開在空地圖上、有東西之後就不再擋路**：不用存檔旗標（那要跨局狀態），
## 用「這一局蓋了東西沒有」判斷——玩家一放下第一個節點就代表他會操作了。
## 這張圖有幾座橋，說明就講幾座。零座也是一句有用的話——
## 「這一關不用擔心過路徑」本身就是關卡設計要傳達的訊息（§7.9 第 1 關）。
func _bridge_line() -> String:
	var n: int = (s.sets["crossings"] as Dictionary).size()
	if n <= 0:
		return "　導管不能跨過敵人路徑（紫帶）——這張圖沒有橋，所有東西都在同一側"
	return "　導管要過敵人路徑（紫帶）只能走「橋」——路徑上那 %d 段架高結構" % n


func _build_help_panel() -> void:
	var box := UiKit.panel(0.94)
	box.position = Vector2(150, 250)
	var col := UiKit.vbox(3)
	box.add_child(col)
	for line: String in [
		"操作　全部只用滑鼠左鍵，沒有鍵盤、沒有右鍵",
		"　蓋節點：左欄選一種 → 左鍵點地圖上的一格",
		"　拉導管：「連線」→ 點起點節點 → 點終點節點",
		"　加　粗：「加粗」→ 點導管的中間（不是兩端的節點）",
		"　拆　除：「拆除」→ 點節點或導管，返還 75%",
		"",
		"規則",
		"　導管只能走 水平／垂直／45°，要轉彎先放一個「中繼」",
		# ★ 座數讀地圖，不寫死（B1.2）：第 1 關一座橋都沒有，跟新手講
		#   「路徑上那三段架高結構」只會讓他去找一個畫面上不存在的東西。
		_bridge_line(),
		"　節點不能蓋在敵人路徑上",
		"　敵人走過時會打壞相鄰 1 格的東西 → 塔與導管退開 2 格就安全",
		"　塔只有交戰時吃電，待機 0：約束是「峰值電力」，不是平均",
		"",
		"底欄　快進 4×（只有準備期）｜提前召喚（提早開波換掉落倍率）｜優先權（缺料時誰先餓死）",
	]:
		if line == "":
			col.add_child(_spacer(6))
			continue
		var head := not line.begins_with("　")
		col.add_child(UiKit.label(
			line, 15 if head else 14,
			Palette.ORDER_BRIGHT if head else Palette.TEXT_PRIMARY, false
		))
	# （不吃滑鼠由 `UiKit.panel()` 保證——這一張曾經預設開在玩家要放第一個
	#   節點的位置上並把那片點擊整片吞掉，等於教學把遊戲擋住了。RG-39）
	add_child(box)
	_help_panel = box
	# 空地圖＝這局還沒開始，正是需要它的時刻。TL_NAKED 下不開（它整片都是文字）。
	var fresh: bool = s.nodes.size() <= 1 and not Hooks.naked
	box.visible = fresh
	_help_auto = fresh
	_help_button.set_pressed_no_signal(fresh)


func _on_toggle_help(open: bool) -> void:
	_help_panel.visible = open


## ★ 能量收支面板（使用者要求：「不太清楚怎樣的操作可以讓能量增加、哪些會減少」）。
##
## 頂欄的能量條說的是**結果**（供給 30／需求 37），它不說「這 37 是誰吃的」。
## 這張表把每一項逐條攤開並**即時跟著跑**，所以它同時是答案與教材：
## 玩家蓋一台發電機，`+` 那一欄當場多 20——因果在同一個畫面上發生。
##
## 只列**這一局真的存在**的項目：一張永遠有八行的表沒有資訊量，
## 有幾行會動、什麼時候動，本身就是資訊。
func _build_energy_panel() -> void:
	var box := UiKit.panel()
	box.position = Vector2(872, 96)
	box.visible = false
	# ★ **固定尺寸、固定列數**（B0.7.4）。使用者回報「面板會因為一些小改動
	#   一直跳動，很難看清楚」——原因是沒有數值的列會自己隱藏，`PanelContainer`
	#   跟著縮放，於是每過一個 tick 版面就位移一次。
	#   **一張一直在動的表，讀不了**。現在列數恆定、寬度恆定，
	#   不存在的項目留在原位變暗——**位置固定本身就是可讀性**。
	# 320 ＝ 標題 ＋ 14 列 ×（17 ＋ 3）＋ 邊距。B1.1 多了「熔爐」一列。
	box.custom_minimum_size = Vector2(392, 320)
	var col := UiKit.vbox(3)
	box.add_child(col)
	col.add_child(UiKit.label("能量收支（每秒）", 15, Palette.ENERGY_AMBER, false))
	for key: String in ENERGY_ROWS:
		var l := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		l.custom_minimum_size = Vector2(380, 17)
		col.add_child(l)
		_energy_rows[key] = l
	add_child(box)
	_energy_panel = box


func _on_toggle_energy(open: bool) -> void:
	_energy_panel.visible = open


func _refresh_energy() -> void:
	if _energy_panel == null or not _energy_panel.visible:
		return
	var r: Dictionary = s.rates
	var gen := 0.0
	var reclaim := 0.0
	var tower := 0.0
	# 熔爐的耗能**不能併進任何一列既有的**：它既不是交戰耗能（待機也吃），
	# 也不是儲槽充能。B1.1 之前 `silo_in = demand − tower` 會把熔爐那 10/秒
	# 記到儲槽頭上——面板從此開始說謊。
	var smelt := 0.0
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		gen += float(def.get("power_out", 0.0)) * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		if def.has("reclaim"):
			reclaim += float(n["buffer"])
		smelt += float(def.get("power_in", 0.0))
		if _engaged.get(int(n["id"]), false):
			tower += float(def.get("engage_power", 0.0))
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var silo_out := maxf(0.0, supply - gen)
	var silo_in := maxf(0.0, demand - tower - smelt)
	var net := supply - demand

	_set_row("gen", "＋ 發電機 ×%d　%+.0f" % [s.count_of("generator"), gen],
		gen > 0.05, Palette.ENERGY_AMBER)
	_set_row("silo_out", "＋ 儲槽放電　%+.0f" % silo_out, silo_out > 0.05, Palette.ENERGY_AMBER)
	_set_row("reclaim", "＋ 回收者存量　%.0f（擊殺換來的，限速注入）" % reclaim,
		reclaim > 0.05, Palette.ENERGY_AMBER)
	_set_row("sep1", "─────────────────", false)
	_set_row("tower", "− 塔（交戰 %d 座）　%.0f" % [int(r["engaged"]), tower], tower > 0.05)
	_set_row("smelt", "− 熔爐 ×%d　%.0f（待機也吃）" % [s.count_of("smelter"), smelt],
		smelt > 0.05)
	_set_row("silo_in", "− 儲槽充能　%.0f（受自己那條線限速）" % silo_in, silo_in > 0.05)
	_set_row("sep2", "─────────────────", false)

	# ★ 「誰餵不飽」（使用者要求）。淨值只說「差多少」，不說「誰在挨餓」——
	#   而玩家能採取的動作（拉優先權、加粗那條線、多蓋一台發電機）取決於後者。
	#   名單直接取三態徽章的 `STARVED`，與地圖上的橙色倒三角是同一份判定。
	var short_list: Array[String] = []
	var states: Dictionary = r["node_state"]
	for n: Dictionary in s.nodes:
		if int(states.get(int(n["id"]), 0)) != SessionState.STARVED:
			continue
		short_list.append("%s%s %.0f%%" % [
			NodeDefs.label(String(n["type"])), n["cell"],
			100.0 * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		])

	var ok_all := short_list.is_empty()
	_set_row("net", "淨值　%+.0f/秒　%s" % [net, "餵得飽" if ok_all else "有東西在挨餓"], true,
		Palette.OK_GREEN if ok_all else Palette.WARN_ORANGE)
	for i in SHORT_ROWS:
		var key := "short%d" % i
		if ok_all:
			_set_row(key, "　全部餵得飽" if i == 0 else "", false)
		elif i == SHORT_ROWS - 1 and short_list.size() > SHORT_ROWS:
			_set_row(key, "　…還有 %d 座" % (short_list.size() - SHORT_ROWS + 1), true,
				Palette.WARN_ORANGE)
		elif i < short_list.size():
			_set_row(key, "　餵不飽：" + short_list[i] if i == 0 else "　　　　　" + short_list[i],
				true, Palette.WARN_ORANGE)
		else:
			_set_row(key, "", false)

	_set_row("tip", "加電：多蓋發電機（每台吃 4 礦砂/秒）", false)
	_set_row("tip2", "省電：塔少一點，或用「優先權」決定誰先餓", false)


## `live` ＝ 這一項現在有沒有在作用。**沒作用的列不隱藏、只變暗**——
## 隱藏會讓下面每一列往上跳，而一張一直在動的表讀不了（B0.7.4）。
func _set_row(key: String, text: String, live: bool, col: Color = Palette.TEXT_SECONDARY) -> void:
	var l: Label = _energy_rows[key]
	l.text = text
	l.add_theme_color_override("font_color", col if live else Palette.TEXT_DISABLED)


## ★ 角色簡介浮層（使用者要求）。滑鼠停在左欄的建造鈕上就浮出來、移開就收，
## 底欄「圖鑑」可整個關掉。**半透明**：它蓋在地圖上，要讓人看得見底下是什麼。
##
## 內容一律**從 `data/NodeDefs.gd` 現算**，不另外寫一份文案表——
## 兩份會漂移，而漂移的那一份剛好就是玩家讀到的那一份。
func _build_codex_panel() -> void:
	# 角色簡介刻意半透明：它浮在地圖上，要讓人看得見底下是什麼（使用者指定）。
	var box := UiKit.panel(0.88)
	box.visible = false
	_codex_label = UiKit.label("", 14, Palette.TEXT_PRIMARY, false)
	box.add_child(_codex_label)
	add_child(box)
	_codex_panel = box


func _on_codex_show(type: String, from: Button) -> void:
	if not _codex_on or Hooks.naked:
		return
	_codex_label.text = "\n".join(_codex_lines(type))
	_codex_panel.visible = true
	# 貼著那顆鈕的右側浮出來，垂直對齊它——視線不必離開來源。
	_codex_panel.position = Vector2(124.0, clampf(from.global_position.y - 8.0, 56.0, 470.0))


func _on_codex_hide() -> void:
	_codex_panel.visible = false


## 一種節點的簡介。**先講它在取捨裡的位置，再列數字**——
## 一串沒有脈絡的數值幫不了正在決定「這一分鐘要蓋什麼」的人。
func _codex_lines(type: String) -> Array[String]:
	var def := NodeDefs.of(type)
	var out: Array[String] = [BuildController.price_text(type)]
	out.append({
		"extractor": "礦砂的源頭。只能蓋在礦點上，而且要接到核心才入帳。",
		"generator": "把礦砂燒成能量。它是你唯一的發電來源，也是礦砂的第一大支出。",
		"smelter": "合金的唯一來源。它同時吃礦砂與電，而且「待機也吃」——蓋下去那一刻起，你的塔就少了 10 能量/秒。合金也要接到核心才入帳。",
		"breaker": "濺射：打中最前那一隻，順便打到它周圍 2.5 格內的每一隻。單打比錨還弱，只有敵人擠成一團時才划算。",
		"relay": "轉彎與分岔用。導管只能走直線與 45°，所有拐角都靠它。",
		"silo": "準備期存電、波次期放電。充放電速率受「它自己那條導管的 cap」限制——擺太遠或線太細，電趕不到前線。",
		"anchor": "最便宜的塔，物理傷害。護甲是減法，打甲殼很吃虧。",
		"prism": "最貴的塔，能量傷害穿透一直線。與路徑同一列時可一次貫穿整段——擺位就是它的謎題。",
		"knell": "不開火。減速 40% ＋ 破甲 25%，多座不疊加取最強。它讓別的塔變強。",
		# `Label` 不解析 Markdown——`**任何**` 會原樣印出兩排星號（B0.7.1／B0.7.3
		# 各犯過一次，這裡是第三處，B1.1 一併掃掉）。強調一律用「」。
		"reclaimer": "射程內「任何」敵人死亡就回收能量（不限自己擊殺）。蹲在擊殺點上，不是蹲在它自己射得爽的地方。",
	}.get(type, ""))
	if def.has("ore_out"):
		out.append("產出　＋%.0f 礦砂/秒" % float(def["ore_out"]))
	if def.has("ore_in"):
		out.append("燃料　−%.0f 礦砂/秒" % float(def["ore_in"]))
	if def.has("power_out"):
		out.append("產出　＋%.0f 能量/秒" % float(def["power_out"]))
	if def.has("alloy_out"):
		out.append("產出　＋%.0f 合金/秒" % float(def["alloy_out"]))
	if def.has("power_in"):
		out.append("耗能　−%.0f 能量/秒（一直吃）" % float(def["power_in"]))
	if def.has("capacity"):
		out.append("容量　%.0f 能量" % float(def["capacity"]))
	if def.has("engage_power"):
		out.append("耗能　交戰時 −%.0f 能量/秒（待機 0）" % float(def["engage_power"]))
	if def.has("range"):
		out.append("射程　%.0f 格　射速 %.1f 發/秒　傷害 %.0f（%s）%s" % [
			float(def["range"]), float(def.get("rof", 0.0)), float(def.get("dmg", 0.0)),
			"能量" if String(def.get("dmg_type", "physical")) == "energy" else "物理",
			"　濺射 %.1f 格" % float(def["splash"]) if def.has("splash") else ""
		])
	out.append("生命　%.0f　※ 退開敵人路徑 2 格就打不到" % NodeDefs.hp(type))
	return out


func _on_toggle_priority(open: bool) -> void:
	_prio_panel.visible = open


func _on_priority(type: String, delta: int) -> void:
	s.priorities[type] = clampi(
		int(s.priorities.get(type, 1)) + delta, NodeDefs.PRIORITY_MIN, NodeDefs.PRIORITY_MAX
	)
	_refresh_priority()


## TL_NAKED 明文包含「優先權面板刻度」（`30_TECH_DESIGN.md` §4.1）：
## 刻度是數值標籤，改用琥珀小方塊表示同一個 1–5，形狀仍讀得出高低。
func _refresh_priority() -> void:
	for type: String in _prio_labels:
		var v := int(s.priorities.get(type, 1))
		(_prio_labels[type] as Label).text = "▪".repeat(v) if Hooks.naked else str(v)


## 左欄的工具鈕。`toggle_mode` ＋ 共用群組 ＝ 內建的「選中」外觀，
## 不必自己塗顏色（`20_ART_DIRECTION.md`：能用主題就別硬編碼色值）。
func _tool_button(group: ButtonGroup, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_build_type(type: String) -> void:
	_mode = Mode.BUILD
	_build_type = type
	_connect_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


func _on_mode(mode: int) -> void:
	_mode = mode
	_connect_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


func _refresh_top() -> void:
	_refresh_summon()
	# TL_NAKED：隱藏所有數值標籤，只留線寬／顏色（`30_TECH_DESIGN.md` §4.1）。
	# **能量條不在此列**——它是圖形，長度即資訊（§6.2 硬性要求 1），畫在 `_draw()`。
	if Hooks.naked:
		_top.visible = false
		return
	var r: Dictionary = s.rates
	var core_full := NodeDefs.hp("core")
	var core_col: Color = (
		Palette.WARN_ORANGE if s.core_hp() < core_full else Palette.ORDER_BRIGHT
	)
	var texts := [
		["礦砂 %s　▲%.1f/秒" % [UiKit.commas(int(s.ore)), r["ore_in"]], Palette.ORDER_CYAN],
		# 合金緊貼礦砂：**兩個都是造價貨幣**，玩家看的是同一個問題（我買得起嗎）。
		# 它擠掉的是「節點 N　導管 M」——那是開發用的計數，沒有任何決定依賴它，
		# 而頂欄的寬度是有限的（B1.1）。
		["合金 %s　▲%.1f/秒" % [UiKit.commas(int(s.alloy)), r["alloy_in"]], Palette.ALLOY_VIOLET],
		["能量 %.0f/%.0f" % [r["power_supply"], r["power_demand"]], Palette.ENERGY_AMBER],
		["儲槽 %.0f/%.0f" % [r["silo_charge"], r["silo_capacity"]], Palette.ENERGY_AMBER],
		# 「能量需求為什麼突然翻倍」這個問題的答案永遠是交戰座數（§7.4 峰值約束）。
		["交戰 %d 座　擊殺 %d" % [int(r["engaged"]), s.kills], Palette.ENERGY_AMBER],
		[_phase_text(), Palette.TIDE_MAGENTA if s.phase == "wave" else Palette.TEXT_SECONDARY],
		["核心 %.0f/%.0f" % [maxf(0.0, s.core_hp()), core_full], core_col],
	]
	for i in texts.size():
		var l := _top.get_child(i) as Label
		l.text = String(texts[i][0])
		l.add_theme_color_override("font_color", texts[i][1])


## 準備期顯示倒數（**計時器就在畫面上**——它是關卡參數不是隱藏係數，§7.7）。
func _phase_text() -> String:
	match s.phase:
		"prep":
			var left: float = maxf(0.0, s.prep_time() - s.phase_time)
			var ff := "　▶%d×" % s.speed_mult if s.speed_mult > 1 else ""
			# 駐足在核心的敵人不會隨波次結束而消失（§3.5）。不講的話，
			# 玩家會看到核心在準備期掉血卻找不到原因。
			var left_over := "　殘敵 %d" % s.enemies.size() if not s.enemies.is_empty() else ""
			return "準備期 %0.1fs　下一波 %d%s%s" % [left, s.wave_index + 1, ff, left_over]
		"wave":
			return "第 %d 波　敵人 %d" % [s.wave_index, s.enemies.size()]
		"won":
			return "通關"
		_:
			return "核心已毀"


## 快進只在準備期能按（`10_GDD.md` B5：可跳過等待，戰鬥期不可加速也不可減速）。
func _on_fast_forward() -> void:
	if s.phase != "prep":
		return
	s.speed_mult = 1 if s.speed_mult > 1 else FAST_FORWARD_RATE
	_refresh_top()


## ★ 提前召喚：**按鈕常駐顯示當前獎勵倍率**（`10_GDD.md` §6.2 硬性要求 3）——
## 下注的誘惑要一直在眼前，而不是按下去才知道賭到多少。
## 倍率隨倒數每 tick 縮水，所以這個字串每幀重算。
func _refresh_summon() -> void:
	if _summon_button == null:
		return
	var can: bool = s.phase == "prep"
	_summon_button.disabled = not can
	if Hooks.naked or not can:
		_summon_button.text = "提前召喚"
		return
	var bonus := Score.summon_bonus(maxf(0.0, s.prep_time() - s.phase_time), s.prep_time())
	_summon_button.text = "提前召喚 +%d%%" % roundi((bonus - 1.0) * 100.0)


func _on_summon_now() -> void:
	BattleController.start_wave(s)
	_refresh_top()


## 局末結算（通關或核心歸零）。三個數字照 `10_GDD.md` §7.6 逐項攤開——
## **玩家要看得出研究數據是怎麼算出來的**，一個總分教不會他下一局該改什麼。
## **重來按鈕必須在 1 次點擊之內**（`50_QA_PLAN.md` §4.4），
## 而且失敗不扣任何東西（紅線 R1）——局內狀態本來就不持久化。
func _refresh_over() -> void:
	if _ff_button != null:
		_ff_button.disabled = s.phase != "prep"
	if s.phase != "lost" and s.phase != "won":
		if _over_panel != null:
			_over_panel.queue_free()
			_over_panel = null
		return
	if _over_panel != null:
		return
	var won: bool = s.phase == "won"
	var waves: int = s.wave_index if won else maxi(0, s.wave_index - 1)
	var score := Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK)
	var box := UiKit.panel()
	box.position = Vector2(440, 230)
	var col := UiKit.vbox(10)
	box.add_child(col)
	col.add_child(UiKit.label(
		"通關" if won else "核心已毀", 32, Palette.OK_GREEN if won else Palette.TIDE_MAGENTA
	))
	# ★ 星等與獎勵只在戰役關卡有（測試圖與沙盤沒有進度可寫）。
	if not level.is_empty():
		var stars := Score.stars(
			won, s.core_hp(), NodeDefs.hp("core"), score, float(level["star_throughput"])
		)
		var gain := SaveService.apply_result(
			GameState.data, String((level["map"] as Dictionary)["id"]),
			stars, int(level["reward"])
		)
		SaveService.save_from(GameState.data)
		col.add_child(UiKit.label(
			"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars), 28, Palette.ENERGY_AMBER
		))
		for line: String in _star_lines(stars, score):
			col.add_child(UiKit.label(line, 14, Palette.TEXT_SECONDARY, false))
		if gain > 0.0:
			col.add_child(UiKit.label(
				"關卡獎勵　＋%.0f 研究數據" % gain, 15, Palette.OK_GREEN, false
			))
	for line: String in [
		"撐過 %d 波　　＋%.0f 研究數據" % [waves, Score.DATA_PER_WAVE * float(waves)],
		"產能積分 %.1f（送達核心 %s 礦砂）　＋%.0f" % [
			score, UiKit.commas(int(s.delivered_total)), Score.DATA_PER_SCORE * score
		],
		"提前召喚累計加成　　＋%.0f" % s.bonus_data,
		"研究數據合計 %.0f　　擊殺 %d" % [
			Score.research_data(waves, score, s.bonus_data), s.kills
		],
		"失敗不扣任何東西" if not won else "",
	]:
		if line != "":
			col.add_child(UiKit.label(line, 15, Palette.TEXT_SECONDARY, false))
	var buttons := UiKit.hbox(8)
	col.add_child(buttons)
	var again := Button.new()
	again.text = "立刻重來"
	again.pressed.connect(_restart)
	buttons.add_child(UiKit.touchable(again))
	if on_exit.is_valid():
		var back := Button.new()
		back.text = "回關卡選擇"
		back.pressed.connect(on_exit)
		buttons.add_child(UiKit.touchable(back))
	# 面板本身不吃滑鼠（`UiKit.panel` 的 RG-39），但**這兩顆鈕要點得到**。
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)
	_over_panel = box


## 三顆星各自的達成與否，逐條講清楚——**沒拿到的那顆要說出差在哪**，
## 不然「兩顆星」只是一個沒有下一步的評分。
func _star_lines(stars: int, score: float) -> Array[String]:
	var threshold := float(level["star_throughput"])
	var out: Array[String] = [
		"%s 通關" % ("★" if stars >= 1 else "☆"),
		"%s 核心無損（%.0f/%.0f）" % [
			"★" if stars >= 2 else "☆", s.core_hp(), NodeDefs.hp("core")
		],
		"%s 產能積分 %.2f ／ 門檻 %.2f" % ["★" if stars >= 3 else "☆", score, threshold],
	]
	return out


func _restart() -> void:
	for c: Node in get_children():
		c.queue_free()
	_over_panel = null
	_top = null
	_hint = null
	_ff_button = null
	_summon_button = null
	_prio_panel = null
	_help_panel = null
	_help_button = null
	_energy_panel = null
	_energy_button = null
	_codex_panel = null
	_codex_button = null
	_codex_label = null
	_zoom_button = null
	_energy_rows.clear()
	_prio_labels.clear()
	_mode_buttons.clear()
	_build_buttons.clear()
	_mode = Mode.BUILD
	_build_type = "extractor"
	s = SessionState.new()
	_setup_session()
	_accum = 0.0
	_message = ""
	_build_ui()


func _refresh_hint() -> void:
	if Hooks.naked:
		_hint.visible = false
		return
	# ★ 兩行：**上行永遠是「下一步」，下行才是當下這個動作的細節。**
	# B0.7 原本讓預覽「取代」下一步，於是玩家把滑鼠移到地圖上——正是最需要
	# 指引的那一刻——指引就消失了。使用者實玩後的第一句話是「你沒教我怎麼操作」。
	var parts: Array[String] = []
	match _mode:
		Mode.BUILD:
			if _in_map(_hover):
				parts.append_array(BuildController.preview_place(s, _build_type, _hover)["lines"])
			else:
				parts.append("建造 %s：把滑鼠移到地圖上，左鍵點一格放下。" % NodeDefs.label(_build_type))
		Mode.CONNECT:
			if _connect_from.x >= 0 and _in_map(_hover):
				# 起點選好之後就逐格回報「這一條連不連得成、為什麼」，
				# 不必點下去才知道（八條導引線同時畫在地圖上）。
				parts.append(_connect_hint())
			else:
				parts.append("連線：左鍵點「起點節點」，再點「終點節點」。只能走水平／垂直／45°，轉彎要先放中繼；過敵人路徑只能走橋。")
		Mode.UPGRADE:
			parts.append("加粗：左鍵點一段導管的「中間」（不是兩端的節點）。每級 +6 吞吐，上限 3 級（→28）。1 級 20 礦砂；2 級 40 礦砂＋20 合金；3 級 60 礦砂＋50 合金。")
		Mode.DEMOLISH:
			parts.append("拆除：左鍵點節點或導管，返還 75%%。")
	if _message != "":
		parts.append(_message)
	_hint.text = "▶ %s\n%s" % [_next_step(), "　".join(parts)]


## ★ 下一步（`50_QA_PLAN.md` §4.4「新玩家開局後 15 秒內知道要做什麼嗎」）。
##
## 這**不是教學系統**，是一句讀當前狀態算出來的話——沒有進度旗標、沒有步驟機、
## 不持久化，玩家拆光重蓋它就跟著退回去。做成教學系統的話它會變成第二套要維護的
## 狀態，而且擋在玩家和遊戲之間；一行提示不會。
##
## 順序＝這張圖真正的依賴鏈：礦→入帳→電→塔→接電。
##
## **每一條都要講出「按哪裡、點哪裡」，不能只講目標。** 使用者實玩 B0.7 的第一句
## 回饋是「你沒教我要怎麼操作」——那時這些字串寫的是「先蓋一台採集器」，
## 而畫面上沒有任何地方說過「蓋」＝左欄選一種、再左鍵點地圖。
## 一句只說目標不說動作的提示，對已經會玩的人是提醒，對新玩家是零。
func _next_step() -> String:
	if s.count_of("extractor") == 0:
		return "左欄點「採集器」→ 左鍵點地圖上任一個青色空心圓（礦點）。這是所有東西的源頭。"
	if float(s.rates["ore_in"]) <= 0.0:
		return "礦砂要「送達核心」才入帳：左欄點「連線」→ 點採集器 → 點下一個節點，一路接到右下角的核心。"
	if s.count_of("generator") == 0:
		return "有礦砂了（看頂欄 ▲/秒）。左欄點「發電機」蓋一台，再用「連線」把礦砂線接給它：4 礦砂/秒 → 20 能量/秒。"
	if _towers() == 0:
		return "電有了。左欄點「錨」（最便宜的塔）蓋在「離紫色路徑 2 格以上」的地方——貼太近會被走過的敵人打壞。"
	if _unpowered_tower():
		return "那座塔還沒接進電網，交戰時一發都打不出：左欄點「連線」，把它接到發電機那一側。"
	# 合金是第三資源，但它排在「防線先站得住」之後才提——B0.7 的教訓是
	# 提示列一次只能給一件事做，塞第二條路線只會讓玩家兩件都不做。
	#
	# ★ **這一關沒解鎖熔爐就不准提它**（B1.2）：叫人去點一顆畫面上不存在的鈕，
	#   比不給提示更糟——玩家會以為是自己看漏了，然後花掉整個準備期在找。
	if _buildable().has("smelter") and s.count_of("smelter") == 0 and s.alloy <= 0.0:
		return "防線站住了。想加粗幹線到 2 級以上%s，都要合金：左欄點「熔爐」，它吃 8 礦砂/秒 ＋ 10 能量/秒，產 2 合金/秒。" % (
			"、或蓋「碎浪」" if _buildable().has("breaker") else ""
		)
	if s.count_of("smelter") > 0 and float(s.rates["alloy_in"]) <= 0.0:
		return "熔爐產的合金也要「送達核心」才入帳：用「連線」把熔爐一路接到核心，同時它的礦砂與電也都要接得到。"
	if s.phase == "prep":
		return "都齊了。等倒數跑完自動開波，或按「提前召喚」提早開——倒數剩越多，這一波掉落倍率越高。"
	return "波次進行中：盯著頂端能量條，橙色那截就是餵不飽的部分；節點上的橙色倒三角＝這個缺料。"


## 連線預覽的逐格回報。**連不成的時候要說出差在哪**——「不是 45°」對玩家
## 沒有動作可做，「橫 4 直 3，要 4/4 或 3/3」才有。
func _connect_hint() -> String:
	if s.node_at(_hover).is_empty():
		return "終點也要是一個節點（先在那裡蓋一個「中繼」）。"
	var code: String = Build.can_connect(s.sets, s.conduit_keys(), _connect_from, _hover)
	if code == Build.NOT_STRAIGHT:
		var d: Vector2i = _hover - _connect_from
		return "✕ 不是直線：橫 %d 直 %d。要走 45° 兩邊得一樣長；否則先放一個「中繼」轉彎。" % [
			absi(d.x), absi(d.y)
		]
	if code != Build.OK:
		return "✕ " + BuildController.reason_text(code)
	var cost := Build.conduit_cost(_connect_from, _hover)
	var afford := "" if s.ore >= float(cost) else "　（礦砂不夠）"
	return "✔ 可連：%s → %s，%d 礦砂%s" % [
		_label_at(_connect_from), _label_at(_hover), cost, afford
	]


func _towers() -> int:
	var n := 0
	for node: Dictionary in s.nodes:
		if NodeDefs.of(String(node["type"])).get("tower", false):
			n += 1
	return n


## 有沒有塔完全沒接上任何導管？（接了但電不夠是另一回事，那由三態徽章講。）
func _unpowered_tower() -> bool:
	for node: Dictionary in s.nodes:
		if not NodeDefs.of(String(node["type"])).get("tower", false):
			continue
		var wired := false
		for c: Dictionary in s.conduits:
			if c["a"] == node["cell"] or c["b"] == node["cell"]:
				wired = true
				break
		if not wired:
			return true
	return false


# ── 截圖用的示範佈局（只在 TL_PANEL=battle 時建立）─────────────────────
#
# 指令表在 `data/Maps.gd`，與 `TL_SIM` 的 headless 跑局共用同一份——
# 截圖與數字看的必須是同一個局面。
func _demo_layout() -> void:
	# ★ 戰役關卡用它自己的參考解（`data/Campaign.gd`），與 `campaign_test`
	#   跑的是同一份腳本——**截圖與那支測試印出來的數字保證是同一個局面**。
	#   `TL_DEMO_TICKS` 給得夠大就會跑到局末，星等面板才拍得到。
	if not level.is_empty():
		var step := func(st: RefCounted) -> void: BattleController.step(st)
		for f: Dictionary in BuildController.apply_timeline(s, level["demo"], step):
			push_warning("參考解第 %d 步失敗：%s" % [f["index"], f["reason"]])
		for _i in Hooks.demo_ticks:
			BattleController.step(s)
		return

	var sandbox: bool = Hooks.panel == "sandbox"
	# 沙盤的佈局全部是純礦砂造價（沒有加粗），所以那邊不發合金——
	# **合金要從畫面上那座熔爐煉出來，那正是那張圖要證明的事。**
	s.alloy = 0.0 if sandbox else MapsData.DEMO_ALLOY
	var failures := BuildController.apply_ops(
		s, MapsData.SANDBOX_DEMO if sandbox else MapsData.SHOAL_DEMO
	)
	for f: Dictionary in failures:
		push_warning("示範佈局第 %d 步失敗：%s" % [f["index"], f["reason"]])
	# 快轉到敵潮進入塔的射程。等真實時間跑 86 秒等於讓使用者的桌面開著一個
	# 視窗發呆一分半，模擬本來就不吃 delta，直接推 tick 就好。
	#
	# ★ **推的是 tick，不是階段**（B0.6 改）：讓準備期自己倒數完、波次自己開。
	# 舊寫法直接呼叫 `start_wave()` 把倒數跳過去，B0.5 還沒差別，B0.6 之後
	# 那等於一次滿額的提前召喚（倍率 1.5），截圖的掉落數字會和 `TL_SIM`
	# （自然開波）對不起來。現在 `TL_DEMO_TICKS=N` 與 `TL_SIM=N` 是同一個局面。
	for _i in Hooks.demo_ticks:
		BattleController.step(s)
