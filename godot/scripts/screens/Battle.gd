class_name BattleScreen
extends Control
## 局內畫面的組裝根（`10_GDD.md` §6.2：**全畫面地圖 ＋ 浮層**，不是三欄式）。
##
## B3.14 起這個檔只做四件事：持有「一局」（`s`）與互動狀態、建立並串起各元件、
## 驅動每幀更新（`_process`）與繪圖順序（`_draw`）、轉交 Godot 的虛擬方法。
## 其餘都在元件裡（`BattleXxx.gd`，同一個資料夾）；狀態歸擁有它的元件，
## 元件之間只透過 `battle.<handle>.<成員>` 往來（不帶底線＝對外公開）。
##
## **核心玩法與呈現的分界**（`30_TECH_DESIGN.md` §2.6，換 3D 時照這張表動手）：
##   核心玩法（scripts/game，無畫面、無 autoload）
##       RunSetup 開局｜RunLoop 固定步長｜BattleController 每 tick｜BuildController 玩家指令
##       RunSettlement 結算｜RunDiagnosis 死因｜HintRules 下一步｜Readout 狀態→數字與句子
##   2D 專用（3D 版整組取代）
##       cam（BattleCamera）｜guide（BattleGuide）｜ground／network／fight／overlay（BattleDraw*）
##   HUD 與輸入（疊層，多半可沿用；輸入把「螢幕位置」換成「格」的那一步要改）
##       topbar／bars／prio／help／energy／codex／bp／inspect／hints／menu／result／inp
##   音訊提示：cues（BattleAudioCues，從狀態差值推導，3D 可原封沿用）
##   開發用（不進正式流程）：BattleSelftest（`Hooks.run_selftest`）｜BattleStress｜BattleDemo


const Combat := preload("res://scripts/sim/Combat.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const RunDiagnosis := preload("res://scripts/game/RunDiagnosis.gd")
const RunLoop := preload("res://scripts/game/RunLoop.gd")
const RunSetup := preload("res://scripts/game/RunSetup.gd")

## ★ B1.3.1：`CONNECT` 與 `PAN` 兩個模式已刪。拉線一律是拖曳（B1.6.2 取代了
## 「連線」模式），平移是滑鼠中鍵按住拖——**兩件事都不該是模式**：
## 模式的代價是「忘記切回來時點地圖沒反應」，而這兩個動作都頻繁到會天天付這個代價。
## ★ B3.7.1：**「升級」與「拆除」兩顆模式鈕拿掉**（使用者指定）。
##
## B3.7 把兩個動詞搬到檢視面板上（點那個東西 → 鈕就在旁邊），模式鈕變成同一件事
## 的第二條路——而且是比較慢的那一條（切模式 → 點目標 → 切回建造）。
## 留著兩條路的代價不只是兩顆鈕：**它們是兩套要各自維護、各自驗的點擊語意**，
## 而 B1.3.1 拿掉「連線」與「移動」時的理由一字不改地適用。
enum Mode { BUILD, BLUEPRINT }

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

## ★ 這一局的難度層（B2.6、§7.16）。**0 ＝ 標準**，只有無盡帶得進來——
## 戰役是難度階梯（§7.9）、每日兩榜要可比（§3.10），兩者都恆為 0。
## 由呼叫端在 `add_child()` 之前指派，同 `level`／`endless_seed`。
var difficulty: int = 0

## ★ 每日挑戰打的是哪一張榜（B2.2）。`""` ＝ 不是每日局。
## **地圖仍然走 `endless_seed`**——每日挑戰就是無盡跑在一個固定的日種子上
## （§3.10「兩榜共用同一套地圖、波次、模擬與計分」），這個欄位只決定兩件事：
## 起始配置吃不吃玩家的科技，以及成績寫進哪一格存檔。
var daily_board: String = ""

## 每日挑戰的日期鍵（`YYYY-MM-DD`）。成績要記在哪一天名下。
var daily_date: String = ""

## 回關卡選擇。測試圖沒有上一層，所以是 Callable 而不是寫死的場景切換。
var on_exit: Callable = Callable()

var mode: int = Mode.BUILD

var build_type: String = "extractor"

## 拖曳拉線的起點（B1.6.2）。−1 ＝ 沒有在拉線。
var drag_from: Vector2i = Vector2i(-1, -1)

## ★ 藍圖框選的起點（B2.3）。−1 ＝ 沒有在框。
var bp_from: Vector2i = Vector2i(-1, -1)

## ★ 待展開的藍圖索引（B2.3）。−1 ＝ 沒有拿著藍圖。
## 拿著藍圖時左鍵點地圖＝把它放在那裡，而不是蓋一個節點。
var bp_index: int = -1

## 中鍵按著沒放（B1.3.1）＝正在平移地圖。
var panning: bool = false

var hover: Vector2i = Vector2i(-999, -999)

## ★ 被檢視的那一格（B3.6）。`(-1,-1)` ＝ 沒有選取。
## **不是模式**——選取是一個狀態，模式是一個動詞，兩者混在一起的話
## 「選著一座塔的時候還能不能蓋東西」會變成一個要另外回答的問題。
var selected: Vector2i = Vector2i(-1, -1)

## ★ 被檢視的那條導管（B3.7）。存的是**導管 `id` 不是索引**，−1 ＝ 沒有選取。
##
## 索引會位移：拆掉任何一條線、或**敵人啃斷一條線**，後面每一條的索引都往前挪。
## 存索引的話面板會安靜地換成講另一條線——而那正好發生在戰鬥最亂的時候。
var sel_wire: int = -1

## 游標的**格為單位浮點座標**。命中導管要靠它（格解析度分不出「壓在線上」）。
var hover_p: Vector2 = Vector2(-999, -999)

var accum: float = 0.0

var message: String = ""

## 本幀交戰中的塔 `{id: Array}`。繪圖層自己算——它要畫的是「誰正在吃電」，
## 而模擬只留了一個座數（`rates.engaged`）。
var engaged: Dictionary = {}

## 本幀每隻敵人身上的光環 `Vector2(減速, 破甲)`，與 `s.enemies` 同索引。
## 和 `_engaged` 一樣是**繪圖層自己算的**：模擬層每 tick 都在算同一份，
## 但它只把結果用在傷害上、沒有留下來，而畫面要畫的是「誰被抓住了」。
var auras: Array = []

## 上一幀看到的 tick 序號（音訊與死因診斷共用的邊緣偵測）。
var last_tick: int = -1

## 死因歸因的累計（B1.7）。純畫面層，模擬層不知道它的存在。
var diag := RunDiagnosis.new()

## 本幀「正在被啃」的格（敵人相鄰 1 格內）。**純渲染推導，不新增任何狀態**
## ——同一份判定模擬層每 tick 都在做（`Tide.in_blast`），這裡只是把它畫出來。
var threat: Dictionary = {}

## 本幀每隻敵人所在的格（與 `s.enemies` 同索引）、id → 索引、「這一 tick 被打中的
## 敵人 id」。三者都是**純渲染推導**（B3.11／B3.12，彈丸落點與受擊一閃用），
## 不新增任何模擬狀態。
var enemy_cells: Array = []

var enemy_index: Dictionary = {}

var hit_ids: Dictionary = {}

## 元件（B3.14 自 Battle.gd 拆出）。狀態歸擁有者，這裡只持有參照。
var cam: BattleCamera
var guide: BattleGuide
var cues: BattleAudioCues
var ground: BattleDrawGround
var network: BattleDrawNetwork
var fight: BattleDrawFight
var overlay: BattleDrawOverlay
var topbar: BattleTopbar
var bars: BattleBars
var prio: BattlePriorityPanel
var help: BattleHelpPanel
var energy: BattleEnergyPanel
var codex: BattleCodexPanel
var bp: BattleBlueprintPanel
var inspect: BattleInspectPanel
var hints: BattleHint
var menu: BattleMenu
var result: BattleResult
var inp: BattleInput
## 開發用元件（壓力量測）：只在對應的測試鉤子存在時才以路徑載入。自檢走 `Hooks.run_selftest()`。
var _stress: RefCounted = null


func _init() -> void:
	cam = BattleCamera.new(self)
	guide = BattleGuide.new(self)
	cues = BattleAudioCues.new(self)
	ground = BattleDrawGround.new(self)
	network = BattleDrawNetwork.new(self)
	fight = BattleDrawFight.new(self)
	overlay = BattleDrawOverlay.new(self)
	topbar = BattleTopbar.new(self)
	bars = BattleBars.new(self)
	prio = BattlePriorityPanel.new(self)
	help = BattleHelpPanel.new(self)
	energy = BattleEnergyPanel.new(self)
	codex = BattleCodexPanel.new(self)
	bp = BattleBlueprintPanel.new(self)
	inspect = BattleInspectPanel.new(self)
	hints = BattleHint.new(self)
	menu = BattleMenu.new(self)
	result = BattleResult.new(self)
	inp = BattleInput.new(self)


## 載入一個開發用元件。路徑字串而不是 `class_name`，正式流程的程式碼因此不靠它。
func _dev(part: String) -> RefCounted:
	return (load("res://scripts/screens/Battle%s.gd" % part) as GDScript).new(self)


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
	# `TL_PANEL=sandbox`：沙盤「靜水」（`data/Maps.gd`）。**合金那一列流動珠
	# 只有這張圖上有**——淺灘的示範佈局沒有熔爐，所以第三種資源的視覺編碼
	# 在任何既有截圖裡都不會出現，而沒被看過的編碼不算通過 R-3。
	_setup_session()
	# 地貌層要是**第一個**子節點，而且畫在本體之後面：網格、路徑、節點、遮罩全在它上面。
	ground.terrain_layer = Node2D.new()
	ground.terrain_layer.show_behind_parent = true
	ground.terrain_layer.draw.connect(ground.paint_terrain)
	add_child(ground.terrain_layer)
	bars.build_ui()
	# 截圖驗證要看得到「流動中的網路」，空地圖證明不了任何事——
	# **除了首次體驗**（`50_QA_PLAN.md` §4.4），那正好要看玩家真正的第一眼，
	# 所以 `TL_DEMO_TICKS=0` 的語意是「不要示範佈局」。
	if Hooks.panel in ["battle", "sandbox", "campaign"] and Hooks.demo_ticks > 0:
		_dev("Demo").run()
	if Hooks.click_test:
		Hooks.run_selftest(self)


## 一局的起手。戰役關卡帶著自己的地圖與解鎖清單；沒有關卡就是測試圖／沙盤。
func _setup_session() -> void:
	s = RunSetup.new_session(run_spec(), GameState.data)
	cam.reset_view()
	cues.audio_reset()
	# 兩層一起起跑，戰鬥層先靜音（`AudioBus.music()` 的無縫切層前提）。
	AudioBus.music("battle")


## 這一局是什麼（`RunSetup.new_session()` 與 `RunSettlement.settle()` 吃同一份）。
## 欄位由呼叫端在 `add_child()` 之前指派；測試鉤子在這裡才翻成 spec，核心層看不到 `Hooks`。
func run_spec() -> Dictionary:
	return {
		"level": level, "endless_seed": endless_seed, "difficulty": difficulty,
		"daily_board": daily_board, "daily_date": daily_date,
		"sandbox": Hooks.panel == "sandbox", "stress": Hooks.stress,
	}


## 這一局蓋得出哪些節點。**空的 `unlocked` ＝ 全部**（測試圖與沙盤）。
##
## ★ B2.4 之後「全部」包含招募專屬的三隻，而測試圖與沙盤**刻意不吃名冊**：
## 那兩張圖是開發用的（主選單上寫著「測試圖」），要驗的是節點本身而不是進度。
## 真正的入口各自明講自己要什麼——戰役問關卡（§7.9）、無盡與自由榜問名冊、
## 統一榜走 `Daily.UNIFORM_BUILD`。**沒有一條路是靠這個預設值決定的。**
func buildable() -> Array:
	var unlocked: Array = s.sets.get("unlocked", [])
	return NodeDefs.BUILDABLE if unlocked.is_empty() else unlocked


func _process(delta: float) -> void:
	# ★ 視野緩動（B2.1d）。指數收斂與幀率無關——`1-exp(-k*dt)` 在 30fps 與
	#   144fps 下走完同一段路，`lerp(_, k*dt)` 不會。這只動**畫面**，
	#   不碰模擬：`_pan` 不進 `state_hash()`，也不影響任何 tick。
	if not cam.pan.is_equal_approx(cam.pan_goal):
		cam.pan = cam.pan.lerp(cam.pan_goal, 1.0 - exp(-BattleCamera.PAN_EASE * delta))
		if cam.pan.distance_to(cam.pan_goal) < 0.5:
			cam.pan = cam.pan_goal
		queue_redraw()
	# ★ 小地圖倒數。`TL_SHOT` 下**不倒數**——截圖落在第幾秒取決於這台機器
	#   跑了幾幀，會倒數的話同一組參數在不同機器上會拍出「有／沒有小地圖」
	#   兩種圖，截圖就不能拿來回歸比對了（和模擬凍結同一條理由）。
	if guide.mini_ttl > 0.0 and Hooks.shot_path == "":
		guide.mini_ttl = maxf(0.0, guide.mini_ttl - delta)
		if guide.mini_ttl <= 0.0:
			queue_redraw()

	# ★ `TL_SHOT` 下模擬凍結在 `_demo_layout()` 推完的那一格。否則截圖落在第幾
	# tick 取決於這台機器 3 秒內跑了幾幀——同一份佈局在不同機器上會拍出不同
	# 數字，截圖就不能拿來做回歸比對，也對不上 `TL_SIM=<同一個 N>` 的輸出。
	if Hooks.stress:
		if _stress == null:
			_stress = _dev("Stress")
		_stress.frame(delta)
	if Hooks.shot_path == "" and not Hooks.stress:
		# 固定時間步與快進（多跑幾個 tick、不拉長 tick）在 `RunLoop`——模擬不吃 delta。
		accum = RunLoop.advance(s, accum, delta)
	topbar.refresh_top()
	# 提示列每幀重算：它講的是**當前狀態**下的下一步，而狀態每 tick 都在變。
	# B0.7 之前它只在滑鼠移動時更新，於是「礦砂開始入帳了」「波次開打了」這類
	# 轉折要等玩家碰一下滑鼠才會反映——手不動的那幾秒，提示列是在說謊。
	hints.refresh_hint()
	energy.refresh_energy()
	# 檢視面板講的是**當下這個 tick** 的耗能與供電來源，所以它也要每幀重算。
	inspect.refresh_inspect()
	result.refresh_over()
	# ★ 一個 tick 邊緣偵測，兩個消費者（音訊、死因診斷）。
	#   兩邊各記一份「上一幀的 tick」的那一天，就會有一邊記錯（B1.5.1 的教訓）。
	var advanced: bool = s.tick_count != last_tick
	last_tick = s.tick_count
	cues.audio_tick(advanced)
	if advanced:
		diag.tick(s)
	queue_redraw()


func _draw() -> void:
	var size: Vector2i = s.map["size"]
	var rect := Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID)

	# ★ 全部的地圖繪圖都在**格為單位的地圖座標**裡做，縮放與平移交給這一個
	#   變換（B1.2.2）。所以底下每一支 `_draw_*` 都不知道縮放存在——
	#   縮放要是滲進 9 支繪圖函式裡，每加一種圖形就要記得乘一次倍率。
	#   文字不受影響：`_draw()` 裡沒有任何 `draw_string`，HUD 全是 Control 子節點。
	draw_set_transform(cam.map_origin(), 0.0, Vector2(cam.zoom, cam.zoom))
	# ★ 地貌（B3.13，§1.6c）：每張圖自己的地 ＋ 靜態裝飾，畫在網格線**之下**。
	#   本體只負責把那一層對到同一個視野；換圖才重建零件、重畫那一層。
	ground.sync_terrain()

	# 網格只畫在地圖範圍內：畫到浮層底下會讓「哪裡可以蓋」變得曖昧。
	Shapes.draw_grid(self, rect)

	# 敵人的格算一次給三個人用（交戰、光環、被啃判定）——同一幀各算一次的那一天，
	# 就會有一個用到的是上一幀的位置。
	var cells := Combat.enemy_cells(s.enemies, s.path)
	engaged = Combat.engaged(s.nodes, cells)
	auras = Combat.auras(s.nodes, cells, s.rates["satisfaction"])
	threat = fight.threat_cells(cells)
	# ★ B3.11：敵人的格與「這一 tick 被打中的格」留給 `_draw_enemies()` 讀
	#   （受擊一閃是純渲染推導：剛生出來那幾發的落點）。
	enemy_cells = cells
	enemy_index = fight.index_enemies()
	hit_ids = fight.hit_ids_of()
	ground.draw_path()
	ground.draw_ore_cells()
	ground.draw_fields()
	network.draw_conduits()
	network.draw_nodes()
	fight.draw_enemies()
	fight.draw_ripple()
	fight.draw_shots()
	fight.draw_bursts()
	fight.draw_shields()
	overlay.draw_selection()
	overlay.draw_hover()
	# 階段色調（`10_GDD.md` §6.2 硬性要求 4）：**不看計時器也知道自己在哪個階段**。
	# 蓋在最上層而不是墊在底下——墊底的話節點與敵人會把它整片蓋掉。
	draw_rect(rect, Palette.alpha(
		Palette.WARN_ORANGE if s.phase == "wave" else Palette.ORDER_CYAN,
		0.10 if s.phase == "wave" else 0.03
	))

	# ── 回到螢幕座標 ──────────────────────────────────────────────────
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ground.draw_frame_matte()
	# 導引畫在遮罩**之後**：它們的職責就是講「框架外面有什麼」，被遮罩蓋掉
	# 等於整個功能不存在。兩者都只在 `_oversized()` 時出現。
	guide.draw_arrows()
	guide.draw_minimap()
	network.draw_energy_bar()


## ESC。**鍵盤不是唯一的路**（手機移植預留條款 P3）：左上角有一顆「選單」鈕
## 做完全同一件事，`_toggle_menu()` 是兩者共用的那一個入口。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 設定浮層開著時**不消費事件**，交給它自己的 ESC（它會回到選單）。
	# 這樣兩邊誰先被呼叫都不影響結果——不必賭 Godot 的輸入傳遞順序。
	if menu.settings_layer != null:
		return
	get_viewport().set_input_as_handled()
	AudioBus.play("ui_back")   # ESC ＝ 取消手勢，全遊戲同一個音（B1.5）
	menu.toggle_menu()


func restart() -> void:
	for c: Node in get_children():
		c.queue_free()
	# 選單／設定浮層是 `get_children()` 的一員，上面那圈已經把它們清掉了；
	# 這裡要跟著把手上的參照放掉，否則下一次 ESC 會以為選單還開著。
	menu.menu_layer = null
	menu.settings_layer = null
	menu.menu_button = null
	menu.menu_buttons.clear()
	result.over_panel = null
	topbar.top = null
	# 這兩個陣列裝的是已經 `queue_free()` 掉的 Label——不清就會拿到斷裂的參照。
	topbar.top_values.clear()
	topbar.top_notes.clear()
	hints.label = null
	bars.ff_button = null
	bars.summon_button = null
	prio.prio_panel = null
	bp.bp_panel = null
	help.help_panel = null
	help.help_button = null
	energy.energy_panel = null
	energy.energy_button = null
	codex.codex_panel = null
	codex.codex_button = null
	codex.codex_label = null
	bars.zoom_button = null
	energy.energy_rows.clear()
	prio.prio_labels.clear()
	bars.mode_buttons.clear()
	bars.build_buttons.clear()
	mode = Mode.BUILD
	build_type = "extractor"
	# 選取要跟著局一起歸零。**`_sel_wire` 存的是 id，而新的一局的 id 從頭發**——
	# 不清的話重開一關會看到面板指著一條玩家沒選過的線（B3.7）。
	selected = Vector2i(-1, -1)
	sel_wire = -1
	_setup_session()
	accum = 0.0
	message = ""
	bars.build_ui()


## 滑鼠輸入。**必須是 `_gui_input`，不能是 `_unhandled_input`**——理由與整段歷史見
## `BattleInput.on_event()`。這裡只是 Godot 虛擬方法的入口，實作在輸入元件裡。
func _gui_input(event: InputEvent) -> void:
	inp.on_event(event)
