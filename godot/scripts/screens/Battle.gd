extends Control
## 局內畫面（`10_GDD.md` §6.2：**全畫面地圖 ＋ 浮層**，不是三欄式）。
##
## 這個檔案是**指揮者**，不畫圖、不做規則：
##   · 局的建立（`_setup_session()`）與每幀的節拍（`_process()`：推 tick、叫各模組更新）
##   · 輸入（`_gui_input()`／`_release()`／`_act()`）：把滑鼠事件翻成對 `BuildController` 的呼叫
##   · HUD 的**版面**（`_build_ui()`）：三條邊欄放在哪、哪顆鈕接哪個面板
##
## 其餘都在 `screens/battle/`（地圖怎麼畫、每個面板怎麼運作、測試鉤子）：
##   Stage／Stage2D   舞台（2D→3D 的接縫）     Overlay2D  能量列、小地圖、邊緣箭頭
##   Feedback         音效與死因               SelfTest   `TL_*` 測試鉤子
##   hud/*            各面板（頂欄、建造欄、提示列、優先權、能量、圖鑑、檢視、藍圖、說明、結算、選單）
##
## 外界（`Campaign`／`Tiers`／`DailyScreen`／`Main`）只做三件事：`new()`、指派下面這幾個欄位
## （`level`／`endless_seed`／`difficulty`／`daily_board`／`daily_date`／`on_exit`）、`add_child()`。

const Loadout := preload("res://scripts/sim/Loadout.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const MapsData := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const RosterData := preload("res://data/Roster.gd")
const Stage := preload("res://scripts/screens/battle/Stage.gd")
const Stage2D := preload("res://scripts/screens/battle/Stage2D.gd")
const Overlay2D := preload("res://scripts/screens/battle/Overlay2D.gd")
const Feedback := preload("res://scripts/screens/battle/Feedback.gd")
const SelfTest := preload("res://scripts/screens/battle/SelfTest.gd")
const TopBar := preload("res://scripts/screens/battle/hud/TopBar.gd")
const BuildBar := preload("res://scripts/screens/battle/hud/BuildBar.gd")
const HintBar := preload("res://scripts/screens/battle/hud/HintBar.gd")
const PriorityPanel := preload("res://scripts/screens/battle/hud/PriorityPanel.gd")
const EnergyPanel := preload("res://scripts/screens/battle/hud/EnergyPanel.gd")
const CodexPanel := preload("res://scripts/screens/battle/hud/CodexPanel.gd")
const InspectPanel := preload("res://scripts/screens/battle/hud/InspectPanel.gd")
const BlueprintPanel := preload("res://scripts/screens/battle/hud/BlueprintPanel.gd")
const HelpPanel := preload("res://scripts/screens/battle/hud/HelpPanel.gd")
const ResultPanel := preload("res://scripts/screens/battle/hud/ResultPanel.gd")
const MenuLayer := preload("res://scripts/screens/battle/hud/MenuLayer.gd")

## ★ 底欄的 y（B2.4.2 常數化）。它原本是三處各寫一次的 `668`，而 A-1 那個缺陷
## 正好是「建造欄長到蓋住底欄」——兩個會互相碰撞的東西，座標必須是同一個常數。
const BAR_Y := 668.0

## 建造清單捲動區的高度。**清單再長也只會在這個區域裡捲**，模式鈕永遠釘在
## 它下面、永遠碰不到底欄。
##
## 52 ＝ 動作鈕那一塊實際佔的高度：`vbox 間隔 2 ＋ 間隔物 4 ＋ 間隔 2 ＋ 一列 44`。
## ★ B3.7.1 從 100 降到 52：升級與拆除拿掉之後只剩「藍圖」一顆，**空出來的 48px
## 直接還給節點清單**（十三種節點，捲得越少越好）。
## ⚠ 這種「差幾個像素」的東西不要用眼睛判——第一版的 96 實測差 2px（第二列的底邊
## 落在 670，底欄在 668），`TL_CLICKTEST` 的 `pinned_ok` 當場印出來。
const BUILD_LIST_H := BAR_Y - 56.0 - 52.0

## ★ 「點在導管上」的命中半徑，單位是格（B3.7）。
##
## **刻意比 `conduit_near()` 的預設 0.5 窄。** 導管的中心線正好穿過它經過的每一格
## 的**格心**，所以 0.5 等於「整格都算在線上」——那會讓建造模式下再也蓋不出
## 「線從旁邊經過而不接它」的那種節點，而那是流量網路裡一個真的戰術選擇
## （`Build.can_connect()` 的原註寫著這條規則刻意不禁止穿過節點）。
##
## 0.3 讓線佔住格心那一條帶，格的四周仍然蓋得下去。代價是這條帶在 fit 倍率下
## 只有十幾個像素寬——低於 P3 的 44px 觸控門檻，所以手機移植時要靠放大操作。
## 已登記在 `40_PRODUCTION_PLAN.md` 的移植風險表。
const WIRE_PICK := 0.3

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

## ★ 局內畫面拆成模組（`screens/battle/`），各自是這個節點的子節點。
## 畫面層自己只留：局的建立、每幀的節拍、輸入、HUD 的版面。
##
## 地圖那一半：舞台（只認 `Stage.gd` 的契約）、覆蓋層、回饋、測試鉤子。
var stage: Stage = null
var overlay: Overlay2D = null
var feedback: Feedback = null
var selftest: SelfTest = null

## HUD 那一半（`screens/battle/hud/`）：每個面板擁有自己的 widget、狀態、更新與事件處理。
var topbar: TopBar = null
var buildbar: BuildBar = null
var hintbar: HintBar = null
var priopanel: PriorityPanel = null
var energypanel: EnergyPanel = null
var codexpanel: CodexPanel = null
var inspector: InspectPanel = null
var bppanel: BlueprintPanel = null
var helppanel: HelpPanel = null
var resultpanel: ResultPanel = null
var menulayer: MenuLayer = null

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

var _zoom_button: Button = null

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
var _panning: bool = false

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
	# 模組要在 `_setup_session()` 之前就位——它一開頭就要重設視野與音訊。
	_build_modules()
	# `TL_PANEL=sandbox`：沙盤「靜水」（`data/Maps.gd`）。**合金那一列流動珠
	# 只有這張圖上有**——淺灘的示範佈局沒有熔爐，所以第三種資源的視覺編碼
	# 在任何既有截圖裡都不會出現，而沒被看過的編碼不算通過 R-3。
	_setup_session()
	_build_ui()
	# 截圖驗證要看得到「流動中的網路」，空地圖證明不了任何事——
	# **除了首次體驗**（`50_QA_PLAN.md` §4.4），那正好要看玩家真正的第一眼，
	# 所以 `TL_DEMO_TICKS=0` 的語意是「不要示範佈局」。
	if Hooks.panel in ["battle", "sandbox", "campaign"] and Hooks.demo_ticks > 0:
		selftest.demo_layout()
	if Hooks.click_test:
		selftest.click_selftest.call_deferred()


## 建立並接上全部模組（`screens/battle/`）。
##
## **加入的順序有意義**：子節點依加入順序繪圖，後加的在上面——舞台在最底、覆蓋層次之，
## HUD 的 widget（`_build_ui()` 之後才加）在最上面。`restart()` 只重建 HUD 的 widget，
## 不動這些模組。
func _build_modules() -> void:
	stage = Stage2D.new()
	overlay = Overlay2D.new()
	feedback = Feedback.new()
	selftest = SelfTest.new()
	topbar = TopBar.new()
	buildbar = BuildBar.new()
	hintbar = HintBar.new()
	priopanel = PriorityPanel.new()
	energypanel = EnergyPanel.new()
	codexpanel = CodexPanel.new()
	inspector = InspectPanel.new()
	bppanel = BlueprintPanel.new()
	helppanel = HelpPanel.new()
	resultpanel = ResultPanel.new()
	menulayer = MenuLayer.new()
	_wire_modules()
	_bind_session()
	for m: Node in _modules():
		add_child(m)


## 全部模組。**舞台與覆蓋層排最前**（繪圖順序，見 `_build_modules()`）。
func _modules() -> Array[Node]:
	return [
		stage, overlay, feedback, selftest,
		topbar, buildbar, hintbar, priopanel, energypanel, codexpanel, inspector,
		bppanel, helppanel, resultpanel, menulayer,
	]


## 把「我」與「同伴」交給每個模組。模組各自宣告它要用到的同伴欄位（欄位名 ＝ 本檔的變數名），
## 這裡只管對號入座——**新增一個跨模組的呼叫不必來改這裡**，在那個模組裡多宣告一個欄位就好。
func _wire_modules() -> void:
	var mods: Array[Node] = _modules()
	for m: Node in mods:
		m.scr = self
		for other: Node in mods:
			var key := _field_of(other)
			if other != m and key in m:
				m.set(key, other)


## 模組的欄位名。**只有這一張表**——模組不自報名字，免得兩邊各寫一份而不一致。
func _field_of(m: Node) -> String:
	for key: String in ["stage", "overlay", "feedback", "selftest", "topbar", "buildbar", "hintbar",
			"priopanel", "energypanel", "codexpanel", "inspector", "bppanel", "helppanel",
			"resultpanel", "menulayer"]:
		if get(key) == m:
			return key
	return ""


## 把這一局的 `s` 交給需要它的模組。**每次 `s = SessionState.new()` 之後都要呼叫**——
## 模組各持一份引用（繪圖迴圈裡每次 `scr.s` 的查詢成本不值得），漏掉一次它們就停在上一局。
func _bind_session() -> void:
	for m: Node in _modules():
		if "s" in m:
			m.s = s


## 重畫舞台與覆蓋層。**所有「畫面該更新了」都走這一個**：舞台畫世界、覆蓋層畫螢幕座標的
## 東西，兩者讀同一份視野與局面，只通知其中一個就會有一層停在上一幀。
func redraw() -> void:
	stage.queue_redraw()
	overlay.queue_redraw()


## 一局的起手。戰役關卡帶著自己的地圖與解鎖清單；沒有關卡就是測試圖／沙盤。
func _setup_session() -> void:
	# ★ 局外科技（B1.3）。有測試鉤子時 `SaveService.persist=false` → 存檔是預設值
	#   → `unlocked` 為空 → mods 全中性，所以 `TL_*` 的任何一張截圖與任何一支自檢
	#   都不會因為這台機器上玩家買了什麼科技而改變（RG-61 的同一條紀律）。
	var meta := Loadout.of(GameState.data, difficulty)
	if not level.is_empty():
		s.setup(level["map"], level["unlocked"], meta)
	elif endless_seed != 0:
		# ★ 建造欄不再是「空陣列＝全部」（B2.4）。無盡與每日自由配置榜給的是
		#   **這名玩家的名冊**——招募池的三隻是抽到才有的，發給所有人等於沒有名冊。
		#
		# ★ 統一配置榜走一份**明列的固定清單**（`Daily.UNIFORM_BUILD`，§7.11）：
		#   它與玩家的任何進度與課金完全無關（憲法 B3），而「空陣列＝全部」會讓
		#   每加一隻角色就悄悄改變這張榜。這是 B2.2 記在 §7.11 的那筆債。
		#
		# ★ 兩榜的差異仍然**只在 `SessionState.setup()` 的參數**（§3.10 明文：
		#   不得為此拆成兩套邏輯）。同一張生成圖、同一套波次、同一支模擬。
		var build_list: Array = (
			Daily.UNIFORM_BUILD.duplicate() if daily_board == Daily.UNIFORM
			else RosterData.buildable(GameState.data)
		)
		# ★ 統一配置榜的**全部**局外成長由 `Daily.meta_for()` 一次歸零（憲法 B3）。
		#   一軸一道閘等於靠列舉守住憲法（`sim/Loadout.gd` 開頭）。
		s.setup(MapGen.generate(endless_seed), build_list, Daily.meta_for(daily_board, meta))
	elif Hooks.stress:
		# ★ 壓力情境（B1.7、RG-8）：只為了量渲染。模擬在 `_process` 裡凍結——
		#   這一份佈局的單 tick 要 30 秒（`perf_test.gd` 的說明），不凍結的話
		#   量到的會是模擬的耗時，而渲染一幀都畫不完。
		s.setup(MapsData.stress_map(), [], meta)
		s.ore = 9999999.0
		s.alloy = 9999999.0
		BuildController.apply_ops(s, MapsData.stress_ops())
		for i in MapsData.STRESS_ENEMIES:
			s.add_enemy(["drifter", "carapace", "ember"][i % 3])
		s.phase = "wave"
	else:
		s.setup(MapsData.SANDBOX if Hooks.panel == "sandbox" else MapsData.SHOAL, [], meta)
	stage.reset_view()
	feedback.audio_reset()
	# 兩層一起起跑，戰鬥層先靜音（`AudioBus.music()` 的無縫切層前提）。
	AudioBus.music("battle")


func _on_zoom(mult: float) -> void:
	stage.zoom_by(mult, stage.FRAME.position + stage.FRAME.size * 0.5)


func _on_zoom_reset() -> void:
	stage.reset_view()
	refresh_zoom()
	redraw()


func refresh_zoom() -> void:
	if _zoom_button == null:
		return
	# TL_NAKED 遮所有數值標籤；縮放倍率也是數值。
	if Hooks.naked:
		_zoom_button.text = "全景"
		return
	_zoom_button.text = "全景 %d%%" % roundi(stage.zoom / maxf(0.0001, stage.fit) * 100.0)


func _process(delta: float) -> void:
	# 視野緩動與小地圖倒數：都只動畫面，不碰模擬（細節在各自的函式）。
	stage.tick_view(delta)
	overlay.tick(delta)

	# ★ `TL_SHOT` 下模擬凍結在 `_demo_layout()` 推完的那一格。否則截圖落在第幾
	# tick 取決於這台機器 3 秒內跑了幾幀——同一份佈局在不同機器上會拍出不同
	# 數字，截圖就不能拿來做回歸比對，也對不上 `TL_SIM=<同一個 N>` 的輸出。
	if Hooks.stress:
		selftest.stress_frame(delta)
	if Hooks.shot_path == "" and not Hooks.stress:
		accum += delta
		# 快進＝**多跑幾個 tick**，不是把 tick 拉長。固定時間步不能動，
		# 否則同一組操作在不同倍率下會跑出不同結果（§2.4 確定性）。
		var mult: int = s.speed_mult if s.phase == "prep" else 1
		var guard := 0
		while accum >= BattleController.TICK and guard < 8 * mult:
			for _i in mult:
				BattleController.step(s)
			accum -= BattleController.TICK
			guard += mult
	topbar.refresh_top()
	# 提示列每幀重算：它講的是**當前狀態**下的下一步，而狀態每 tick 都在變。
	# B0.7 之前它只在滑鼠移動時更新，於是「礦砂開始入帳了」「波次開打了」這類
	# 轉折要等玩家碰一下滑鼠才會反映——手不動的那幾秒，提示列是在說謊。
	hintbar.refresh_hint()
	energypanel.refresh_energy()
	# 檢視面板講的是**當下這個 tick** 的耗能與供電來源，所以它也要每幀重算。
	inspector.refresh_inspect()
	resultpanel.refresh_over()
	# ★ 一個 tick 邊緣偵測，兩個消費者（音訊、死因診斷）。
	#   兩邊各記一份「上一幀的 tick」的那一天，就會有一邊記錯（B1.5.1 的教訓）。
	var advanced: bool = s.tick_count != feedback.last_tick
	feedback.last_tick = s.tick_count
	feedback.audio_tick(advanced)
	if advanced:
		feedback.diag_tick()
	redraw()


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
			stage.pan_by(mm.relative)
			redraw()
			return
		# ★ 小地圖按住拖曳（B2.1d，使用者指定）：按住不放，視野持續跟著游標走。
		#   走 `_pan_goal` → 畫面是**平滑**追過去的，不是一格一格跳。
		if overlay.mini_drag:
			overlay.mini_seek(mm.position)
			return
		# 浮點座標每次都更新（不只格變的時候）：命中導管靠的是它，
		# 而「壓在線上」與「在同一格但離線遠」是同一格裡的兩件事。
		hover_p = stage.point_at(mm.position)
		var c := stage.cell_at(mm.position)
		if c != hover:
			hover = c
			hintbar.refresh_hint()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = mb.pressed
		return
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT and overlay.mini_drag:
			# 小地圖上放開：**不可以掉進 `_release()`**，否則等於在小地圖
			# 底下那一格結束一次拉線。
			overlay.mini_drag = false
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_release(mb.position)
		return
	# 滾輪縮放是桌面的便利，不是唯一的路：底欄有 ＋／−／全景 三顆鈕（P3）。
	#
	# ★ **只有游標在地圖框架裡才縮放**（B2.4.7，使用者實玩回報）。
	#   `ScrollContainer` 只在**捲得動的時候**吃掉滾輪事件；捲到頂還往上滾，
	#   事件就落回這裡——於是「建造欄滑到最上面再滑一下，地圖就放大了」。
	#   這條守衛同時擋掉底欄與頂欄上的滾輪，那本來也不該縮放地圖。
	#   ⚠ 不要改成「捲動容器把事件標記為已處理」——那要它在邊界也吞掉事件，
	#     而那會讓「滑到底之後想捲外層」這個標準行為壞掉。**限制範圍才是對的層級。**
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not stage.FRAME.has_point(mb.position):
			return
		stage.zoom_by(stage.ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / stage.ZOOM_STEP,
			mb.position)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# ★ 導引要先問（B2.1b）。小地圖蓋在地圖上面，不先攔的話點它會**在它底下
	#   那一格蓋出東西來**——而且玩家看不出為什麼，因為節點生在畫面外。
	if overlay.guide_click(mb.position):
		return
	# ★ 從節點上按下先不動作，等放開才決定（B1.6.2）：放開在同一格＝一次普通點擊，
	#   放開在另一個節點上＝拉一條導管。這樣「蓋一個 → 接一條 → 蓋一個 → 接一條」
	#   不用每一步都往返左欄切模式——第 1 關的參考解就是 6 蓋 6 接交替，
	#   舊路徑要切 10 次模式，而那 10 次沒有任何一次是決策。
	var c := stage.cell_at(mb.position)
	# ★ 藍圖框選（B2.3）：按下記起點，放開才成框。
	if mode == Mode.BLUEPRINT:
		bp_from = c
		redraw()
		return
	if mode == Mode.BUILD and not s.node_at(c).is_empty():
		drag_from = c
		redraw()
		hintbar.refresh_hint()
		return
	var p := stage.point_at(mb.position)
	# ★ **點在導管上＝檢視那條線**（B3.7，使用者提出）。
	#
	#   放在建造模式裡而不是另開一個模式，理由和 B3.6 選節點同一條：玩家的意圖是
	#   「這條線我要看一下、要動它」，那不該先去底欄按一顆鈕再回來。
	#
	#   ⚠ 節點優先——上面那條已經 return 了，和 `demolish()` 的判斷順序一致。
	#   ⚠ 拿著藍圖時不攔：那時左鍵是「把它放在這裡」，一個明確得多的意圖。
	#   命中帶刻意窄（`WIRE_PICK`），格的其他地方照舊蓋得下去——理由見那個常數。
	if mode == Mode.BUILD and bp_index < 0:
		var wi: int = s.conduit_near(p, WIRE_PICK)
		if wi >= 0:
			inspector.select_wire(int((s.conduits[wi])["id"]))
			hintbar.refresh_hint()
			redraw()
			return
	_act(c)
	hintbar.refresh_hint()


## 左鍵放開。只有「按下時停在某個節點上」的那條路徑會走到這裡。
func _release(pos: Vector2) -> void:
	if bp_from.x >= 0:
		var from_bp := bp_from
		bp_from = Vector2i(-1, -1)
		bppanel.save_blueprint(from_bp, stage.cell_at(pos))
		hintbar.refresh_hint()
		redraw()
		return
	if drag_from.x < 0:
		return
	var from := drag_from
	drag_from = Vector2i(-1, -1)
	var to := stage.cell_at(pos)
	if to != from and not s.node_at(to).is_empty():
		var code := BuildController.lay_conduit(s, from, to)
		if code == Build.OK:
			AudioBus.play("build_wire")
		message = text_of(code)
	else:
		# ★ **在既有節點上點一下＝檢視它**（B3.6，使用者提出）。
		#
		#   這個手勢原本只回一句「從這個節點按住往另一個節點拖」——一句教學，
		#   而玩家蓋到第三座塔之後就不需要它了，那之後這個手勢什麼都不做。
		#   換成選取之後，「點一下那座塔」給出射程、數據、當下耗能，
		#   以及**是誰在餵它電**。拖曳那句話改掛在提示列（`_refresh_hint()`）。
		#
		#   ⚠ 這一段**必須放在這裡，不是 `_act()` 的 BUILD 分支**：
		#   點在既有節點上會先進入「準備拉導管」的按下路徑，放開時走到這裡，
		#   根本到不了 `_act()`。第一版寫在那邊，於是面板永遠不開而斷言說
		#   「檢視=false」——輸入路徑的形狀只有真的送事件才看得出來。
		#
		#   不另開「檢視模式」：模式鈕在 B2.4.2 已經因為十三種節點擠過一次；
		#   也不綁右鍵——P3「操作不得只靠 hover／右鍵／鍵盤」。
		#
		#   ★ B3.7：再點一次同一座就取消選取（使用者提出）。選取是**開關**——
		#   沒有取消的路的話，面板一開就再也關不掉，而它蓋著地圖右半邊。
		selected = Vector2i(-1, -1) if selected == from else from
		sel_wire = -1
		inspector.refresh_inspect()
		message = "" if selected.x >= 0 else "從這個節點按住往另一個節點拖，就能拉一條導管。"
	hintbar.refresh_hint()
	redraw()


## ★ B3.7.1 起這裡只剩建造一種語意。
##
## 加粗與拆除本來在這裡各佔一支分支，並且各自需要**格為單位的浮點座標**才點得準
## （好幾條線擠在同一個節點上時，格解析度分不出玩家指的是哪一條，B1.2.1）。
## 兩個動詞搬到檢視面板之後，那個參數與它的兩支分支一起消失——**面板已經知道
## 玩家選的是哪一個東西，不必再用座標猜一次。**
func _act(cell: Vector2i) -> void:
	# 音效只在**真的做成了**的時候響（`Build.OK` ＝ 空字串）。失敗有提示列說原因，
	# 再配一個音只是把「你做錯了」講兩次。
	match mode:
		Mode.BUILD:
			# ★ 拿著藍圖時，左鍵是「把它放在這裡」而不是蓋一個節點（B2.3）。
			if bp_index >= 0:
				bppanel.expand_blueprint(cell)
				return
			# 蓋在空地上就取消選取：選取講的是「這一座」，而畫面已經換人了。
			selected = Vector2i(-1, -1)
			sel_wire = -1
			inspector.refresh_inspect()
			# ★ B3.7.1：手上什麼都沒拿（再按一次建造鈕就會這樣）＝點空地什麼都不做。
			#   不報錯——「我只是想收起面板」和「我蓋錯地方了」不是同一件事，
			#   對前者丟一句 ✕ 是把一個正常操作講成失敗。
			if build_type == "":
				message = ""
				return
			var code_b := BuildController.place(s, build_type, cell)
			if code_b == Build.OK:
				AudioBus.play("build_place")
			message = text_of(code_b)


func text_of(code: String) -> String:
	return "✔ 完成" if code == Build.OK else "✕ " + BuildController.reason_text(code)


func label_at(cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	return NodeDefs.label(String(n["type"])) if not n.is_empty() else "空地"


# ── 浮層 ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# ★ 頂欄三階 ＋ 固定寬度（B2.4.4）。舊版是七個 15px（**階外**）的 Label 直接
	#   丟進 HBox——11 個數字同一階，而且寬度隨數值變。規格見 `TOP_CELLS`。
	topbar.top = UiKit.hbox(8)
	topbar.top.position = Vector2(120, 12)
	add_child(topbar.top)
	topbar.top_values.clear()
	topbar.top_notes.clear()
	for spec: Dictionary in topbar.TOP_CELLS:
		var cell := UiKit.hbox(4)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		if String(spec["tag"]) != "":
			cell.add_child(UiKit.label(String(spec["tag"]), 13, Palette.TEXT_SECONDARY, false))
		var v := UiKit.label("", int(spec["vs"]), Palette.TEXT_PRIMARY, false)
		v.custom_minimum_size.x = float(spec["vw"])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(v)
		topbar.top_values.append(v)
		var n := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		n.custom_minimum_size.x = float(spec["nw"])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(n)
		topbar.top_notes.append(n)
		topbar.top.add_child(cell)

	# ★ 選單（B1.4.1）。ESC 是快捷，**不是唯一的路**（P3：操作不得只靠鍵盤）。
	#   放左上角 x<120、y<56 那塊角落——頂欄從 x=120 起、建造欄從 y=56 起，
	#   全畫面只剩這裡是空的，而它也正好是選單的慣例位置。
	var menu_bar := UiKit.hbox(0)
	menu_bar.position = Vector2(8, 6)
	add_child(menu_bar)
	menulayer.menu_button = Button.new()
	menulayer.menu_button.text = "選單"
	menulayer.menu_button.custom_minimum_size.x = 104
	menulayer.menu_button.pressed.connect(menulayer.toggle_menu)
	menu_bar.add_child(UiKit.touchable(menulayer.menu_button))

	# ★ 縮放（B1.2.2）。放在頂欄右端那片空白——建造欄與底欄都已經滿了，
	#   而地圖右上角是縮放控制的慣例位置。**三顆鈕都是可點的**：滾輪只是
	#   桌面的便利，手機移植預留條款 P3 不許任何操作只有滾輪／右鍵一條路。
	var zoom_bar := UiKit.hbox(6)
	zoom_bar.position = Vector2(1072, 6)
	add_child(zoom_bar)
	for pair: Array in [["−", 1.0 / stage.ZOOM_STEP], ["＋", stage.ZOOM_STEP]]:
		var zb := Button.new()
		zb.text = String(pair[0])
		zb.pressed.connect(_on_zoom.bind(float(pair[1])))
		zoom_bar.add_child(UiKit.touchable(zb))
	_zoom_button = Button.new()
	# 倍率印在「全景」鈕上，不另給一個標籤——底欄與建造欄都沒有空位了，
	# 而「現在幾倍」與「回到全景」本來就是同一件事的兩面。
	_zoom_button.pressed.connect(_on_zoom_reset)
	zoom_bar.add_child(UiKit.touchable(_zoom_button))
	refresh_zoom()

	# 間距 2 而不是 4：B1.1 起建造欄有 10 種節點＋3 個模式鈕，44px 的觸控高度
	# （手機移植前提，不能縮）乘 13 已經吃掉 572px，只剩間距可以讓。
	#
	# ★ B2.4.2：那句話在 B2.4 加了三隻角色之後**就不夠了**——13 種把「加粗／拆除」
	#   推到和底欄疊在一起，「藍圖」整顆掉出畫面（RG-139），而**全收集的玩家打無盡
	#   就是 13 種**。所以建造清單改裝進捲動容器，模式鈕釘在它下面。
	#
	#   為什麼是捲動而不是「壓矮一點」或「排兩欄」：44px 是手機移植的硬底線
	#   （P2，不能縮），兩欄在 112px 欄寬裡塞不下「回收者」三個字。而真正的理由是
	#   **這條清單還要再長一倍**——`10_GDD.md` §5 的 M3 內容矩陣是 24 隻角色，
	#   加 5 種生產節點就是 29 顆鈕。任何「剛好排得下」的方案都只是把同一個 bug
	#   往後推一批。
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
	# ★ B3.7.1：允許「按一下選、再按一下取消」（使用者指定）。`ButtonGroup` 預設
	#   永遠有一顆是按下的——那對模式是對的（總得在某個模式裡），對「手上拿著誰」
	#   不對：玩家常常只是想看一下地圖，而不是隨時都握著一種節點。
	group.allow_unpress = true
	# ★ 只列**這一關解鎖的**（`10_GDD.md` §7.9）。第 1 關給四顆鈕不是十顆——
	#   十顆對一個還不知道「電是流率」的人來說不是自由，是雜訊。
	#   一局之內這份清單不會變，所以鈕的位置仍然是固定的（R-15 的同一條理由）。
	buildbar.build_scroll = ScrollContainer.new()
	buildbar.build_scroll.custom_minimum_size = Vector2(112, BUILD_LIST_H)
	buildbar.build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(buildbar.build_scroll)
	var list := UiKit.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buildbar.build_scroll.add_child(list)

	# ★ 生產／防線分段（B2.4.2）。**兩段不是排版，是這一欄的整句話**——
	#   優先權面板為了同一件事特地做了雙欄（`NodeDefs.PRIORITY_SPLIT`），
	#   而建造欄是玩家做**同一個決定**的地方（這 40 礦砂餵產線還是餵防線）。
	#   分段同時讓捲動清單找得到東西：29 顆一模一樣的鈕捲起來是找不到路的。
	# ★ **自己排序，不假設 `_buildable()` 已經是生產在前**（B2.4.2 code review 抓到）。
	#   那份清單是各關在 `data/Campaign.gd` 手寫的，目前碰巧都是生產在前——
	#   而「碰巧」不是不變量。有一關把塔寫在採集器前面時，那顆採集器會安靜地
	#   歸到「防線」那一段，畫面看起來完全正常。
	var ordered: Array[String] = []
	for pass_towers: bool in [false, true]:
		for type: String in buildbar.buildable():
			if bool(NodeDefs.of(type).get("tower", false)) == pass_towers:
				ordered.append(type)
	var seen_tower := false
	for type: String in ordered:
		var is_tower: bool = bool(NodeDefs.of(type).get("tower", false))
		if not seen_tower and is_tower:
			seen_tower = true
			list.add_child(buildbar.section_label("防線"))
		elif not seen_tower and list.get_child_count() == 0:
			list.add_child(buildbar.section_label("生產"))
		# TL_NAKED 連造價都遮：它的語意是「隱藏所有數值標籤」，不是「隱藏狀態數值」。
		# 鈕上**只有名字**（使用者指定，B1.3.1）：價牌在提示列的第一行，
		# 而滑鼠移到鈕上時圖鑑浮層也會寫一次。同一個數字印三遍只是把鈕撐長。
		var b := buildbar.tool_button(group, NodeDefs.label(type))
		# ★ B3.7.1：接 `toggled` 不是 `pressed`（使用者指定「再按一下就是取消選擇」）。
		#   `pressed` 收不到「這一顆剛被放開」——那正是取消選擇要聽的事件。
		b.toggled.connect(buildbar.on_build_type.bind(type))
		# ★ 角色簡介：滑鼠停在鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
		b.mouse_entered.connect(codexpanel.on_codex_show.bind(type, b))
		b.mouse_exited.connect(codexpanel.on_codex_hide)
		buildbar.build_buttons[type] = b
		list.add_child(UiKit.touchable(b))
	# ★ B3.7.1：`_build_type` 可以是空字串（手上什麼都沒拿），而空字串沒有對應的鈕。
	#   索引不到會丟執行期錯誤 → **中止整支 `_build_ui()`**，症狀是「半個畫面沒建出來」
	#   而不是報錯（RG-164 的形狀）。
	if buildbar.build_buttons.has(build_type):
		(buildbar.build_buttons[build_type] as Button).button_pressed = true

	col.add_child(buildbar.spacer(4))
	# ★ 動作鈕只剩一顆（B3.7.1，使用者指定）。歷次拿掉的理由是同一條：
	#   **一個模式鈕如果只是「同一件事的比較慢的做法」，它就該消失。**
	#   「連線」B1.6.2 被拖曳取代；「移動」B1.3.1 改中鍵拖；
	#   「升級」「拆除」B3.7 被檢視面板上的鈕取代——切模式 → 點目標 → 切回建造，
	#   三步裡有兩步不是決定。
	#   藍圖留著：它不是動詞，是**手上拿著的東西**，沒有別的地方表達得了。
	var bp_btn_mode := buildbar.tool_button(group, "藍圖")
	bp_btn_mode.toggled.connect(buildbar.on_mode.bind(Mode.BLUEPRINT))
	buildbar.mode_buttons[Mode.BLUEPRINT] = bp_btn_mode
	col.add_child(UiKit.touchable(bp_btn_mode))

	# 建造欄放不下八種節點再加動作鈕（8×44 已經吃掉 380px），
	# 所以時間流與面板開關搬到地圖下緣那條 56px 的空帶——那裡本來就空著。
	# ★ 三群（B2.4.4，§7.2 B-5）：**時間流｜浮層開關｜說明**。
	#   群間 24、群內 8（§1.3 間距階），**不加分隔線**——七顆同權重的鈕裡有一顆
	#   是不可逆的，而視覺重量要對應後果的重量。
	var bar := UiKit.hbox(24)
	bar.position = Vector2(8, BAR_Y)
	add_child(bar)
	var g_time := UiKit.hbox(8)
	var g_panels := UiKit.hbox(8)
	var g_help := UiKit.hbox(8)
	bar.add_child(g_time)
	bar.add_child(g_panels)
	bar.add_child(g_help)
	topbar.ff_button = Button.new()
	topbar.ff_button.text = "快進 4×"
	topbar.ff_button.pressed.connect(topbar.on_fast_forward)
	g_time.add_child(UiKit.touchable(topbar.ff_button))
	topbar.summon_button = Button.new()
	topbar.summon_button.pressed.connect(topbar.on_summon_now)
	# ★ **全底欄唯一一顆不可逆的鈕**：按下去這一波就提早來，獎勵倍率也定了。
	#   §7.2 B-5 原本開的處方是 `energy.amber` 描邊——**那違反 §1.1 配色紀律 2**
	#   （琥珀專屬於能量，而提前召喚跟耗能無關）。改用 `warn.orange`：紀律 1 說
	#   橙／品紅專屬於「敵人與危險狀態」，而這顆鈕做的事**就是把敵潮叫過來**，
	#   它是玩家自己選的危險。同一條紀律，剛好也是更強的編碼。
	topbar.summon_button.add_theme_color_override("font_color", Palette.WARN_ORANGE)
	topbar.summon_button.add_theme_color_override("font_hover_color", Palette.WARN_ORANGE)
	g_time.add_child(UiKit.touchable(topbar.summon_button))
	# 抽屜開關本來就是一個開關：做成 toggle，按下狀態才**真的**等於「抽屜開著」。
	# 之前是普通按鈕，它拿到焦點時的外框看起來就像被選中，玩家會以為抽屜開了。
	var prio := Button.new()
	prio.text = "優先權"  # 底欄六個鈕，字都壓到最短——提示列要留得下兩行字

	prio.toggle_mode = true
	prio.toggled.connect(priopanel.on_toggle_priority)
	g_panels.add_child(UiKit.touchable(prio))
	# ★ 藍圖庫（B2.3）。放底欄抽屜而不是左欄：左欄的八種節點加動作鈕已經
	#   吃掉 380px，而藍圖是**每局用一兩次**的東西，不該和每秒都在點的建造欄搶位置。
	var bp_btn := Button.new()
	bp_btn.text = "藍圖"
	bp_btn.toggle_mode = true
	bp_btn.toggled.connect(bppanel.on_toggle_blueprint)
	g_panels.add_child(UiKit.touchable(bp_btn))
	helppanel.help_button = Button.new()
	helppanel.help_button.text = "說明"
	helppanel.help_button.toggle_mode = true
	helppanel.help_button.toggled.connect(helppanel.on_toggle_help)

	energypanel.energy_button = Button.new()
	energypanel.energy_button.text = "能量"
	energypanel.energy_button.toggle_mode = true
	energypanel.energy_button.toggled.connect(energypanel.on_toggle_energy)
	g_panels.add_child(UiKit.touchable(energypanel.energy_button))
	codexpanel.codex_button = Button.new()
	codexpanel.codex_button.text = "圖鑑"
	codexpanel.codex_button.toggle_mode = true
	codexpanel.codex_button.button_pressed = true   # 預設開：它只在滑鼠停在建造鈕上時才出現
	codexpanel.codex_button.toggled.connect(func(on: bool) -> void: codexpanel.codex_on = on)
	g_panels.add_child(UiKit.touchable(codexpanel.codex_button))
	# 說明自己一群：它是唯一一顆**跟局面無關**的鈕（不改狀態、不開資料浮層）。
	g_help.add_child(UiKit.touchable(helppanel.help_button))

	priopanel.build_priority_panel()
	bppanel.build_blueprint_panel()
	energypanel.build_energy_panel()
	codexpanel.build_codex_panel()
	inspector.build_inspect_panel()
	helppanel.build_help_panel()

	# 兩行：上行「下一步」、下行當下動作的細節。
	#
	# ★ x **跟著底欄實際的右緣走**，不是一個寫死的 520（B2.9）。原本是寫死的，
	#   而 B2.9 給按鈕套上美術 token（`content_margin` 12/8）之後每一顆鈕都變寬了
	#   ——七顆鈕加起來超過 520，提示文字當場被壓在「說明」那顆鈕上面。
	#   寫死的座標就是這樣壞的：它記的是**當時**那七顆鈕有多寬。
	#   （這也是手機預留條款 P1「不硬編碼像素位置」在這一行的兌現。）
	hintbar.hint = UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
	hintbar.hint.position = Vector2(520, 666)
	hintbar.hint.size = Vector2(755, 50)
	add_child(hintbar.hint)
	bar.resized.connect(hintbar.place_hint.bind(bar))
	hintbar.place_hint.call_deferred(bar)
	hintbar.refresh_hint()


func restart() -> void:
	# ★ 四個模組（舞台、覆蓋層…）跟著這個畫面活到最後，**只有 HUD 要重建**。
	#   B3.13 到這裡為止是 `get_children()` 全部 `queue_free()`——包括舞台底下的地貌層，
	#   而 `_terrain_id` 沒變，重來之後不會重建它：**按「立刻重來」之後地貌整層消失**。
	#   十二條自檢與三十二張截圖都沒有走過這條路。
	for c: Node in get_children():
		if c in _modules():
			continue
		c.queue_free()
	# 選單／設定浮層是 `get_children()` 的一員，上面那圈已經把它們清掉了；
	# 這裡要跟著把手上的參照放掉，否則下一次 ESC 會以為選單還開著。
	menulayer.menu_layer = null
	menulayer.settings_layer = null
	menulayer.menu_button = null
	menulayer.menu_buttons.clear()
	resultpanel.over_panel = null
	topbar.top = null
	# 這兩個陣列裝的是已經 `queue_free()` 掉的 Label——不清就會拿到斷裂的參照。
	topbar.top_values.clear()
	topbar.top_notes.clear()
	hintbar.hint = null
	topbar.ff_button = null
	topbar.summon_button = null
	priopanel.prio_panel = null
	bppanel.bp_panel = null
	helppanel.help_panel = null
	helppanel.help_button = null
	energypanel.energy_panel = null
	energypanel.energy_button = null
	codexpanel.codex_panel = null
	codexpanel.codex_button = null
	codexpanel.codex_label = null
	_zoom_button = null
	energypanel.energy_rows.clear()
	priopanel.prio_labels.clear()
	buildbar.mode_buttons.clear()
	buildbar.build_buttons.clear()
	mode = Mode.BUILD
	build_type = "extractor"
	# 選取要跟著局一起歸零。**`_sel_wire` 存的是 id，而新的一局的 id 從頭發**——
	# 不清的話重開一關會看到面板指著一條玩家沒選過的線（B3.7）。
	selected = Vector2i(-1, -1)
	sel_wire = -1
	s = SessionState.new()
	_bind_session()
	_setup_session()
	accum = 0.0
	message = ""
	_build_ui()
