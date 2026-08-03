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
const MapGen := preload("res://scripts/sim/MapGen.gd")
const CampaignData := preload("res://data/Campaign.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const SettingsScreen := preload("res://scripts/screens/Settings.gd")

## ★ 「快」的門檻（B1.6.3、`20_ART_DIRECTION.md` §1.7）。超過就給拖尾與流線輪廓。
## 取在 1.2：現行三種是 1.6／1.0／0.6，門檻落在漂蟲（基準 1.0）之上一截，
## 所以 M3 補敵人時「比基準明顯快」才拿得到這個視覺，不是隨便快一點就有。
const SWIFT_SPEED := 1.2

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
## 縮放上限＝**下限**的幾倍。
##
## ★ 下限在 B2.1b 從「就是 fit」改成 `max(fit, 可讀性地板)`：
##   一屏可見的圖（全部戰役關卡）fit 本來就在地板之上 → 行為完全不變；
##   大過一屏的圖（無盡）fit 會讓一格掉到 24px 以下，而那正是 RG-59 說
##   「要重新驗收才能跨過」的線——**縮到看得見全圖但讀不出瓶頸，等於
##   把 R-3 的驗收轉包給玩家**。所以無盡看全圖的地方是小地圖，不是主畫面。
const ZOOM_MAX_MULT := 3.0
const ZOOM_STEP := 1.25

## 小地圖（B2.1b、`20_ART_DIRECTION.md` §1.8）。**只在地圖大過框架時出現**
## ——戰役全部一屏可見，問題節點就在畫面上，多一個浮層只是多一塊遮擋。
const MINIMAP_MAX := Vector2(232.0, 140.0)
const MINIMAP_PAD := 12.0
## 邊緣箭頭上限。**十個箭頭等於沒有箭頭**（§2 反模式：資訊過載）。
const ARROW_MAX := 3
const ARROW_SIZE := 11.0
## 箭頭的命中半徑。P3 手機移植預留條款要求 ≥ 44×44 px，所以半徑取 22。
const ARROW_HIT := 22.0

## `10_GDD.md` §7.1。**只在準備期可用。**
const FAST_FORWARD_RATE := 4

## `TL_STRESS`：丟掉的暖身幀數與實際量測幀數。
const STRESS_WARMUP := 30
const STRESS_FRAMES := 240

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

## ★ B1.3.1：`CONNECT` 與 `PAN` 兩個模式已刪。拉線一律是拖曳（B1.6.2 取代了
## 「連線」模式），平移是滑鼠中鍵按住拖——**兩件事都不該是模式**：
## 模式的代價是「忘記切回來時點地圖沒反應」，而這兩個動作都頻繁到會天天付這個代價。
enum Mode { BUILD, UPGRADE, DEMOLISH }

var s: RefCounted = null

## ★ 這一局打的是哪一關（`data/Campaign.gd` 的一筆）。**空字典＝測試圖／沙盤**，
## 那條路徑沒有星等、沒有解鎖限制、也不寫存檔。
## 由呼叫端在 `add_child()` **之前**指派——`_ready()` 一進來就要用它。
var level: Dictionary = {}
## ★ 無盡模式的地圖種子（B2.1a）。**0 ＝ 不是無盡局**。
## 刻意不塞進 `level`：那個字典的每個讀取端都假設有 `star_throughput`／`reward`，
## 而無盡沒有星等也沒有關卡獎勵——共用會換來一堆 `if level.has(...)`。
## 由呼叫端在 `add_child()` 之前指派，同 `level`。
var endless_seed: int = 0
## 回關卡選擇。測試圖沒有上一層，所以是 Callable 而不是寫死的場景切換。
var on_exit: Callable = Callable()

## 視野（B1.2.2）。`_fit` 是「剛好填滿框架」的倍率，也是縮放下限。
var _zoom: float = 1.0
var _fit: float = 1.0
## 平移（螢幕像素）。fit 時恆為 0（地圖與框架同大，居中就是全貌）。
var _pan: Vector2 = Vector2.ZERO
## ★ 平移的**目標**（B2.1d）。`_pan` 每幀朝它收斂，所以小地圖拖曳與一鍵跳
## 都是平滑的。**中鍵直接拖地圖不走這條**——直接拖曳加上緩動會變成「黏手」，
## 手指到哪畫面就該到哪。`reduce_motion` 開啟時一律直接到位（§1.6 的紀律：
## 動效是裝飾，關掉之後資訊一點都不能少）。
var _pan_goal: Vector2 = Vector2.ZERO
## 每秒收斂比率。14 在 60fps 下約 4 幀走完八成——快到不覺得延遲，
## 又慢到看得出是「滑過去」而不是「跳過去」（使用者要的是後者的反面）。
const PAN_EASE := 14.0
## 小地圖拖曳中。按住不放時視野持續跟著游標走。
var _mini_drag: bool = false
var _zoom_button: Button = null

var _mode: int = Mode.BUILD
var _build_type: String = "extractor"
## 拖曳拉線的起點（B1.6.2）。−1 ＝ 沒有在拉線。
var _drag_from: Vector2i = Vector2i(-1, -1)
## 中鍵按著沒放（B1.3.1）＝正在平移地圖。
var _panning: bool = false
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
## 局內選單（ESC 或左上角「選單」鈕）。`null` ＝ 沒開。
var _menu_layer: Control = null
var _menu_button: Button = null
var _menu_buttons: Array[Button] = []
## 從局內選單開出來的設定浮層。開著時 ESC 由它自己處理（回到選單）。
var _settings_layer: Control = null
## 本幀交戰中的塔 `{id: Array}`。繪圖層自己算——它要畫的是「誰正在吃電」，
## 而模擬只留了一個座數（`rates.engaged`）。
var _engaged: Dictionary = {}
## 本幀每隻敵人身上的光環 `Vector2(減速, 破甲)`，與 `s.enemies` 同索引。
## 和 `_engaged` 一樣是**繪圖層自己算的**：模擬層每 tick 都在算同一份，
## 但它只把結果用在傷害上、沒有留下來，而畫面要畫的是「誰被抓住了」。
var _auras: Array = []
## ★ 音訊（B1.5）。上一幀的幾個數字，用來推導「這一幀發生了什麼」。
## **音效一律從畫面層推導，模擬層維持零副作用**（`CLAUDE.md` 技術慣例）：
## 在 `scripts/sim/` 裡塞一行 `AudioBus.play()` 就等於讓每日挑戰的重播會出聲。
var _audio_prev: Dictionary = {}
## 上一幀看到的 tick 序號（音訊與死因診斷共用的邊緣偵測）。
var _last_tick: int = -1
## 死因歸因的累計（B1.7）。純畫面層，模擬層不知道它的存在。
var _diag: Dictionary = {}
## `TL_STRESS` 的量測狀態。
var _stress_frames: int = 0
var _stress_total: float = 0.0
var _stress_worst: float = 0.0
## 本幀「正在被啃」的格（敵人相鄰 1 格內）。**純渲染推導，不新增任何狀態**
## ——同一份判定模擬層每 tick 都在做（`Tide.in_blast`），這裡只是把它畫出來。
var _threat: Dictionary = {}


func _ready() -> void:
	theme = UiKit.theme()
	# ★ **`set_anchors_and_offsets_preset`，不是 `set_anchors_preset`。**
	# 後者只設錨點不動 offset，本節點的 `size` 一直是 **(0, 0)**——而
	# `_draw()` 用的是絕對座標、`CanvasItem` 的繪圖不受 Control 尺寸裁切，
	# 所以**畫面完全正常，但滑鼠命中區是空的**：整張地圖點不動（B0.7.2）。
	# 這是「看起來對」與「真的對」差最遠的一種缺陷。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ★ 「減少動態效果」（§4.4）。B1.6 之前這是**死設定**：存檔裡有、
	#   沒有任何人讀。設定畫面在 B1.4，在那之前它由存檔預設值（false）決定。
	# `Motion.reduce` 由 `GameState.apply_settings()` 統一設定（B1.4）——
	# 開機一次、設定畫面改一次動一次。這裡不再各讀一份。
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
	# ★ 局外科技（B1.3）。有測試鉤子時 `SaveService.persist=false` → 存檔是預設值
	#   → `unlocked` 為空 → mods 全中性，所以 `TL_*` 的任何一張截圖與任何一支自檢
	#   都不會因為這台機器上玩家買了什麼科技而改變（RG-61 的同一條紀律）。
	var tech: Array = (GameState.data.get("tech", {}) as Dictionary).get("unlocked", [])
	if not level.is_empty():
		s.setup(level["map"], level["unlocked"], tech)
	elif endless_seed != 0:
		# 無盡開局就是全建造欄（§7.10）——它沒有解鎖階梯，而**空 `unlocked`
		# 就是「全部」**（`SessionState.setup()`），不必另外列一份會過期的清單。
		s.setup(MapGen.generate(endless_seed), [], tech)
	elif Hooks.stress:
		# ★ 壓力情境（B1.7、RG-8）：只為了量渲染。模擬在 `_process` 裡凍結——
		#   這一份佈局的單 tick 要 30 秒（`perf_test.gd` 的說明），不凍結的話
		#   量到的會是模擬的耗時，而渲染一幀都畫不完。
		s.setup(MapsData.stress_map(), [], tech)
		s.ore = 9999999.0
		s.alloy = 9999999.0
		BuildController.apply_ops(s, MapsData.stress_ops())
		for i in MapsData.STRESS_ENEMIES:
			s.add_enemy(["drifter", "carapace", "ember"][i % 3])
		s.phase = "wave"
	else:
		s.setup(MapsData.SANDBOX if Hooks.panel == "sandbox" else MapsData.SHOAL, [], tech)
	_reset_view()
	_audio_reset()
	# 兩層一起起跑，戰鬥層先靜音（`AudioBus.music()` 的無縫切層前提）。
	AudioBus.music("battle")


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
func _oversized() -> bool:
	var px := Vector2(s.map["size"]) * Shapes.GRID * _zoom
	return px.x > FRAME.size.x + 0.5 or px.y > FRAME.size.y + 0.5


## 進場（與「全景」鈕）的視野：fit ＋ 居中。
func _reset_view() -> void:
	_fit = _fit_zoom()
	_zoom = _fit
	_pan = Vector2.ZERO
	_pan_goal = Vector2.ZERO
	# ★ `TL_FOCUS="x,y,zoom"`：拍特效的近照（B1.6）。**不會在真實遊玩中生效**
	#   ——它只在有鉤子時存在，而有鉤子時存檔已經是唯讀的。
	if Hooks.focus.x >= 0:
		_zoom = clampf(_fit * Hooks.focus_zoom, _fit, _fit * ZOOM_MAX_MULT)
		var px := Vector2(s.map["size"]) * Shapes.GRID
		_pan_to((px * 0.5 - _center(Hooks.focus)) * _zoom, true)


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
	_pan_goal.x = clampf(_pan_goal.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	_pan_goal.y = clampf(_pan_goal.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))


## 設定平移目標。`immediate` 為真時當場到位——中鍵拖曳、縮放錨定、
## 以及所有測試斷言都走這條（斷言要驗的是「目標對不對」，不是「補間跑完沒」）。
func _pan_to(p: Vector2, immediate: bool = false) -> void:
	_pan_goal = p
	if immediate or Motion.reduce:
		_pan = p
	_clamp_pan()
	queue_redraw()


## 讓補間立刻走完。測試專用——把「動畫還沒到」和「算錯位置」分開。
func _settle_view() -> void:
	_pan = _pan_goal
	_clamp_pan()
	queue_redraw()


## 縮放。`anchor` 是螢幕上要固定不動的那一點（滑鼠位置或框架中心）——
## 少了它，滾輪縮放會把玩家正在看的東西推出畫面。
func _zoom_by(mult: float, anchor: Vector2) -> void:
	var before := _zoom
	_zoom = clampf(_zoom * mult, _fit, _fit * ZOOM_MAX_MULT)
	if is_equal_approx(before, _zoom):
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
	var origin_before := FRAME.position + (FRAME.size - m * before) * 0.5 + _pan
	var k := _zoom / before
	_pan_to(
		anchor - (anchor - origin_before) * k
		- (FRAME.position + (FRAME.size - m * _zoom) * 0.5),
		true
	)
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
	if Hooks.panel == "endless":
		await _guide_selftest()
		return
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
	#   中繼，再從一端拖到另一端。整條路徑都走真實輸入——包含按鈕。
	_press(_build_buttons["relay"])
	var from := Vector2i(10, 10)
	var to := Vector2i(13, 13)     # 正斜角，且遠離路徑（路徑走 y=4 與 x=30）
	_click(from)
	_click(to)
	for _i in 3:
		await get_tree().process_frame
	var diag_placed: bool = s.nodes.size() == before + 3
	_drag(from, to)
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
	_drag(Vector2i(6, 12), Vector2i(7, 13))
	for _i in 3:
		await get_tree().process_frame
	_press(_mode_buttons[Mode.UPGRADE])
	_click_at(_to_screen((_center(Vector2i(6, 12)) + _center(Vector2i(7, 13))) * 0.5))
	for _i in 3:
		await get_tree().process_frame
	var short_diag: int = s.conduit_near(Vector2(6.5, 12.5))
	var upgraded: bool = short_diag >= 0 and int((s.conduits[short_diag])["level"]) == 1

	# ★ 拖曳拉線（B1.6.2）：**全程停在建造模式**。會壞的地方有兩個——按下時
	#   沒把起點記起來、放開的事件沒被路由到——而兩個都只有真的送出
	#   「按下 → 移動 → 放開」三顆事件才驗得出來。
	_press(_build_buttons["relay"])
	_click(Vector2i(3, 8))
	_click(Vector2i(3, 11))
	for _i in 3:
		await get_tree().process_frame
	var wires_before: int = s.conduits.size()
	_drag(Vector2i(3, 8), Vector2i(3, 11))
	for _i in 3:
		await get_tree().process_frame
	var dragged: bool = s.conduits.size() == wires_before + 1 and _mode == Mode.BUILD

	# ★ 中鍵平移（B1.3.1）：「移動」模式鈕拿掉之後，**這是唯一的平移路徑**。
	#   先放大（fit 倍率下平移恆被夾成 0，量不到東西）。
	_on_zoom(ZOOM_STEP * ZOOM_STEP)
	var pan_before := _pan
	# 中鍵拖曳＝「移動」模式鈕拿掉之後唯一的平移路徑（B1.3.1），所以它得有自檢。
	_drag_px(Vector2(600, 400), Vector2(540, 360), MOUSE_BUTTON_MIDDLE)
	for _i in 3:
		await get_tree().process_frame
	var panned: bool = _pan != pan_before
	_on_zoom_reset()

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
	# 圖鑑與能量是兩顆各自獨立的開關 → 玩家可以同時開。所以「不互相蓋掉」
	# 和優先權面板一樣是斷言，不是希望（B1.6.2 的截圖上抓到它們疊在一起）。
	var codex_ok: bool = (
		_codex_panel.visible and _codex_label.text.contains("熔爐")
		and _codex_panel.position.x + _codex_panel.size.x <= _energy_panel.position.x
	)
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

	# ★ 局內選單（B1.4.1）。會壞的地方有四個，每一個都只有真的送出事件才驗得到：
	#   ESC 到不到得了、遮罩擋不擋得住地圖、設定回不回得到選單、
	#   以及**左上角那顆鈕是不是同一件事**（P3：不能只有鍵盤那條路）。
	_press(_build_buttons["relay"])
	var free_cell := Vector2i(20, 12)
	_escape()
	for _i in 3:
		await get_tree().process_frame
	var menu_open: bool = _menu_layer != null and _menu_buttons.size() == 4
	var nodes_before: int = s.nodes.size()
	_click(free_cell)
	for _i in 3:
		await get_tree().process_frame
	var menu_blocks: bool = s.nodes.size() == nodes_before

	_press(_menu_buttons[2])          # 設定
	for _i in 3:
		await get_tree().process_frame
	var settings_open: bool = _settings_layer != null
	_escape()                          # 設定的 ESC ＝ 回選單，**不是**回戰場
	for _i in 3:
		await get_tree().process_frame
	var settings_back: bool = _settings_layer == null and _menu_layer != null
	_escape()
	for _i in 3:
		await get_tree().process_frame
	var menu_closed: bool = _menu_layer == null
	# 同一格在選單關掉之後蓋得起來 → 上面那個「蓋不起來」才證明得了是遮罩擋的，
	# 而不是那一格本來就不能蓋。
	_click(free_cell)
	for _i in 3:
		await get_tree().process_frame
	var buildable_after: bool = s.nodes.size() == nodes_before + 1
	_press(_menu_button)
	for _i in 3:
		await get_tree().process_frame
	var menu_by_button: bool = _menu_layer != null
	# 選單面板整個要留在畫面內。`CenterContainer` 幾乎不會出錯，但科技樹那張
	# 掉出畫面的卡片與設定畫面溢出的最後一行都是「`_draw()` 一個字都不會說」
	# 的同一類缺陷——量一次比相信便宜。
	var panel: Control = _menu_buttons[0].get_parent().get_parent() as Control
	var menu_fits: bool = (
		panel.global_position.y >= 0.0
		and panel.global_position.y + panel.size.y <= float(size.y)
	)
	_close_menu()

	# ★ 音訊（B1.5）。四件事，全部只有真的跑起來才問得到：
	#   ① 兩層 BGM **都在播**（perc 靜音待命）——這是「無縫切層」的實作前提。
	#      等到要打了才 `play()` 那一層，接進去的會是曲子的中間。
	#   ② 準備期時戰鬥層是 0（`_audio_tick()` 每幀從 `phase` 推目標）。
	#   ③ ★ **一進入波次，戰鬥層真的開始爬。** 第一版的自檢直接呼叫
	#      `combat_layer(true)`，結果下一幀就被 `_audio_tick()` 從 `phase` 蓋回 0——
	#      量到的是自己的呼叫，不是遊戲真正的那條路。改成推 `phase`。
	#   ④ 播一個音效之後真的有聲道在響（檔案讀得到、`play()` 有生效）。
	#      ⚠ 有鉤子時是**匯流排靜音**，不是不播，所以這些狀態問得到。
	var music_ok: bool = AudioBus.music_playing("base") and AudioBus.music_playing("perc")
	var layer_prep: bool = AudioBus.layer_level() <= 0.0
	var phase_before: String = s.phase
	s.phase = "wave"
	for _i in 8:
		await get_tree().process_frame
	var layer_rising: bool = AudioBus.layer_level() > 0.0
	s.phase = phase_before
	AudioBus.play("build_place")
	await get_tree().process_frame
	var voice_ok: bool = false
	for child: Node in AudioBus.get_children():
		var pl := child as AudioStreamPlayer
		if pl != null and pl.playing:
			voice_ok = true
	var audio_ok: bool = music_ok and layer_prep and layer_rising and voice_ok and AudioBus.muted

	# ★ **局結束之後不得有東西還在動**（使用者回報：「音效還在，他們也還在射擊」）。
	#   根因是 `step()` 在 won/lost 直接 return → 開火線的 `ttl` 不再遞減 →
	#   拿 `ttl` 當「剛剛才開火」的判定就每一幀都成立。這裡塞一條假的開火線，
	#   讓局結束，然後量兩件事：線有沒有被收掉、還會不會繼續發出聲音。
	# ⚠ 開火線的起點**必須是一座真的塔**，否則 `fire_<type>` 找不到檔案、
	#   `play()` 直接 return，這一段就變成一個永遠會過的空測試。
	_press(_build_buttons["anchor"])
	var tower_cell := Vector2i(22, 12)
	_click(tower_cell)
	for _i in 3:
		await get_tree().process_frame
	var tower_built: bool = String(s.node_at(tower_cell).get("type", "")) == "anchor"

	# ★ 潮鳴的場（B1.8）。要守的回歸是「**繪圖層真的去讀了光環**」——
	#   `Combat.auras()` 的數學已經有 `combat_test` 守著（滿電／半電／不疊加），
	#   這裡缺的那一環是 `_draw()` 有沒有把它算進 `_auras`。少了那一行，
	#   潮鳴就會安靜地退回 B1.7 之前「每秒吃 9 電、畫面上零回饋」的樣子，
	#   而 `_draw()` 對此一個字都不會說（B0.7.2 那個 size (0,0) 的同一類缺陷）。
	_press(_build_buttons["knell"])
	_click(Vector2i(20, 8))              # 離路徑 (20,4) 四格 → 在 5 格射程內
	for _i in 3:
		await get_tree().process_frame
	var knell: Dictionary = s.node_at(Vector2i(20, 8))
	s.add_enemy("drifter")
	(s.enemies[0] as Dictionary)["progress"] = 20.0   # 路徑上的 (20,4)
	for _i in 3:
		await get_tree().process_frame
	var field_ok: bool = (
		not knell.is_empty()
		and _auras.size() == s.enemies.size()         # 繪圖層每幀算了它
		and _engaged.get(int(knell["id"]), false)     # 而且潮鳴確實在交戰
	)
	s.enemies.clear()
	for _i in 2:
		await get_tree().process_frame

	s.phase = "won"
	for _i in 4:
		await get_tree().process_frame
	# ① 局末面板出現的那一刻，凍住的開火線與碎片要被收乾淨。
	var over_cleared: bool = s.shots.is_empty() and _over_panel != null
	# ② 面板已經在了（`_refresh_over` 之後不會再清一次），這時再塞一條滿 `ttl` 的
	#    開火線——**舊版會每一幀重播一次它的開火音**，新版因為 tick 沒有前進而不播。
	s.shots.append({
		"from": tower_cell, "to": Vector2i(22, 4), "ttl": BattleController.SHOT_TTL,
	})
	var plays_before: int = AudioBus.plays
	for _i in 12:
		await get_tree().process_frame
	var over_silent: bool = AudioBus.plays == plays_before
	s.shots.clear()
	s.phase = phase_before
	for _i in 3:
		await get_tree().process_frame

	# ③ ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」，所以
	#    **輸掉的那一面板上一定要有那一句**，而且整張面板要留在畫面內
	#    （多一行會換行的字，正是最容易把面板推出下緣的東西）。
	_diag["wave_ticks"] = 600
	_diag["starved"] = 300
	_diag["leak_wave"] = 3
	s.phase = "lost"
	for _i in 4:
		await get_tree().process_frame
	var why_shown := false
	if _over_panel != null:
		for n: Node in _over_panel.find_children("*", "Label", true, false):
			if (n as Label).text.begins_with("為什麼輸"):
				why_shown = true
	var why_fits: bool = (
		_over_panel != null
		and _over_panel.position.y + _over_panel.size.y <= float(size.y)
	)
	s.phase = phase_before
	for _i in 3:
		await get_tree().process_frame
	var over_ok: bool = (
		tower_built and over_cleared and over_silent and why_shown and why_fits
		and field_ok
	)

	# ★ 最後才留一個懸而未決的拖曳起點（按下不放開），讓八條方向導引與
	#   「連不成」的橙色預覽線入鏡——**這是玩家真的會看到的那一幀**（手指還沒鬆開）。
	#   一定要放在所有斷言之後：懸著的起點會讓下一次點擊被當成拖曳的終點。
	_press_at(_to_screen(_center(from)), true)
	_hover = from + Vector2i(4, 3)     # 橫 4 直 3：正好不是 45°
	_refresh_hint()

	var menu_ok: bool = (
		menu_open and menu_blocks and settings_open and settings_back and menu_closed
		and buildable_after and menu_by_button and menu_fits
	)
	var ok: bool = (
		placed and rejected and diag_placed and wired and upgraded and dragged and panned
		and reachable and alloy_gated and energy_ok and codex_ok and prio_ok
		and view_ok and menu_ok and audio_ok and over_ok
	)
	print("[TL_CLICKTEST] place=%s reject_path=%s diag_node=%s diag_conduit=%s diag_upgrade=%s drag_wire=%s mid_pan=%s last_btn=%s alloy_gate=%s energy=%s codex=%s prio=%s view=%s menu=%s audio=%s over=%s → %s" % [
		placed, rejected, diag_placed, wired, upgraded, dragged, panned, reachable, alloy_gated,
		energy_ok, codex_ok, prio_ok, view_ok, menu_ok, audio_ok, over_ok,
		"PASS" if ok else "FAIL"
	])
	print("[TL_CLICKTEST/audio] two_layers=%s prep_silent=%s wave_fade_in=%s voice=%s muted=%s tower=%s over_cleared=%s over_silent=%s why=%s why_fits=%s knell_field=%s" % [
		music_ok, layer_prep, layer_rising, voice_ok, AudioBus.muted, tower_built, over_cleared,
		over_silent, why_shown, why_fits, field_ok
	])
	print("[TL_CLICKTEST/menu] esc_open=%s scrim_blocks=%s settings=%s settings_back=%s esc_close=%s cell_buildable=%s button=%s fits=%s" % [
		menu_open, menu_blocks, settings_open, settings_back, menu_closed, buildable_after,
		menu_by_button, menu_fits
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
	# ★ **以框架正中放大時，畫面中心不能跑掉**（B1.3.1）。舊版按一次「＋」就把
	#   地圖甩到左上角、pan 當場撞上夾限再也拖不動，而當時的斷言全是綠的——
	#   「倍率有變大」與「pan 夾得住」都成立，錯的是「往哪邊放大」。
	var centered: bool = _pan.is_equal_approx(Vector2.ZERO)
	# ★ 以滑鼠位置放大時，游標底下那一格必須還是同一格。
	_on_zoom_reset()
	var probe := Vector2(500.0, 300.0)
	var probe_cell := _cell_at(probe)
	_zoom_by(ZOOM_STEP, probe)
	var anchored: bool = _cell_at(probe) == probe_cell
	_on_zoom_reset()
	_on_zoom(ZOOM_STEP)
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

	print("[TL_CLICKTEST/view] fit=%s fills=%s inside=%s bar_clear=%s zoom_in=%s centered=%s anchored=%s pan_clamp=%s reset=%s floor=%s hit_after_zoom=%s　（fit=%.3f，格 %.1f px）" % [
		at_fit, filled, inside, bar_clear, zoomed_in, centered, anchored, pan_clamped,
		reset_ok, floor_ok, hit_ok, _fit, Shapes.GRID * _fit
	])
	return (
		at_fit and filled and inside and bar_clear and zoomed_in and centered and anchored
		and pan_clamped and reset_ok and floor_ok and hit_ok
	)


func _press(b: Button) -> void:
	b.button_pressed = true
	b.pressed.emit()


## 合成一次 ESC。走 `Input.parse_input_event()` 的完整輸入管線，才驗得到
## 「`ui_cancel` 這個 action 真的對得上 ESC 鍵」與「事件真的傳到 `_unhandled_key_input`」
## ——直接呼叫 `_toggle_menu()` 兩件都驗不到。
func _escape() -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)


## GUI 的滑鼠路由要先有「游標在這裡」才認得出按下的是誰，所以**先送一個移動事件**。
## 走 `Input.parse_input_event()`（完整輸入管線）而不是 `Viewport.push_input()`：
## 後者繞過了一部分 GUI 狀態的建立，測不到真實玩家會走的那條路。
## ★ `_center()` 回的是**地圖座標**，合成滑鼠事件要的是**螢幕座標**——
## 中間差的就是縮放與平移那個變換（B1.2.2）。少了 `_to_screen()`，
## 這支自檢會點到旁邊那一格去，而畫面上一切看起來都正常。
func _click(cell: Vector2i) -> void:
	_click_at(_to_screen(_center(cell)))


## 合成一次拖曳：在 `a` 按下、移動到 `b`、在 `b` 放開。
func _drag(a: Vector2i, b: Vector2i) -> void:
	_drag_px(_to_screen(_center(a)), _to_screen(_center(b)), MOUSE_BUTTON_LEFT)


## 像素座標的拖曳。按下 → 移動（鍵壓著）→ 放開。
func _drag_px(a: Vector2, b: Vector2, button: int) -> void:
	Input.use_accumulated_input = false
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	_press_at(a, true, button)
	# 移動到終點時鍵是壓著的——`button_mask` 少了這一位，平移那條分支就進不去。
	var mm := InputEventMouseMotion.new()
	mm.position = b
	mm.global_position = b
	mm.relative = b - a
	mm.button_mask = mask
	Input.parse_input_event(mm)
	_press_at(b, false, button)


## 一顆按鍵事件（前面附一次移動，GUI 的滑鼠路由要先知道游標在哪）。
## `pressed=true` 而不送對應的放開，就是「手指還沒鬆開」那一幀。
func _press_at(at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	Input.use_accumulated_input = false
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = mask if pressed else 0
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


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


## 合成一次滑鼠移動（不按鍵）。驗拖曳用——`_click_at()` 按下即放開，
## 用它驗不到「按住不放的時候會怎樣」。
func _move_at(at: Vector2) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)


func _process(delta: float) -> void:
	# ★ 視野緩動（B2.1d）。指數收斂與幀率無關——`1-exp(-k*dt)` 在 30fps 與
	#   144fps 下走完同一段路，`lerp(_, k*dt)` 不會。這只動**畫面**，
	#   不碰模擬：`_pan` 不進 `state_hash()`，也不影響任何 tick。
	if not _pan.is_equal_approx(_pan_goal):
		_pan = _pan.lerp(_pan_goal, 1.0 - exp(-PAN_EASE * delta))
		if _pan.distance_to(_pan_goal) < 0.5:
			_pan = _pan_goal
		queue_redraw()

	# ★ `TL_SHOT` 下模擬凍結在 `_demo_layout()` 推完的那一格。否則截圖落在第幾
	# tick 取決於這台機器 3 秒內跑了幾幀——同一份佈局在不同機器上會拍出不同
	# 數字，截圖就不能拿來做回歸比對，也對不上 `TL_SIM=<同一個 N>` 的輸出。
	if Hooks.stress:
		_stress_frame(delta)
	if Hooks.shot_path == "" and not Hooks.stress:
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
	# ★ 一個 tick 邊緣偵測，兩個消費者（音訊、死因診斷）。
	#   兩邊各記一份「上一幀的 tick」的那一天，就會有一邊記錯（B1.5.1 的教訓）。
	var advanced: bool = s.tick_count != _last_tick
	_last_tick = s.tick_count
	_audio_tick(advanced)
	if advanced:
		_diag_tick()
	queue_redraw()


## ★ 死因歸因的原始資料（B1.7）。
##
## M1 的驗收句子是「**陌生人可以說得出自己為什麼輸**」。局末面板原本只給
## 「撐過幾波、產能積分多少」——那些是**成績**，不是**原因**。玩家輸掉的時候
## 要的是下一句「所以我下次該改什麼」。
##
## 全部從畫面層累計，模擬層一個欄位都不動（`scripts/sim/` 零副作用）。
func _diag_tick() -> void:
	if s.phase != "wave":
		return
	_diag["wave_ticks"] = int(_diag["wave_ticks"]) + 1
	if float(s.rates["power_demand"]) > float(s.rates["power_supply"]) + 0.01:
		_diag["starved"] = int(_diag["starved"]) + 1
	# 核心開始掉血的那一波 ＝ 第一次有敵人走到底。
	if int(_diag["leak_wave"]) < 0 and s.core_hp() < float(_diag["core_hp"]) - 0.01:
		_diag["leak_wave"] = s.wave_index
	_diag["core_hp"] = s.core_hp()


## 一句話的死因。**只給一句**：三條並列的診斷等於沒有診斷。
func _diag_line(won: bool) -> String:
	var ticks: int = maxi(1, int(_diag["wave_ticks"]))
	var starve := float(_diag["starved"]) / float(ticks)
	var leak: int = int(_diag["leak_wave"])
	if not won:
		if leak >= 0:
			return "為什麼輸　第 %d 波開始有敵人走到核心。%s" % [
				leak,
				"缺電讓塔的射速掉了（%d%% 的戰鬥時間供不應求）——先補發電機或儲槽。" % roundi(starve * 100.0)
				if starve >= 0.25 else "那條路線上的火力不夠——把塔往敵人的必經之路挪，或多蓋一座。",
			]
		return "為什麼輸　核心被相鄰的敵人啃掉了。節點退開敵人路徑 2 格就打不到。"
	if starve >= 0.25:
		return "下一次　有 %d%% 的戰鬥時間供不應求，塔是降速在打的——補電力就能拉高產能積分。" % roundi(starve * 100.0)
	return ""


# ── 音訊（B1.5）────────────────────────────────────────────────────────


## ★ 渲染壓力量測（`TL_STRESS=1`，B1.7）。
##
## **模擬是凍結的**，所以這裡量到的是純粹的「畫 547 個節點 ＋ 2045 條導管 ＋
## 200 隻敵人要多久」。前 30 幀丟掉（著色器編譯與第一次配置都落在那裡），
## 之後取平均與最壞值——**最壞值才是玩家感覺得到的那一下卡頓**。
func _stress_frame(delta: float) -> void:
	_stress_frames += 1
	if _stress_frames <= STRESS_WARMUP:
		return
	_stress_total += delta
	_stress_worst = maxf(_stress_worst, delta)
	var n := _stress_frames - STRESS_WARMUP
	if n < STRESS_FRAMES:
		return
	var avg := _stress_total / float(n)
	print("[TL_STRESS] 節點 %d／導管 %d／敵人 %d　→　平均 %.2f ms（%.0f FPS）／最壞 %.2f ms　量了 %d 幀" % [
		s.nodes.size(), s.conduits.size(), s.enemies.size(),
		avg * 1000.0, 1.0 / maxf(avg, 0.000001), _stress_worst * 1000.0, n
	])
	# 60 FPS ＝ 16.7ms；45 FPS（§5 的最低可接受）＝ 22.2ms。
	print("[TL_STRESS] 60FPS 目標 16.67ms／45FPS 底線 22.22ms → %s" % (
		"通過（60FPS）" if avg <= 0.01667
		else ("勉強（45FPS 以上）" if avg <= 0.02222 else "不通過")
	))
	get_tree().quit(0)


func _audio_reset() -> void:
	_audio_prev = {
		"kills": s.kills, "nodes": s.nodes.size(), "core": s.core_hp(),
		"warn_at": -99.0, "core_at": -99.0,
	}
	_last_tick = s.tick_count
	_diag = {"wave_ticks": 0, "starved": 0, "leak_wave": -1, "core_hp": s.core_hp()}


## 這一幀發生了什麼？全部從狀態的差值推出來——**不在模擬層留任何一個
## 「順便播個音」的呼叫**。代價是要自己記上一幀，換到的是 `sim/` 仍然
## 可以在 headless 重播一萬次而不出聲。
func _audio_tick(advanced: bool) -> void:
	if _audio_prev.is_empty():
		return
	var over: bool = s.phase == "won" or s.phase == "lost"
	AudioBus.combat_layer(s.phase == "wave")
	# 局結束就停掉生產的循環音。它是「東西正在跑」的聲音，而東西已經不跑了。
	AudioBus.flow(0.0 if over else clampf(float(s.rates["ore_in"]) / 30.0, 0.0, 1.0))

	# ★★ **一次性音效只在模擬真的往前走了一格時才判定。**
	#
	# 少了這一條會出兩件事，而且兩件都出過：
	#   ① 畫面 60fps、tick 10Hz → 同一發開火線會被連續 6 幀看到「ttl 還是滿的」，
	#      於是一發子彈播六次音。
	#   ② **局結束後 `BattleController.step()` 直接 return，`ttl` 從此不再遞減**
	#      → 最後那一 tick 的開火線永遠停在「剛剛才生出來」的狀態，
	#      音效就每一幀重放一次，聽起來像卡住了（使用者回報）。
	#
	# 用「差值偵測」的東西，就要確定自己是在**變化的那一刻**被呼叫的。
	if not advanced:
		return
	var now := float(s.tick_count) * BattleController.TICK

	# 開火：`ttl` 還是滿的就是這一 tick 才生出來的那幾發。
	# **一種塔一幀只出一個音**——五座錨同時開火時要聽到「一發」，
	# 不是五個同相位的正弦疊起來爆掉。
	var fired: Dictionary = {}
	for sh: Dictionary in s.shots:
		if int(sh["ttl"]) != BattleController.SHOT_TTL:
			continue
		var n: Dictionary = s.node_at(sh["from"])
		if not n.is_empty():
			fired[String(n["type"])] = true
	for type: String in fired:
		AudioBus.play("fire_%s" % type, -4.0)

	if s.kills > int(_audio_prev["kills"]):
		AudioBus.play("enemy_hit")
	# 節點變少＝被啃掉或被玩家拆掉。兩件事共用一個音是刻意的：
	# 玩家自己拆的那一次他知道自己在做什麼，不需要另一個音來告訴他。
	if s.nodes.size() < int(_audio_prev["nodes"]):
		AudioBus.play("build_destroyed", -2.0)
	# ★ 核心受擊與能量不足都要**節流**。核心每 tick 都在掉血，照實播就是
	#   每秒十次 0.9 秒的爆炸；警報響個不停等於沒有警報。
	if s.core_hp() < float(_audio_prev["core"]) - 0.01 and now - float(_audio_prev["core_at"]) >= 0.8:
		AudioBus.play("core_hit")
		_audio_prev["core_at"] = now
	var short: bool = float(s.rates["power_demand"]) > float(s.rates["power_supply"]) + 0.01
	if short and s.phase == "wave" and now - float(_audio_prev["warn_at"]) >= 4.0:
		AudioBus.play("warn_power", -5.0)
		_audio_prev["warn_at"] = now

	_audio_prev["kills"] = s.kills
	_audio_prev["nodes"] = s.nodes.size()
	_audio_prev["core"] = s.core_hp()


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
		# ★ 平移：**按住滑鼠中鍵拖**（B1.3.1，使用者指定）。
		#   ⚠ 手機移植預留條款 P3：觸控沒有中鍵，移植時要補一個雙指拖曳手勢
		#   （已登記在 `40_PRODUCTION_PLAN.md` 的風險表）。放大只由底欄的
		#   ＋／−／全景三顆鈕與滾輪進入，而 fit 倍率下平移恆被夾成 0，
		#   所以在桌面版之外「完全平移不了」不會發生。
		#
		#   判斷用**自己記的 `_panning`，不讀 `mm.button_mask`**：那個位元是
		#   Input 單例從實體滑鼠狀態填的，合成事件填進去的值不保證留得住——
		#   驗不到的輸入路徑就是遲早會壞掉的輸入路徑（B0.7.2 的教訓）。
		if _panning:
			_pan_to(_pan + mm.relative, true)
			queue_redraw()
			return
		# ★ 小地圖按住拖曳（B2.1d，使用者指定）：按住不放，視野持續跟著游標走。
		#   走 `_pan_goal` → 畫面是**平滑**追過去的，不是一格一格跳。
		if _mini_drag:
			_mini_seek(mm.position)
			return
		var c := _cell_at(mm.position)
		if c != _hover:
			_hover = c
			_refresh_hint()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = mb.pressed
		return
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT and _mini_drag:
			# 小地圖上放開：**不可以掉進 `_release()`**，否則等於在小地圖
			# 底下那一格結束一次拉線。
			_mini_drag = false
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_release(mb.position)
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
	# ★ 導引要先問（B2.1b）。小地圖蓋在地圖上面，不先攔的話點它會**在它底下
	#   那一格蓋出東西來**——而且玩家看不出為什麼，因為節點生在畫面外。
	if _guide_click(mb.position):
		return
	# ★ 從節點上按下先不動作，等放開才決定（B1.6.2）：放開在同一格＝一次普通點擊，
	#   放開在另一個節點上＝拉一條導管。這樣「蓋一個 → 接一條 → 蓋一個 → 接一條」
	#   不用每一步都往返左欄切模式——第 1 關的參考解就是 6 蓋 6 接交替，
	#   舊路徑要切 10 次模式，而那 10 次沒有任何一次是決策。
	var c := _cell_at(mb.position)
	if _mode == Mode.BUILD and not s.node_at(c).is_empty():
		_drag_from = c
		queue_redraw()
		_refresh_hint()
		return
	_act(c, _point_at(mb.position))
	_refresh_hint()


## 左鍵放開。只有「按下時停在某個節點上」的那條路徑會走到這裡。
func _release(pos: Vector2) -> void:
	if _drag_from.x < 0:
		return
	var from := _drag_from
	_drag_from = Vector2i(-1, -1)
	var to := _cell_at(pos)
	if to != from and not s.node_at(to).is_empty():
		var code := BuildController.lay_conduit(s, from, to)
		if code == Build.OK:
			AudioBus.play("build_wire")
		_message = _text_of(code)
	else:
		# 在既有節點上點一下就放開。**不要回「這一格已經有東西了」**——
		# 那句話對玩家沒有下一步；這裡正是教會拖曳這個手勢最好的時機。
		_message = "從這個節點按住往另一個節點拖，就能拉一條導管。"
	_refresh_hint()
	queue_redraw()


## `point` 是**格為單位的浮點座標**（整數＝格中心）。加粗與拆除要用它才點得準：
## 好幾條線擠在同一個節點上時，格解析度分不出玩家指的是哪一條（B1.2.1）。
## 省略時退回格中心，`_click()` 那條合成輸入的路徑走這個預設。
func _act(cell: Vector2i, point: Vector2 = Vector2(-999, -999)) -> void:
	var p := Vector2(cell) if point.x < -900.0 else point
	# 音效只在**真的做成了**的時候響（`Build.OK` ＝ 空字串）。失敗有提示列說原因，
	# 再配一個音只是把「你做錯了」講兩次。
	# ⚠ `match` 的各分支共享作用域，變數名不能重複（`CLAUDE.md` 嚴格型別地雷）。
	match _mode:
		Mode.BUILD:
			var code_b := BuildController.place(s, _build_type, cell)
			if code_b == Build.OK:
				AudioBus.play("build_place")
			_message = _text_of(code_b)
		Mode.UPGRADE:
			var ci: int = s.conduit_near(p)
			if ci < 0:
				_message = "加粗模式：請點一段導管（不是節點）"
			else:
				var code_u := BuildController.upgrade(s, ci)
				if code_u == Build.OK:
					AudioBus.play("build_wire")
				_message = _text_of(code_u)
		Mode.DEMOLISH:
			var before_d: int = s.nodes.size()
			var code_d := BuildController.demolish(s, cell, p)
			# 拆**節點**的音由 `_audio_tick()` 的「節點變少」那條負責（敵人啃掉的
			# 走同一條）。這裡只補拆導管——導管不算在節點數裡，那條看不到。
			if code_d == Build.OK and s.nodes.size() == before_d:
				AudioBus.play("build_destroyed", -4.0)
			_message = _text_of(code_d)


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

	# 敵人的格算一次給三個人用（交戰、光環、被啃判定）——同一幀各算一次的那一天，
	# 就會有一個用到的是上一幀的位置。
	var cells := Combat.enemy_cells(s.enemies, s.path)
	_engaged = Combat.engaged(s.nodes, cells)
	_auras = Combat.auras(s.nodes, cells, s.rates["satisfaction"])
	_threat = _threat_cells(cells)
	_draw_path()
	_draw_ore_cells()
	_draw_fields()
	_draw_conduits()
	_draw_nodes()
	_draw_enemies()
	_draw_shots()
	_draw_bursts()
	_draw_shields()
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
	# 導引畫在遮罩**之後**：它們的職責就是講「框架外面有什麼」，被遮罩蓋掉
	# 等於整個功能不存在。兩者都只在 `_oversized()` 時出現。
	_draw_arrows()
	_draw_minimap()
	_draw_energy_bar()


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
		if _threat.has(c):
			hurt.append(c)
		elif int(state.get(int(n["id"]), SessionState.NORMAL)) != SessionState.NORMAL:
			stuck.append(c)
	hurt.append_array(stuck)
	return hurt


## 目前看得到的世界座標矩形。小地圖的視野框與「這個問題在不在畫面內」
## 都從這裡算——**只有一份**，兩者不可能各算各的而對不起來。
func _view_world_rect() -> Rect2:
	var o := _map_origin()
	return Rect2((FRAME.position - o) / _zoom, FRAME.size / _zoom)


## 把某一格移到畫面中央（小地圖與箭頭的「一鍵跳」）。
## 與 `TL_FOCUS` 走同一條算式——兩份會漂掉。
func _center_view_on(c: Vector2i, immediate: bool = false) -> void:
	var px := Vector2(s.map["size"]) * Shapes.GRID
	_pan_to((px * 0.5 - _center(c)) * _zoom, immediate)


## 小地圖的位置：框架**右下角**內側——離建造欄（左）與能量列（上）最遠的角。
## 尺寸依地圖長寬比縮進 `MINIMAP_MAX`，所以它永遠和地圖同比例（不同比例的
## 縮圖上，「我在哪」那個框會說謊）。
func _minimap_rect() -> Rect2:
	var m := Vector2(s.map["size"])
	var k := minf(MINIMAP_MAX.x / m.x, MINIMAP_MAX.y / m.y)
	var sz := m * k
	return Rect2(FRAME.end - sz - Vector2(MINIMAP_PAD, MINIMAP_PAD), sz)


func _draw_minimap() -> void:
	if not _oversized():
		return
	var r := _minimap_rect()
	# ★ 底板往外長，**外框畫在 `r` 上**（B2.1d）。舊版把框也畫在 `box` 上，
	#   於是推到底時視野框離可見的邊還有 5px ——使用者回報「小地圖滑到底
	#   不會貼邊」。框就是地圖的邊界，底板只是讓它在遊戲畫面上讀得出來。
	draw_rect(r.grow(5.0), Palette.alpha(Palette.BG_PANEL, 0.96))
	draw_rect(r, Palette.BORDER_STRONG, false, 1.0)
	# 世界座標 → 小地圖座標。
	var k := r.size.x / (float(s.map["size"].x) * Shapes.GRID)
	var cell := maxf(1.0, Shapes.GRID * k)

	for c: Vector2i in s.path:
		draw_rect(Rect2(r.position + Vector2(c) * cell, Vector2(cell, cell)), Palette.TIDE_DEEP)
	# 玩家節點：小地圖上讀的是**產線的形狀**，不是個別節點，所以一律同一個點。
	for n: Dictionary in s.nodes:
		draw_rect(
			Rect2(r.position + Vector2(n["cell"]) * cell, Vector2(cell, cell)),
			Palette.ORDER_CYAN
		)
	# 問題標記：**比節點大一倍** ＋ 脈動。要在一堆青點裡被一眼挑出來，
	# 只換顏色不夠（§4.3b）。
	var a := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.45)
	for c: Vector2i in _problem_cells():
		var at := r.position + Vector2(c) * cell - Vector2(cell, cell) * 0.5
		draw_rect(Rect2(at, Vector2(cell, cell) * 2.0), Palette.alpha(Palette.WARN_ORANGE, a))
	# 視野框：「我在哪」——這是小地圖與一張縮圖的唯一差別。
	var vw := _view_world_rect()
	draw_rect(
		Rect2(r.position + vw.position * k, vw.size * k).intersection(r),
		Palette.ORDER_BRIGHT, false, 1.0
	)


## 邊緣箭頭：畫在框架內緣，指向畫面外的問題。
##
## 只畫**不在畫面內**的——在畫面內的問題本來就看得到，再加一個箭頭是雜訊。
func _draw_arrows() -> void:
	if not _oversized():
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
	var vw := _view_world_rect()
	var mid := FRAME.position + FRAME.size * 0.5
	# 框架內緣，留出箭頭自己的半徑，否則尖端會被邊緣切掉。
	var inner := FRAME.grow(-(ARROW_SIZE + 6.0))
	for c: Vector2i in _problem_cells():
		if out.size() >= ARROW_MAX:
			break
		var w := _center(c)
		if vw.has_point(w):
			continue
		var dir := (_to_screen(w) - mid)
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
func _guide_click(pos: Vector2) -> bool:
	if not _oversized():
		return false
	for hit: Array in _arrow_hits():
		if pos.distance_to(hit[0] as Vector2) <= ARROW_HIT:
			_center_view_on(hit[2] as Vector2i)
			return true
	if not _minimap_rect().grow(5.0).has_point(pos):
		return false
	# 按下就開始拖曳；放開才結束（見 `_gui_input`）。單擊仍然等於「跳一次」，
	# 因為按下的當下就已經 seek 過一次了。
	_mini_drag = true
	_mini_seek(pos)
	return true


## 把小地圖上的一點換算成地圖格，並把視野**平滑**移過去。
func _mini_seek(pos: Vector2) -> void:
	var r := _minimap_rect()
	var k := r.size.x / (float(s.map["size"].x) * Shapes.GRID)
	_center_view_on(Shapes.to_grid((pos - r.position) / k))


## ★ 大圖導引自檢（`TL_CLICKTEST=1 TL_PANEL=endless`，B2.1b）。
##
## 這一支驗的就是 B2.1b 的 DoD：**瓶頸節點即使不在畫面內也能在 30 秒內被找到**。
## 「30 秒」對自檢沒有意義，能驗的是它的前提——**問題在畫面外時，畫面上真的
## 有一個指得到它、而且點得到的東西**。
##
## 造問題的方式：在畫面外的礦點上蓋一座採集器、不接任何導管。它的產出推不
## 出去 → `stuck` → `滿溢`（和三態徽章同一份判定），一個節點就成立，不必
## 佈一整條產線。
func _guide_selftest() -> void:
	var big: bool = _oversized()

	# 找一個**開場看不到**的礦點——大圖的重點就是「畫面外」。
	var vw := _view_world_rect()
	var target := Vector2i(-1, -1)
	for c: Vector2i in (s.map["ore"] as Array):
		if not vw.has_point(_center(c)):
			target = c
			break
	var found_offscreen: bool = target.x >= 0

	if found_offscreen:
		# ★ **先把視野移過去才蓋得到**：那一格在畫面外，合成點擊落在框架外
		#   會被輸入層擋掉（第一版就是這樣紅的——而那個行為是對的，玩家也
		#   點不到看不見的格子）。蓋完再 `_reset_view()` 把它送回畫面外。
		_center_view_on(target, true)
		for _i in 2:
			await get_tree().process_frame
		_press(_build_buttons["extractor"])
		_click(target)
		for _i in 3:
			await get_tree().process_frame
		# 推幾個 tick，`node_state` 才算得出 `滿溢`。
		for _i in 6:
			BattleController.step(s)
		_reset_view()
		for _i in 2:
			await get_tree().process_frame
	var placed: bool = not s.node_at(target).is_empty()
	var back_offscreen: bool = placed and not _view_world_rect().has_point(_center(target))
	var flagged: bool = _problem_cells().has(target)

	# 箭頭：它在畫面外，所以應該有一個指著它的箭頭。
	var arrows := _arrow_hits()
	var arrow_at := Vector2(-1, -1)
	for hit: Array in arrows:
		if (hit[2] as Vector2i) == target:
			arrow_at = hit[0]
	var arrowed: bool = arrow_at.x >= 0
	# 箭頭要**在框架內**，不然它自己就在畫面外（第一版就是這樣：內縮沒算箭頭
	# 自己的半徑，尖端被邊緣切掉一半）。
	var arrow_inside: bool = arrowed and FRAME.has_point(arrow_at)

	# 一鍵跳：點那個箭頭，目標要進到畫面內。
	var jumped := false
	if arrowed:
		_click_at(arrow_at)
		for _i in 2:
			await get_tree().process_frame
		# ★ 補間中途的 `_pan` 還沒到位——`_settle_view()` 把「動畫沒跑完」
		#   和「位置算錯」分開，否則這條斷言會變成在驗補間速度。
		_settle_view()
		jumped = _view_world_rect().has_point(_center(target))

	# ★ 推到底要真的貼到地圖的邊（RG-121）。使用者回報「小地圖滑到底不會貼邊」
	#   ——那是視野框與小地圖外框之間的內縮，肉眼在縮放過的截圖上判不準，
	#   所以這裡用數字驗：夾到底之後視野的世界矩形要對齊地圖的角。
	var msz := Vector2(s.map["size"]) * Shapes.GRID
	_pan_to(Vector2(99999.0, 99999.0), true)
	var tl := _view_world_rect().position
	_pan_to(Vector2(-99999.0, -99999.0), true)
	var br := _view_world_rect().end
	var flush: bool = (
		absf(tl.x) < 0.5 and absf(tl.y) < 0.5
		and absf(br.x - msz.x) < 0.5 and absf(br.y - msz.y) < 0.5
	)
	_reset_view()

	# 小地圖：點左上角，視野要往左上走（而且**不可以在那裡蓋出東西**）。
	#
	# ★ 先切成「中繼」再點：中繼哪裡都蓋得起來，所以 `mini_safe` 才是真斷言。
	#   用採集器的那一版是**假通過**——點到非礦點本來就會被擋，攔不攔截都一樣綠。
	_press(_build_buttons["relay"])
	var r := _minimap_rect()
	var pan_before := _pan
	# ★ 哨兵字串，不是「節點數沒變」。節點數那一版**紅不起來**：那一格剛好
	#   不能蓋，攔不攔截都是綠的（第一版的假斷言）。`_act()` 在 BUILD 模式下
	#   **一定**會覆寫 `_message`（成功是空字串、失敗是原因），所以哨兵還在
	#   ＝ 這次點擊根本沒走到建造層。
	_message = "＿哨兵＿"
	# ★ 點「離目前視野最遠的那個角」，不是固定點左上角。固定左上是**看種子
	#   臉色**的斷言：前一步的箭頭跳轉若剛好把視野帶到左上，`_pan` 已經夾在
	#   (0,0)，再點左上當然不會動——測試紅掉而產品沒問題（`TL_SEED=42` 實際
	#   踩到）。確定性的閘門不可以有「某些種子才過」這種行為。
	var msize := Vector2(s.map["size"]) * Shapes.GRID
	var vcen := _view_world_rect().get_center() / msize
	_click_at(r.position + Vector2(
		6.0 if vcen.x > 0.5 else r.size.x - 6.0,
		6.0 if vcen.y > 0.5 else r.size.y - 6.0
	))
	for _i in 2:
		await get_tree().process_frame
	var mini_moved: bool = _pan_goal != pan_before
	var mini_safe: bool = _message == "＿哨兵＿"

	# ★ 按住拖曳（B2.1d，使用者指定）：**按住不放時視野要持續跟著游標**。
	#   ⚠ `_click_at()` 是按下**即放開**，所以要自己按住——第一版直接接在
	#   上一次點擊後面送移動事件，`drag=false`，因為那時早就放開了。
	var opp := r.position + Vector2(
		r.size.x - 6.0 if vcen.x > 0.5 else 6.0,
		r.size.y - 6.0 if vcen.y > 0.5 else 6.0
	)
	_press_at(r.position + r.size * 0.5, true)
	for _i in 2:
		await get_tree().process_frame
	var drag_from := _pan_goal
	_move_at(opp)
	for _i in 2:
		await get_tree().process_frame
	var dragged: bool = _pan_goal != drag_from
	# 放開之後再移動就**不可以**再跟著跑，否則等於滑鼠一直黏著小地圖。
	_press_at(opp, false)
	var after_release := _pan_goal
	_move_at(r.position + r.size * 0.5)
	for _i in 2:
		await get_tree().process_frame
	var drag_stops: bool = _pan_goal == after_release
	# 平滑：目標已經到了，但 `_pan` 還在路上（補間真的存在，不是瞬移）。
	var smooth: bool = not _pan.is_equal_approx(_pan_goal)
	_settle_view()

	# 可讀性地板：大圖的縮放下限是 24px／格，不是 fit（RG-59）。
	var floor_ok: bool = Shapes.GRID * _fit >= Shapes.MIN_READABLE_CELL - 0.001

	# ★ 視野框佔小地圖的比例 ＝ 看得到的比例。**這一條用肉眼判不準**
	#   （小地圖只有 232px 寬，視野框和外框差幾個像素），所以用數字。
	#   兩軸都必須 < 1（真的有看不到的部分）也都必須 > 0.3（不然是算錯了，
	#   而算錯的症狀正是「小地圖上那個框說謊」）。
	var frac := _view_world_rect().size / msize
	var frac_ok: bool = (
		frac.x > 0.3 and frac.x < 1.0 and frac.y > 0.3 and frac.y < 1.0
	)

	var ok: bool = (
		big and found_offscreen and placed and back_offscreen and flagged and arrowed
		and arrow_inside and jumped and mini_moved and mini_safe and floor_ok and frac_ok
		and flush and dragged and drag_stops and smooth
	)
	print(
		"[TL_CLICKTEST/endless] big=%s offscreen=%s placed=%s back_off=%s flagged=%s arrow=%s"
		% [big, found_offscreen, placed, back_offscreen, flagged, arrowed]
		+ " inside=%s jump=%s mini_pan=%s mini_safe=%s floor=%s（%.1f px/格）"
		% [arrow_inside, jumped, mini_moved, mini_safe, floor_ok, Shapes.GRID * _fit]
		+ " flush=%s drag=%s drag_stop=%s smooth=%s view=%.0f%%×%.0f%% → %s"
		% [flush, dragged, drag_stops, smooth, frac.x * 100.0, frac.y * 100.0, "PASS" if ok else "FAIL"]
	)
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


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
func _draw_fields() -> void:
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		if not def.has("slow") or not _engaged.get(int(n["id"]), false):
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
		draw_arc(
			_center(n["cell"]), float(def.get("range", 0.0)) * Shapes.GRID, 0.0, TAU, 64,
			Palette.alpha(Palette.ORDER_CYAN, a), 2.0
		)


func _draw_conduits() -> void:
	var flows: Dictionary = s.rates["conduit_flow"]
	var sat: Dictionary = s.rates["satisfaction"]
	for c: Dictionary in s.conduits:
		var bonus := float(s.mods["cap_bonus"])
		var cap := Build.conduit_cap(int(c["level"]), bonus)
		var flow := float(flows.get(c["id"], 0.0))
		var to_node: Dictionary = s.node_at(c["b"])
		var starving := (
			not to_node.is_empty() and float(sat.get(to_node["id"], 1.0)) < 0.95 and flow > 0.0
		)
		# 線寬的分母是**全遊戲的最大 cap**，不是這條線自己的——粗細因此在
		# 全圖上可以互相比較，而且加粗一條線之後它會真的變粗（B1.1 使用者回報）。
		var w := Shapes.conduit_width(flow, Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus))
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
		# ★ B1.6.1：刻度必須**明確伸出管緣**。原本固定 ±5px，而滿載的管子
		#   本身就有 8px 寬——刻度只比它寬一點點，畫成近白青之後讀起來是
		#   「管子這裡破了一個洞」（使用者回報「有破圖」）。
		#   現在長度跟著線寬走並固定外露 3px，而且貼在起點端而不是線長 12%
		#   那個沒有意義的位置：等級是這條線的屬性，標在接頭上才讀得出來。
		var reach := w * 0.5 + 3.0
		var tick_w := maxf(1.5, 2.0 / maxf(0.2, _zoom))
		var step := maxf(3.0, 4.0 / maxf(0.2, _zoom))
		# 起點要**閃過節點自己的圖形**：節點最大到半徑 13（碎浪的外框），
		# 貼太近就被畫在它底下看不見（第一版貼 6px，截圖當場抓到）。
		# 短線上再夾一次，免得刻度跑過中點看起來像掛在另一端。
		var span := pa.distance_to(pb)
		var head := minf(17.0, span * 0.32)
		for i in range(int(c["level"])):
			var at := pa + (pb - pa).normalized() * (head + step * float(i))
			draw_line(at - perp * reach, at + perp * reach, Palette.ORDER_BRIGHT, tick_w)
		# ★ 流動珠：礦砂／能量／合金各一列，各自往自己的淨流向跑（§1.4a）。
		var net: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
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
		# 礦砂珠用 `text.primary`（近白）而不是 `order.bright`：導管本身就是亮青，
		# 亮青珠子在亮青線上只讀得出「這裡有個洞」，讀不出「有東西在跑」。
		# 能量珠的琥珀、合金珠的紫本來就與線色分屬不同色相，維持配色紀律 2。
		for i in lanes.size():
			_draw_beads(
				pa, pb, float(lanes[i][0]), lanes[i][1], w,
				float(i) / float(lanes.size())
			)


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
## `lane_phase` 是 0..1 的相位偏移：多種資源在同一條線上時用它錯開，
## 於是白、琥珀、紫依序前進而不是疊在一起（B1.6.1）。
func _draw_beads(
	a: Vector2, b: Vector2, amount: float, col: Color, width: float,
	lane_phase: float = 0.0
) -> void:
	if absf(amount) < BEAD_MIN_RATE:
		return  # 沒在流動的線必須是靜止的——這是「哪裡斷了」最快的讀法
	var span := a.distance_to(b)
	if span < 1.0:
		return
	var u := (b - a) / span
	# 相位用模擬秒數推（tick 數 ＋ 幀內插值），不用系統時間：
	# 渲染可以不確定，但別引入新的亂數源。`TL_SHOT` 下模擬凍結 → 珠子也凍結。
	var t := (float(s.tick_count) + _accum / BattleController.TICK) * BattleController.TICK
	# 珠子大小跟著線寬走：這樣它**強化**「線寬＝流量」而不是把線戳成虛線。
	# 固定大小的珠子在 2px 的細線上會蓋掉整條線，粗細那條資訊就沒了（R-3）。
	# ★ 上限收到半寬：珠子不得比管子胖，否則它就是「管子上的腫塊」。
	var r := clampf(width * 0.30, 1.4, width * 0.5)
	# ★ 描邊是**螢幕固定粗細**（B1.6.1）。原本是固定 +1.2 地圖 px：在 r=1.4 的
	#   細線上，光暈佔了直徑的 46%，讀起來是「管子上的洞」而不是「在跑的東西」；
	#   而放大到 300% 時它又變成一圈很粗的黑框。1px 螢幕在任何倍率下都只是描邊。
	var edge := 1.0 / maxf(0.2, _zoom)
	var x := fposmod(t * amount * BEAD_SPEED + lane_phase * BEAD_GAP, BEAD_GAP)
	while x < span:
		var p := a + u * x
		# **深色描邊是這個元素能被看見的唯一原因**：導管本身就是亮青，
		# 亮青珠子畫在亮青線上等於沒畫（使用者實看 B0.6 時反映的正是這件事）。
		draw_circle(p, r + edge, Palette.BG_DEEP)
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
		_draw_threat(n["cell"], p)
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


## 開火線。留 `SHOT_TTL` 個 tick 並隨之淡出——瞬間閃一下的線等於沒畫。
## ★ 四種開火形態（B1.6.3，`20_ART_DIRECTION.md` §1.7）。
##
## 起因是使用者實玩回報「塔的攻擊可以有更多不同的特效嗎」——查證屬實：
## 五座塔畫的是**同一條 `order.bright` 直線**，濺射半徑玩家完全看不到。
##
## **形態由 `NodeDefs` 既有的機制欄位推導，不新增美術欄位**：所以做不出一座
## 「會濺射但看起來不濺射」的塔，M3 擴到 24 隻角色時也自動正確。
##
## **物理 vs 能量用形狀分，不用顏色分**：琥珀專屬於能量這個**資源**（§1.1
## 配色紀律），拿它去畫「能量傷害」會污染全案最重要的資訊通道——玩家看到
## 琥珀必須永遠是「跟耗能有關」。所以彈丸＝物理、光束＝能量。回收者那顆
## 琥珀珠是唯一的例外，而它是對的：那顆珠真的是能量，正在流回電網。
func _draw_shots() -> void:
	var frac := _accum / BattleController.TICK
	for sh: Dictionary in s.shots:
		# 沒有 `by` 的一律當錨（`TL_CLICKTEST` 手塞的那一發）。
		var def := NodeDefs.of(String(sh.get("by", "anchor")))
		var a := _center(sh["from"])
		var b := _center(sh["to"])
		var t := Motion.progress(BattleController.SHOT_TTL, int(sh["ttl"]), frac)
		var fade := 1.0 - t
		if bool(def.get("pierce", false)):
			_shot_beam(a, b, fade)
			continue
		_shot_bolt(a, b, t, fade)
		# 濺射環只掛在這一發濺射的**第一筆**記錄上（`BattleController`），
		# 所以這裡畫幾次就是幾發，不會被打中的隻數放大。
		if sh.has("splash_at"):
			_shot_splash(_center(sh["splash_at"]), t, fade, float(def.get("splash", 0.0)))
		if float(def.get("reclaim", 0.0)) > 0.0:
			_shot_reclaim(a, b, t)


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
func _draw_enemies() -> void:
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		var def := Enemies.of(String(e["type"]))
		var p := _enemy_pos(e)
		var r := float(def.get("radius", 9.0))
		# 敵潮的動態是「有機的呼吸」（§4.2 ease-in-out-sine 循環）；
		# 相位用 id 錯開，一群敵人才不會像節拍器一起脹縮。
		var pulse := Motion.pulse(s.tick_count, Motion.AMBIENT, 0.12, float(e["id"]))
		var armored: bool = float(def.get("armor", 0.0)) > 0.0
		var swift: bool = float(def.get("speed", 1.0)) > SWIFT_SPEED
		# ★ 這裡曾經有兩個殘影當拖尾（B1.6.3 第一版），**實看 A/B 之後砍掉**：
		#   第 5 波的間距是 0.6 格，任何畫在身後的東西都會壓到後面那一隻——
		#   一列 11 隻分得開的敵人變成一條連續的香腸，把「看不出差異」修成了
		#   「看不出有幾隻」。速度線索因此全部收進**本體輪廓**（流線拉長），
		#   不佔用敵人之間的空隙。
		var pts := _enemy_shape(e, p, r, pulse, armored, swift)
		draw_colored_polygon(pts, Palette.TIDE_MAGENTA)
		# ★ 甲板（B1.6.3）：**同形描邊，不是外圈弧**。血量弧已經是 `tide.deep`
		#   的圓弧、畫在 `r+4`，再加一圈外弧就是同一個位置上的兩個訊息——
		#   而 §4.3b 那條規則說「換顏色不夠，要換形狀」。這個專案在這裡踩過
		#   兩次（B0.6 儲槽充能弧撞血條、B1.6 受擊環撞交戰環）。描邊在輪廓
		#   **內側**，和任何弧都不會疊。
		if armored:
			var plate := pts.duplicate()
			plate.append(pts[0])
			draw_polyline(plate, Palette.TIDE_DEEP, 3.0)
		# ★ 亮核心（B1.6.3）：**快**在 16px 上唯一活得下來的線索。
		#   輪廓的壓扁在 fit 倍率幾乎讀不到（實看 A/B 抓到），明度差讀得到。
		#   畫在**中心**而不是外圈：外圈已經有甲板描邊與血量弧兩個訊息了。
		elif swift:
			draw_circle(p, r * pulse * 0.45, Palette.TIDE_BRIGHT)
		# ★ 被潮鳴抓住的敵人：輪廓描一圈 `order.cyan`（B1.8）。
		#   **標在敵人身上而不是塔上**——減速 −40%／破甲 −25% 作用在它身上，
		#   標在這裡因果才讀得出來；標在塔上只說得出「它開著」。
		#   閉合折線，和血量弧（`tide.deep` 圓弧）一個是線一個是弧，分得開（§4.3b）。
		var slow := 0.0 if i >= _auras.size() else (_auras[i] as Vector2).x
		if slow > 0.01:
			var ring := pts.duplicate()
			ring.append(pts[0])
			draw_polyline(ring, Palette.alpha(Palette.ORDER_CYAN, 0.35 + 1.4 * slow), 2.0)
		var frac := float(e["hp"]) / maxf(1.0, float(def.get("hp", 1.0)))
		if frac < 1.0:
			draw_arc(p, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 20, Palette.TIDE_DEEP, 2.0)


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
func _draw_threat(cell: Vector2i, p: Vector2) -> void:
	if not _threat.has(cell):
		return
	var a := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.3)
	var col := Palette.alpha(Palette.WARN_ORANGE, a)
	var h := Shapes.GRID * 0.5 - 1.0   # 半格：括號貼著這一格的邊界
	var arm := 6.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := p + Vector2(sx * h, sy * h)
			draw_line(corner, corner - Vector2(sx * arm, 0.0), col, 2.0)
			draw_line(corner, corner - Vector2(0.0, sy * arm), col, 2.0)


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
	var frac := _accum / BattleController.TICK
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
	var frac := _accum / BattleController.TICK
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
		var count := 3 + (absi(seed_id) % 3)
		for i in count:
			var dir := Motion.fragment_dir(seed_id, i, count)
			var p := at + dir * (10.0 + 22.0 * e)
			var r := (5.0 if chaos else 4.0) * (1.0 - 0.6 * t)
			var c := Palette.alpha(col, 1.0 - t)
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


## ★ 敵人的輪廓（B1.6.3，`20_ART_DIRECTION.md` §1.7）。
##
## 三種輪廓**全部由既有的機制欄位推導**，不新增美術資料：
##   預設        9 邊柔性水滴、wobble ±15%          ← 漂蟲
##   `armor > 0` 6 邊硬稜角、wobble ±7%             ← 甲殼（物理打不動它）
##   `speed 快`  沿行進方向拉長的尖銳水滴 ＋ 拖尾   ← 熾泳
##
## 這樣做的第一個理由不是省事，是**設計上不可能說謊**：沒有辦法做出一隻
## 「有護甲但看起來不硬」的敵人。M3 擴到 18 種敵人時也自動正確（§5 內容矩陣）。
##
## 三者仍然全部屬於**混沌**側（§0）：不規則、脈動、不對齊網格。硬稜角指的是
## 頂點少、抖動小，不是變成正六邊形——正多邊形是秩序側的語彙。
func _enemy_shape(
	e: Dictionary, p: Vector2, r: float, pulse: float, armored: bool, swift: bool
) -> PackedVector2Array:
	var sides := 6 if armored else 9
	var amp := 0.07 if armored else 0.15
	var pts := PackedVector2Array()
	# `k` 而不是 `i`：呼叫端已經用掉 `i`（敵人索引），而 GDScript 的 for
	# 迭代變數共享同一個作用域——同名會是 parse error，不是遮蔽。
	for k in sides:
		var a := TAU * float(k) / float(sides)
		# 每隻各自的不規則度，由 id 決定（同一隻永遠長同一個樣子）。
		# 值域收在 ±amp：再寬就會有頂點塌進去，變成尖角旗子而不是水滴。
		var wobble := 1.0 + amp * sin(float(e["id"]) * 3.7 + a * 2.0)
		var v := Vector2(cos(a), sin(a)) * r * pulse * wobble
		if swift:
			# ★ 流線＝**垂直於行進方向壓扁**，不是沿行進方向拉長（B1.6.3 實看修正）。
			#
			#   前兩版都往「拉長」的方向做（先加拖尾、再加長本體），A/B 對照
			#   當場否決：第 5 波的間距是 0.6 格，**任何沿行進軸變長的東西都會
			#   碰到鄰居**——一列 11 隻分得開的敵人糊成一條連續的香腸，把
			#   「看不出差異」修成了「看不出有幾隻」。
			#
			#   壓扁則相反：footprint 只會變小，結構上不可能製造新的重疊，
			#   而「薄」在一排圓團與六邊形之間仍然是一眼分得出來的輪廓。
			var d := _enemy_dir(e)
			var perp := Vector2(-d.y, d.x)
			v -= perp * v.dot(perp) * 0.45
		pts.append(p + v)
	return pts


## 行進方向（單位向量）。路徑是正交的，所以這就是「下一格 − 這一格」。
func _enemy_dir(e: Dictionary) -> Vector2:
	var prog := float(e["progress"])
	var i := clampi(int(floor(prog)), 0, s.path.size() - 1)
	var j := mini(i + 1, s.path.size() - 1)
	if i == j:
		return Vector2.RIGHT
	return (Vector2(s.path[j] - s.path[i]) as Vector2).normalized()


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
	var cf := _drag_from
	if cf.x >= 0:
		draw_rect(Rect2(_world(cf), g), Palette.ORDER_BRIGHT, false, 2.0)
		_draw_connect_guides(cf)
		# ★ 預覽線依**合法性**上色。B0.7.2 之前不管連不連得成都畫一條亮線，
		#   那是在畫一條不可能存在的導管——玩家只能點下去才知道不行。
		var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, _hover, s.conduit_cells()
	)
		var legal: bool = code == Build.OK and not s.node_at(_hover).is_empty()
		draw_line(
			_center(cf), _center(_hover),
			Palette.alpha(Palette.OK_GREEN if legal else Palette.WARN_ORANGE, 0.7), 2.0
		)


## ★ 連線的八條方向導引（`10_GDD.md` §3.2「導管只能走水平／垂直／45°」）。
##
## 使用者回報「沒有辦法 45 度放置管道」——規則其實是通的，**難的是用肉眼在
## 網格上找出正斜角**（要 |dx| 恰好等於 |dy|）。一條規則如果只能靠試錯才知道
## 自己有沒有踩中，那它在體感上就等於壞掉。把八條合法方向直接畫出來，
## 「45°」從一句文字變成畫面上看得到的四條斜線。
func _draw_connect_guides(anchor: Vector2i) -> void:
	var from := _center(anchor)
	var col := Palette.alpha(Palette.ORDER_DIM, 0.5)
	var size: Vector2i = s.map["size"]
	for d: Vector2i in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]:
		var end := anchor
		while _in_map(end + d):
			end += d
		if end != anchor:
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

	# ★ 選單（B1.4.1）。ESC 是快捷，**不是唯一的路**（P3：操作不得只靠鍵盤）。
	#   放左上角 x<120、y<56 那塊角落——頂欄從 x=120 起、建造欄從 y=56 起，
	#   全畫面只剩這裡是空的，而它也正好是選單的慣例位置。
	var menu_bar := UiKit.hbox(0)
	menu_bar.position = Vector2(8, 6)
	add_child(menu_bar)
	_menu_button = Button.new()
	_menu_button.text = "選單"
	_menu_button.custom_minimum_size.x = 104
	_menu_button.pressed.connect(_toggle_menu)
	menu_bar.add_child(UiKit.touchable(_menu_button))

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
		# 鈕上**只有名字**（使用者指定，B1.3.1）：價牌在提示列的第一行，
		# 而滑鼠移到鈕上時圖鑑浮層也會寫一次。同一個數字印三遍只是把鈕撐長。
		var b := _tool_button(group, NodeDefs.label(type))
		b.pressed.connect(_on_build_type.bind(type))
		# ★ 角色簡介：滑鼠停在鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
		b.mouse_entered.connect(_on_codex_show.bind(type, b))
		b.mouse_exited.connect(_on_codex_hide)
		_build_buttons[type] = b
		col.add_child(UiKit.touchable(b))
	(_build_buttons[_build_type] as Button).button_pressed = true

	col.add_child(_spacer(4))
	# ★ 動作鈕只剩兩顆（B1.3.1，使用者指定）：
	#   **「連線」拿掉**——B1.6.2 的拖曳已經完全取代它，留著一顆進去只能點兩次
	#   的模式鈕，等於在教一個比較慢的做法。
	#   **「移動」拿掉**——改成滑鼠中鍵按住拖。平移是一個持續性的動作，
	#   把它做成模式代表玩家每次看完別的地方都要記得切回來，而忘記切回來的
	#   代價是「點地圖沒反應」。
	var modes := GridContainer.new()
	modes.columns = 2
	modes.add_theme_constant_override("h_separation", 2)
	modes.add_theme_constant_override("v_separation", 2)
	col.add_child(modes)
	for pair: Array in [[Mode.UPGRADE, "加粗"], [Mode.DEMOLISH, "拆除"]]:
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
		"操作　左鍵做事、中鍵移動視野、滾輪縮放、ESC 開選單。沒有右鍵",
		"　蓋節點：左欄選一種 → 左鍵點地圖上的一格",
		"　拉導管：從一個節點按住左鍵，拖到另一個節點放開（隨時都能拖，不用切模式）",
		"　加　粗：「加粗」→ 點導管的中間（不是兩端的節點）",
		"　拆　除：「拆除」→ 點節點或導管，返還 75%",
		"　移　動：按住滑鼠中鍵拖動地圖（放大之後才需要）",
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
	# ★ 不設寬度的話它會長到最長那一行那麼寬（熔爐那一行 850px），
	#   從 x=124 一路蓋掉 x=870 的能量面板——兩個浮層同時開就疊在一起。
	_codex_label.custom_minimum_size.x = 640.0
	_codex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	_drag_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


func _on_mode(mode: int) -> void:
	_mode = mode
	_drag_from = Vector2i(-1, -1)
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
	# ★ 倒數最後 10 秒脈動（`20_ART_DIRECTION.md` §4.3「一定要動」清單，B1.6）。
	#   **它動的是階段那一格**，不是整條頂欄——脈動要指向「時間快到了」這一件事。
	#   週期用 `dur.slow`：比環境呼吸急、又不到讓人分心的程度。
	var phase_label := _top.get_child(5) as Label
	var urgent: bool = s.phase == "prep" and s.prep_time() - s.phase_time <= 10.0
	phase_label.modulate = Color(1, 1, 1, 1)
	if urgent:
		phase_label.add_theme_color_override("font_color", Palette.WARN_ORANGE)
		phase_label.modulate = Color(1, 1, 1, Motion.pulse01(s.tick_count, Motion.SLOW, 0.45))


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
	# ★ 局一結束 `BattleController.step()` 就直接 return，開火線與碎片的 `ttl`
	#   從此不再遞減——它們會**永遠停在畫面上**，看起來像每一座塔都卡在開火的
	#   那一幀（使用者回報「他們還在射擊」）。兩者都是純渲染、不進 `state_hash()`，
	#   由畫面層在這裡收乾淨。
	s.shots.clear()
	s.bursts.clear()
	s.shields.clear()
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
	# ★ 無盡的個人最佳（B2.1a、§7.10）。放在星等的位置——無盡沒有星，
	#   「破了幾項紀錄」就是它的成就感來源。兩欄各自比對（`apply_endless`）。
	if endless_seed != 0:
		var e: Dictionary = GameState.data.get("endless", {})
		var prev_wave := int(e.get("best_wave", 0))
		var prev_output := float(e.get("best_output", 0.0))
		var fresh := SaveService.apply_endless(GameState.data, waves, score)
		SaveService.save_from(GameState.data)
		for line: Array in [
			["最高波次　%d 波" % waves, bool(fresh["wave"]), "前次 %d 波" % prev_wave],
			["最佳產能　%.1f" % score, bool(fresh["output"]), "前次 %.1f" % prev_output],
		]:
			col.add_child(UiKit.label(
				"%s　%s" % [line[0], "★ 新紀錄" if line[1] else line[2]],
				15, Palette.ENERGY_AMBER if line[1] else Palette.TEXT_SECONDARY, false
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
	# ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」——
	#   上面那幾行是**成績**，這一行才是**原因**。放在按鈕正上方：
	#   玩家的視線在按「立刻重來」之前一定會經過這裡。
	var why := _diag_line(won)
	if why != "":
		var lbl := UiKit.label(
			why, 14, Palette.WARN_ORANGE if not won else Palette.ORDER_CYAN, false
		)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size.x = 400.0
		col.add_child(lbl)
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


# ── 局內選單（B1.4.1）────────────────────────────────────────────────
#
# ★ **不暫停**（`10_GDD.md` B5「不可暫停，但可跳過等待」）。選單開著的這幾秒
#   敵人仍然在走、電仍然在流。這不是偷懶：可暫停的選單就是一個「隨時可以停下來
#   慢慢想」的按鍵，而那正是 B5 要擋掉的東西。面板上直接寫出來，玩家才不會
#   以為是遊戲壞了——**沒說出口的規則會被當成 bug**。

## ESC。**鍵盤不是唯一的路**（手機移植預留條款 P3）：左上角有一顆「選單」鈕
## 做完全同一件事，`_toggle_menu()` 是兩者共用的那一個入口。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 設定浮層開著時**不消費事件**，交給它自己的 ESC（它會回到選單）。
	# 這樣兩邊誰先被呼叫都不影響結果——不必賭 Godot 的輸入傳遞順序。
	if _settings_layer != null:
		return
	get_viewport().set_input_as_handled()
	AudioBus.play("ui_back")   # ESC ＝ 取消手勢，全遊戲同一個音（B1.5）
	_toggle_menu()


func _toggle_menu() -> void:
	if _menu_layer != null:
		_close_menu()
		return
	_open_menu()


## 半透明遮罩。它做兩件事：把戰場壓暗讓選單讀得到，以及**吃掉滑鼠**——
## 選單開著的時候點下去不該蓋出一個節點來（`mouse_filter` 預設 STOP）。
func _scrim() -> Control:
	var layer := ColorRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.color = Palette.alpha(Palette.BG_DEEP, 0.82)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP   # 明寫：擋滑鼠是它一半的工作
	return layer


func _open_menu() -> void:
	_close_menu()
	_menu_layer = _scrim()
	add_child(_menu_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_layer.add_child(center)
	var box := UiKit.panel()
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 面板不吃滑鼠，但鈕要點得到
	center.add_child(box)
	var col := UiKit.vbox(8)
	box.add_child(col)
	col.add_child(UiKit.label("選單", 28, Palette.ORDER_BRIGHT))
	col.add_child(UiKit.label("時間仍在走——這款遊戲不能暫停。", 13, Palette.WARN_ORANGE))
	_menu_buttons.clear()
	# 「重來」與「退出」的代價寫在鈕上。**不做二次確認**：R1 說失敗只花時間，
	# 而一句括號比一個確認框省一次點擊，也省一整個對話框元件。
	var entries: Array = [
		["繼續", _close_menu],
		["重來（本局歸零）", _restart],
		["設定", _open_settings],
	]
	if on_exit.is_valid():
		entries.append(["退出（放棄本局）", on_exit])
	for entry: Array in entries:
		var b := Button.new()
		b.text = String(entry[0])
		b.custom_minimum_size.x = 200
		b.pressed.connect(entry[1] as Callable)
		_menu_buttons.append(b)
		col.add_child(UiKit.touchable(b))


func _close_menu() -> void:
	if _menu_layer == null:
		return
	# `queue_free()` 要到影格末才生效，中間那一幀遮罩還在畫也還在吃滑鼠——
	# 先 `remove_child()` 讓它當場離開樹（`Campaign._clear()` 同一條）。
	remove_child(_menu_layer)
	_menu_layer.queue_free()
	_menu_layer = null
	_menu_buttons.clear()


## 局內開設定：整個設定畫面原封不動疊上來，不另做一份「局內版設定」——
## 兩份設定畫面遲早會有一份漏掉新選項。
func _open_settings() -> void:
	_close_menu()
	_settings_layer = _scrim()
	add_child(_settings_layer)
	var screen := SettingsScreen.new()
	screen.on_exit = _close_settings
	_settings_layer.add_child(screen)


func _close_settings() -> void:
	if _settings_layer != null:
		remove_child(_settings_layer)
		_settings_layer.queue_free()
		_settings_layer = null
	_open_menu()


func _restart() -> void:
	for c: Node in get_children():
		c.queue_free()
	# 選單／設定浮層是 `get_children()` 的一員，上面那圈已經把它們清掉了；
	# 這裡要跟著把手上的參照放掉，否則下一次 ESC 會以為選單還開著。
	_menu_layer = null
	_settings_layer = null
	_menu_button = null
	_menu_buttons.clear()
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
	# 拖曳中就只講這一條線連不連得成——這時玩家問的問題只有那一個。
	if _drag_from.x >= 0:
		_hint.text = "▶ %s\n%s" % [
			"放開在另一個節點上就拉出一條導管；放開在空地／原地則取消。",
			_connect_hint() if _in_map(_hover) else "",
		]
		return
	match _mode:
		Mode.BUILD:
			if _in_map(_hover):
				parts.append_array(BuildController.preview_place(s, _build_type, _hover)["lines"])
			else:
				parts.append("建造 %s：左鍵點一格放下；從既有節點按住拖到另一個節點＝拉導管。" % NodeDefs.label(_build_type))
		Mode.UPGRADE:
			# 上限寫成算出來的：科技「導管擴容」會把基礎值推到 16（滿配 34），
			# 寫死「→28」在買過科技之後就是錯的（B1.3）。
			parts.append("加粗：左鍵點一段導管的「中間」（不是兩端的節點）。每級 +6 吞吐，上限 3 級（→%d）。1 級 20 礦砂；2 級 40 礦砂＋20 合金；3 級 60 礦砂＋50 合金。" % int(
				Build.conduit_cap(Build.CAP_MAX_LEVEL, float(s.mods["cap_bonus"]))
			))
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
		return "礦砂要「送達核心」才入帳：從採集器按住左鍵，拖到下一個節點放開，一路接到右下角的核心。"
	if s.count_of("generator") == 0:
		return "有礦砂了（看頂欄 ▲/秒）。左欄點「發電機」蓋一台，再從採集器拖一條線給它：4 礦砂/秒 → 20 能量/秒。"
	if _towers() == 0:
		return "電有了。左欄點「錨」（最便宜的塔）蓋在「離紫色路徑 2 格以上」的地方——貼太近會被走過的敵人打壞。"
	if _unpowered_tower():
		return "那座塔還沒接進電網，交戰時一發都打不出：從那座塔按住拖到發電機那一側的節點。"
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
		return "熔爐產的合金也要「送達核心」才入帳：從熔爐拖一條線出去，一路接到核心；同時它的礦砂與電也都要接得到。"
	if s.phase == "prep":
		return "都齊了。等倒數跑完自動開波，或按「提前召喚」提早開——倒數剩越多，這一波掉落倍率越高。"
	return "波次進行中：盯著頂端能量條，橙色那截就是餵不飽的部分；節點上的橙色倒三角＝這個缺料。"


## 連線預覽的逐格回報。**連不成的時候要說出差在哪**——「不是 45°」對玩家
## 沒有動作可做，「橫 4 直 3，要 4/4 或 3/3」才有。
func _connect_hint() -> String:
	if s.node_at(_hover).is_empty():
		return "終點也要是一個節點（先在那裡蓋一個「中繼」）。"
	var cf := _drag_from
	var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, _hover, s.conduit_cells()
	)
	if code == Build.NOT_STRAIGHT:
		var d: Vector2i = _hover - cf
		return "✕ 不是直線：橫 %d 直 %d。要走 45° 兩邊得一樣長；否則先放一個「中繼」轉彎。" % [
			absi(d.x), absi(d.y)
		]
	if code != Build.OK:
		return "✕ " + BuildController.reason_text(code)
	var cost := Build.conduit_cost(cf, _hover)
	var afford := "" if s.ore >= float(cost) else "　（礦砂不夠）"
	return "✔ 可連：%s → %s，%d 礦砂%s" % [
		_label_at(cf), _label_at(_hover), cost, afford
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
