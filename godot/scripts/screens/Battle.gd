extends Control
## 局內畫面（`10_GDD.md` §6.2：**全畫面地圖 ＋ 浮層**，不是三欄式）。
##
## B0.3 只做「建造與地圖」需要的部分：地圖繪製、四種建造模式、頂欄供需。
## 真正的 HUD（三態徽章、能量列脈動、提前召喚、局末結算）是 B0.6；
## 敵人與波次是 B0.4。**這一批要證明的是：線會亮、線會滿載、加粗會變粗。**

const Loadout := preload("res://scripts/sim/Loadout.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const MapsData := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Score := preload("res://scripts/sim/Score.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const Tech := preload("res://data/Tech.gd")
const RosterData := preload("res://data/Roster.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const SettingsScreen := preload("res://scripts/screens/Settings.gd")
const Stage := preload("res://scripts/screens/battle/Stage.gd")
const Stage2D := preload("res://scripts/screens/battle/Stage2D.gd")
const Overlay2D := preload("res://scripts/screens/battle/Overlay2D.gd")
const Feedback := preload("res://scripts/screens/battle/Feedback.gd")
const SelfTest := preload("res://scripts/screens/battle/SelfTest.gd")

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

## `10_GDD.md` §7.1。**只在準備期可用。**
const FAST_FORWARD_RATE := 4

## 能量收支面板的**固定列序**。列數與順序恆定，沒有值的列留在原位變暗，
## 面板才不會每個 tick 抖一次（B0.7.4）。`short0..2` 是餵不飽的節點清單。
const ENERGY_ROWS := [
	"gen", "silo_out", "reclaim", "sep1", "tower", "smelt", "silo_in", "silo_store", "sep2", "net",
	"short0", "short1", "short2", "tip", "tip2",
]

## 「餵不飽」最多列幾座，其餘收成一行「…還有 N 座」。
const SHORT_ROWS := 3

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

## ★ 局內畫面拆成四個模組（`screens/battle/`），各自是這個節點的子節點。
## 畫面層自己只留：局的建立、每幀的節拍、輸入、HUD。
var stage: Stage = null
var overlay: Overlay2D = null
var feedback: Feedback = null
var selftest: SelfTest = null

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

var _bp_panel: PanelContainer = null

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
var _sel_wire: int = -1

## 游標的**格為單位浮點座標**。命中導管要靠它（格解析度分不出「壓在線上」）。
var hover_p: Vector2 = Vector2(-999, -999)

var accum: float = 0.0

var _message: String = ""

## 頂欄六欄的版面（B2.4.4，§7.2 的 B-2 ＋ B-3）。
##
## 每一欄 ＝ `[標籤 sm] [數值 vs 級·固定寬·右對齊] [註腳 sm·固定寬·右對齊]`。
##
## **三階不是為了好看，是為了回答不同的問題**（§7.2 B-2）：
##   · 主（22 ＝ `text.lg`）＝**能量／波次／核心**——「我現在會不會輸」的全部答案
##   · 次（16 ＝ `text.base`）＝礦砂、合金——「我買不買得起」
##   · 附屬（13 ＝ `text.sm`）＝`▲/秒`、儲槽、交戰、擊殺——上面那幾個的**註腳**
##
## **固定寬度是 §3 那條硬性要求的正解**（「資源數字跳動時不得左右位移」）。
## ⚠ 原稿說要開 OpenType `tnum`——**量過之後那是修一個不存在的問題**：微軟正黑體
## 的數字本來就等寬，同位數換數字（1111→8888）本來就不位移。真正會位移的是
## **跨位數**（999→1000），而 `tnum` 對它無效，只有固定寬度擋得住。
## 量測留在 `_topbar_selftest()`，兩種情況各一條斷言。
##
## 寬度是**猜的，然後由 `bar_clear` 驗**（頂欄不得長到撞上縮放鈕）。固定寬度讓
## 那條斷言從「這一刻的數值排得下」升級成「任何數值都排得下」。
##
## ★ **從七欄縮成五欄**：三階字級排不下 11 個數字（第一版實測超出 166px），
##   而 §2 反模式清單自己就寫著「每個畫面最多 4 個『主要數字』」。
##   **搬家不是刪除**（B-2 說資訊完備性不能砍）：
##     · 儲槽存量 → 能量面板（它是「充放電」那兩列的分母），地圖上每顆儲槽
##       身上還有一圈琥珀弧，「哪一顆滿了」讀得到
##     · 交戰座數 → 併進能量那一格的註腳（它就是能量需求的解釋）
##     · 擊殺 → 併進波次那一格的註腳（兩個都在講「這一波打得怎樣」）
const TOP_CELLS := [
	{"tag": "礦砂", "vw": 64, "vs": 16, "nw": 48},
	{"tag": "合金", "vw": 56, "vs": 16, "nw": 48},
	{"tag": "能量", "vw": 88, "vs": 22, "nw": 72},
	{"tag": "",     "vw": 144, "vs": 22, "nw": 120},
	{"tag": "核心", "vw": 116, "vs": 22, "nw": 0},
]

var _top: HBoxContainer = null

## 頂欄每一欄的數值／註腳標籤。**存參照而不是每次 `get_child(i).get_child(j)`**
## ——那種索引在版面改一次就會安靜地指到別格（RG-134 是同一個錯法的按鈕版）。
var _top_values: Array[Label] = []

var _top_notes: Array[Label] = []

var _hint: Label = null

var _mode_buttons: Dictionary = {}

var _build_buttons: Dictionary = {}

## 建造清單的捲動容器（B2.4.2）。模式鈕釘在它**下面**，所以清單再長也推不動它們。
var _build_scroll: ScrollContainer = null

var _ff_button: Button = null

var _summon_button: Button = null

var _over_panel: Control = null

var _prio_panel: Control = null

var _help_panel: Control = null

var _help_button: Button = null

var _energy_panel: Control = null

var _energy_button: Button = null

var _energy_rows: Dictionary = {}

var _codex_button: Button = null

var _codex_panel: Control = null

var _inspect_panel: Control = null

var _inspect_label: Label = null

## ★ 檢視面板上的兩顆動詞鈕（B3.7）。升級／加粗共用一顆——選的是什麼就升什麼。
var _inspect_up: Button = null

var _inspect_del: Button = null

var _codex_label: Label = null

var _codex_on: bool = true

var _prio_labels: Dictionary = {}

## 局內選單（ESC 或左上角「選單」鈕）。`null` ＝ 沒開。
var _menu_layer: Control = null

var _menu_button: Button = null

var _menu_buttons: Array[Button] = []

## 從局內選單開出來的設定浮層。開著時 ESC 由它自己處理（回到選單）。
var _settings_layer: Control = null


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


## 建立並接上四個模組（`screens/battle/`）。
##
## **加入的順序有意義**：子節點依加入順序繪圖，後加的在上面——舞台在最底、覆蓋層次之，
## HUD（`_build_ui()` 之後才加）在最上面。`_restart()` 只重建 HUD，不動這四個。
func _build_modules() -> void:
	stage = Stage2D.new()
	overlay = Overlay2D.new()
	feedback = Feedback.new()
	selftest = SelfTest.new()
	for m: Node in _modules():
		m.scr = self
	overlay.stage = stage
	selftest.stage = stage
	selftest.overlay = overlay
	selftest.feedback = feedback
	_bind_session()
	for m: Node in _modules():
		add_child(m)


func _modules() -> Array[Node]:
	return [stage, overlay, feedback, selftest]


## 把這一局的 `s` 交給四個模組。**每次 `s = SessionState.new()` 之後都要呼叫**——
## 模組各持一份引用（繪圖迴圈裡每次 `scr.s` 的查詢成本不值得），漏掉一次它們就停在上一局。
func _bind_session() -> void:
	for m: Node in _modules():
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


## 這一局蓋得出哪些節點。**空的 `unlocked` ＝ 全部**（測試圖與沙盤）。
##
## ★ B2.4 之後「全部」包含招募專屬的三隻，而測試圖與沙盤**刻意不吃名冊**：
## 那兩張圖是開發用的（主選單上寫著「測試圖」），要驗的是節點本身而不是進度。
## 真正的入口各自明講自己要什麼——戰役問關卡（§7.9）、無盡與自由榜問名冊、
## 統一榜走 `Daily.UNIFORM_BUILD`。**沒有一條路是靠這個預設值決定的。**
func _buildable() -> Array:
	var unlocked: Array = s.sets.get("unlocked", [])
	return NodeDefs.BUILDABLE if unlocked.is_empty() else unlocked


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
	_refresh_top()
	# 提示列每幀重算：它講的是**當前狀態**下的下一步，而狀態每 tick 都在變。
	# B0.7 之前它只在滑鼠移動時更新，於是「礦砂開始入帳了」「波次開打了」這類
	# 轉折要等玩家碰一下滑鼠才會反映——手不動的那幾秒，提示列是在說謊。
	_refresh_hint()
	_refresh_energy()
	# 檢視面板講的是**當下這個 tick** 的耗能與供電來源，所以它也要每幀重算。
	_refresh_inspect()
	_refresh_over()
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
			_refresh_hint()
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
		_refresh_hint()
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
			_select_wire(int((s.conduits[wi])["id"]))
			_refresh_hint()
			redraw()
			return
	_act(c)
	_refresh_hint()


## 左鍵放開。只有「按下時停在某個節點上」的那條路徑會走到這裡。
func _release(pos: Vector2) -> void:
	if bp_from.x >= 0:
		var from_bp := bp_from
		bp_from = Vector2i(-1, -1)
		_save_blueprint(from_bp, stage.cell_at(pos))
		_refresh_hint()
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
		_message = _text_of(code)
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
		_sel_wire = -1
		_refresh_inspect()
		_message = "" if selected.x >= 0 else "從這個節點按住往另一個節點拖，就能拉一條導管。"
	_refresh_hint()
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
				_expand_blueprint(cell)
				return
			# 蓋在空地上就取消選取：選取講的是「這一座」，而畫面已經換人了。
			selected = Vector2i(-1, -1)
			_sel_wire = -1
			_refresh_inspect()
			# ★ B3.7.1：手上什麼都沒拿（再按一次建造鈕就會這樣）＝點空地什麼都不做。
			#   不報錯——「我只是想收起面板」和「我蓋錯地方了」不是同一件事，
			#   對前者丟一句 ✕ 是把一個正常操作講成失敗。
			if build_type == "":
				_message = ""
				return
			var code_b := BuildController.place(s, build_type, cell)
			if code_b == Build.OK:
				AudioBus.play("build_place")
			_message = _text_of(code_b)


func _text_of(code: String) -> String:
	return "✔ 完成" if code == Build.OK else "✕ " + BuildController.reason_text(code)


func _label_at(cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	return NodeDefs.label(String(n["type"])) if not n.is_empty() else "空地"


# ── 浮層 ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# ★ 頂欄三階 ＋ 固定寬度（B2.4.4）。舊版是七個 15px（**階外**）的 Label 直接
	#   丟進 HBox——11 個數字同一階，而且寬度隨數值變。規格見 `TOP_CELLS`。
	_top = UiKit.hbox(8)
	_top.position = Vector2(120, 12)
	add_child(_top)
	_top_values.clear()
	_top_notes.clear()
	for spec: Dictionary in TOP_CELLS:
		var cell := UiKit.hbox(4)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		if String(spec["tag"]) != "":
			cell.add_child(UiKit.label(String(spec["tag"]), 13, Palette.TEXT_SECONDARY, false))
		var v := UiKit.label("", int(spec["vs"]), Palette.TEXT_PRIMARY, false)
		v.custom_minimum_size.x = float(spec["vw"])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(v)
		_top_values.append(v)
		var n := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		n.custom_minimum_size.x = float(spec["nw"])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(n)
		_top_notes.append(n)
		_top.add_child(cell)

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
	_build_scroll = ScrollContainer.new()
	_build_scroll.custom_minimum_size = Vector2(112, BUILD_LIST_H)
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_build_scroll)
	var list := UiKit.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_scroll.add_child(list)

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
		for type: String in _buildable():
			if bool(NodeDefs.of(type).get("tower", false)) == pass_towers:
				ordered.append(type)
	var seen_tower := false
	for type: String in ordered:
		var is_tower: bool = bool(NodeDefs.of(type).get("tower", false))
		if not seen_tower and is_tower:
			seen_tower = true
			list.add_child(_section_label("防線"))
		elif not seen_tower and list.get_child_count() == 0:
			list.add_child(_section_label("生產"))
		# TL_NAKED 連造價都遮：它的語意是「隱藏所有數值標籤」，不是「隱藏狀態數值」。
		# 鈕上**只有名字**（使用者指定，B1.3.1）：價牌在提示列的第一行，
		# 而滑鼠移到鈕上時圖鑑浮層也會寫一次。同一個數字印三遍只是把鈕撐長。
		var b := _tool_button(group, NodeDefs.label(type))
		# ★ B3.7.1：接 `toggled` 不是 `pressed`（使用者指定「再按一下就是取消選擇」）。
		#   `pressed` 收不到「這一顆剛被放開」——那正是取消選擇要聽的事件。
		b.toggled.connect(_on_build_type.bind(type))
		# ★ 角色簡介：滑鼠停在鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
		b.mouse_entered.connect(_on_codex_show.bind(type, b))
		b.mouse_exited.connect(_on_codex_hide)
		_build_buttons[type] = b
		list.add_child(UiKit.touchable(b))
	# ★ B3.7.1：`_build_type` 可以是空字串（手上什麼都沒拿），而空字串沒有對應的鈕。
	#   索引不到會丟執行期錯誤 → **中止整支 `_build_ui()`**，症狀是「半個畫面沒建出來」
	#   而不是報錯（RG-164 的形狀）。
	if _build_buttons.has(build_type):
		(_build_buttons[build_type] as Button).button_pressed = true

	col.add_child(_spacer(4))
	# ★ 動作鈕只剩一顆（B3.7.1，使用者指定）。歷次拿掉的理由是同一條：
	#   **一個模式鈕如果只是「同一件事的比較慢的做法」，它就該消失。**
	#   「連線」B1.6.2 被拖曳取代；「移動」B1.3.1 改中鍵拖；
	#   「升級」「拆除」B3.7 被檢視面板上的鈕取代——切模式 → 點目標 → 切回建造，
	#   三步裡有兩步不是決定。
	#   藍圖留著：它不是動詞，是**手上拿著的東西**，沒有別的地方表達得了。
	var bp_btn_mode := _tool_button(group, "藍圖")
	bp_btn_mode.toggled.connect(_on_mode.bind(Mode.BLUEPRINT))
	_mode_buttons[Mode.BLUEPRINT] = bp_btn_mode
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
	_ff_button = Button.new()
	_ff_button.text = "快進 4×"
	_ff_button.pressed.connect(_on_fast_forward)
	g_time.add_child(UiKit.touchable(_ff_button))
	_summon_button = Button.new()
	_summon_button.pressed.connect(_on_summon_now)
	# ★ **全底欄唯一一顆不可逆的鈕**：按下去這一波就提早來，獎勵倍率也定了。
	#   §7.2 B-5 原本開的處方是 `energy.amber` 描邊——**那違反 §1.1 配色紀律 2**
	#   （琥珀專屬於能量，而提前召喚跟耗能無關）。改用 `warn.orange`：紀律 1 說
	#   橙／品紅專屬於「敵人與危險狀態」，而這顆鈕做的事**就是把敵潮叫過來**，
	#   它是玩家自己選的危險。同一條紀律，剛好也是更強的編碼。
	_summon_button.add_theme_color_override("font_color", Palette.WARN_ORANGE)
	_summon_button.add_theme_color_override("font_hover_color", Palette.WARN_ORANGE)
	g_time.add_child(UiKit.touchable(_summon_button))
	# 抽屜開關本來就是一個開關：做成 toggle，按下狀態才**真的**等於「抽屜開著」。
	# 之前是普通按鈕，它拿到焦點時的外框看起來就像被選中，玩家會以為抽屜開了。
	var prio := Button.new()
	prio.text = "優先權"  # 底欄六個鈕，字都壓到最短——提示列要留得下兩行字

	prio.toggle_mode = true
	prio.toggled.connect(_on_toggle_priority)
	g_panels.add_child(UiKit.touchable(prio))
	# ★ 藍圖庫（B2.3）。放底欄抽屜而不是左欄：左欄的八種節點加動作鈕已經
	#   吃掉 380px，而藍圖是**每局用一兩次**的東西，不該和每秒都在點的建造欄搶位置。
	var bp_btn := Button.new()
	bp_btn.text = "藍圖"
	bp_btn.toggle_mode = true
	bp_btn.toggled.connect(_on_toggle_blueprint)
	g_panels.add_child(UiKit.touchable(bp_btn))
	_help_button = Button.new()
	_help_button.text = "說明"
	_help_button.toggle_mode = true
	_help_button.toggled.connect(_on_toggle_help)

	_energy_button = Button.new()
	_energy_button.text = "能量"
	_energy_button.toggle_mode = true
	_energy_button.toggled.connect(_on_toggle_energy)
	g_panels.add_child(UiKit.touchable(_energy_button))
	_codex_button = Button.new()
	_codex_button.text = "圖鑑"
	_codex_button.toggle_mode = true
	_codex_button.button_pressed = true   # 預設開：它只在滑鼠停在建造鈕上時才出現
	_codex_button.toggled.connect(func(on: bool) -> void: _codex_on = on)
	g_panels.add_child(UiKit.touchable(_codex_button))
	# 說明自己一群：它是唯一一顆**跟局面無關**的鈕（不改狀態、不開資料浮層）。
	g_help.add_child(UiKit.touchable(_help_button))

	_build_priority_panel()
	_build_blueprint_panel()
	_build_energy_panel()
	_build_codex_panel()
	_build_inspect_panel()
	_build_help_panel()

	# 兩行：上行「下一步」、下行當下動作的細節。
	#
	# ★ x **跟著底欄實際的右緣走**，不是一個寫死的 520（B2.9）。原本是寫死的，
	#   而 B2.9 給按鈕套上美術 token（`content_margin` 12/8）之後每一顆鈕都變寬了
	#   ——七顆鈕加起來超過 520，提示文字當場被壓在「說明」那顆鈕上面。
	#   寫死的座標就是這樣壞的：它記的是**當時**那七顆鈕有多寬。
	#   （這也是手機預留條款 P1「不硬編碼像素位置」在這一行的兌現。）
	_hint = UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
	_hint.position = Vector2(520, 666)
	_hint.size = Vector2(755, 50)
	add_child(_hint)
	bar.resized.connect(_place_hint.bind(bar))
	_place_hint.call_deferred(bar)
	_refresh_hint()


## 提示文字擺在底欄右邊 24px（§1.3 間距階的群間距，同底欄自己的三群）。
## 底欄是容器，它的寬度要到版面跑完才知道——所以走 `resized` 而不是算一次。
func _place_hint(bar: Control) -> void:
	if _hint == null or not is_instance_valid(bar):
		return
	_hint.position.x = bar.position.x + bar.size.x + 24.0
	_hint.size.x = maxf(120.0, float(size.x) - _hint.position.x - 8.0)


## ★ 依**節點類型**的優先權面板（`10_GDD.md` §3.1）。
##
## 三件事是設計鎖死的，不要「順手」改掉：
##   ① **列固定、順序固定**（`NodeDefs.PRIORITY_ROWS`）——不可暫停的戰術動作
##      必須是一個手勢；滑桿會跑位就不是手勢了。
##   ② **沒有「每一座」的選項**——操作負擔不得隨建築數量成長（風險 R-1）。
##   ③ 預設收合。它是抽屜不是常駐欄（§6.2 全畫面地圖 ＋ 可收合浮層）。
## ★ 藍圖抽屜（B2.3）。位置在畫面左中——優先權面板在 (128, 380)、
## 能量面板在右上、提示列在底邊，這一塊是剩下唯一放得下一張清單的地方。
func _build_blueprint_panel() -> void:
	var box := UiKit.panel()
	# 位置是**擠出來的**，不是挑出來的：優先權面板佔 128..510、能量面板佔
	# 872..1264、圖鑑浮層下緣到 320、提示列從 660 起——中間這一塊是唯一
	# 能讓三張浮層同時開又互不相疊的地方。
	# 第一版放 (128, 150)，於是被圖鑑整個蓋住（截圖抓到，文字從圖鑑後面透出來）。
	box.position = Vector2(560, 400)
	box.visible = false
	box.add_child(UiKit.vbox(4))
	add_child(box)
	_bp_panel = box
	_refresh_blueprints()


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
	outer.add_child(UiKit.label("能量／礦砂不足時，誰先餓死", 13, Palette.TEXT_SECONDARY, false))
	var cols := UiKit.hbox(10)
	outer.add_child(cols)
	var lanes := [UiKit.vbox(4), UiKit.vbox(4)]
	cols.add_child(lanes[0])
	cols.add_child(lanes[1])
	# ★ 只列這一關蓋得出來的（核心永遠在，它不是玩家蓋的）。B1.2 起前幾關
	#   只解鎖四到六種節點，把另外五條永遠用不到的滑桿也列出來，就是把
	#   「這一格是我的戰術決定」稀釋成「這一排我看不懂」。**一局之內清單不變**，
	#   所以滑桿仍然恆在同一位置（R-1／R-15 要保的是那一件事）。
	# ★ 一列＝一個**角色的角色**，不是一個資料表的鍵（`NodeDefs.PRIORITY_GROUP`，
	#   B2.4）。長哨與定潮併進「錨」那一列、霜礁併進「潮鳴」那一列，所以滑桿數
	#   永遠是這九條的子集——M3 的 24 隻角色也不會讓這個面板長成一份表單（R-1）。
	var rows: Array = []
	for type: String in NodeDefs.PRIORITY_ROWS:
		if type == "core":
			rows.append(type)
			continue
		for member: String in NodeDefs.priority_members(type):
			if _buildable().has(member):
				rows.append(type)
				break
	var split := 0
	for type: String in rows:
		if NodeDefs.PRIORITY_ROWS.find(type) < NodeDefs.PRIORITY_SPLIT:
			split += 1
	for i in rows.size():
		var type := String(rows[i])
		var row := UiKit.hbox(4)
		var name_label := UiKit.label(NodeDefs.label(type), 13, Palette.TEXT_PRIMARY, false)
		name_label.custom_minimum_size = Vector2(52, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		var down := Button.new()
		down.text = "◀"
		down.pressed.connect(_on_priority.bind(type, -1))
		row.add_child(UiKit.touchable(down))
		var value := UiKit.label("", 16, Palette.ENERGY_AMBER)
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
		return "　導管不能跨過敵人路徑（紫帶）。這張圖沒有橋，所有東西都在同一側"
	return "　導管要過敵人路徑（紫帶）只能走「橋」，也就是路徑上那 %d 段架高結構" % n


func _build_help_panel() -> void:
	var box := UiKit.panel(0.94)
	box.position = Vector2(150, 250)
	var col := UiKit.vbox(3)
	box.add_child(col)
	for line: String in [
		"操作　左鍵做事、中鍵移動視野、滾輪縮放、ESC 開選單",
		"　蓋節點：左欄選一種 → 左鍵點地圖上的一格",
		"　拉導管：從一個節點按住左鍵，拖到另一個節點放開（隨時都能拖）",
		"　檢　視：左鍵點一座建築或一條導管 → 右邊出現它的數據，升級與拆除也在那個面板上",
		"　　　　　升級：每一級加的東西不同，耗能一律 +25%／級，上限 5 級，隨局結束消失｜拆除返還 75%",
		"　取　消：再點一次同一個東西＝收起面板；再按一次左欄的節點鈕＝放下手上那一種",
		"　移　動：按住滑鼠中鍵拖動地圖（放大之後才需要）",
		"",
		"規則",
		"　導管只能走 水平／垂直／45°，要轉彎先放一個「中繼」",
		# ★ 座數讀地圖，不寫死（B1.2）：第 1 關一座橋都沒有，跟新手講
		#   「路徑上那三段架高結構」只會讓他去找一個畫面上不存在的東西。
		_bridge_line(),
		"　節點不能蓋在敵人路徑上",
		"　敵人走過時會打壞相鄰 1 格的東西 → 塔與導管退開 2 格就安全",
		"　塔只有交戰時吃電，待機 0",
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
	# ★ **預設不開**（B2.4.7，使用者指定）。原本空地圖時自動彈出，理由是
	#   「這局還沒開始，正是需要它的時刻」——但它整片是文字，蓋在地圖上，
	#   而每一局開頭都會再來一次。提示列（`_hint`）本來就在講下一步，
	#   說明鈕也一直在底欄。**要看的人按得到，不要看的人不必關掉它。**
	box.visible = false
	_help_button.set_pressed_no_signal(false)


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
	col.add_child(UiKit.label("能量收支（每秒）", 16, Palette.ENERGY_AMBER, false))
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
		if stage.engaged.get(int(n["id"]), false):
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
	# ★ 儲槽**存量**（B2.4.4）。它原本掛在頂欄，而頂欄的三階層次容不下 11 個
	#   數字（§2 反模式：每畫面最多 4 個主要數字）。搬到這裡而不是刪掉：
	#   這一格是「充放電」那兩列的分母，放在它們旁邊比放在頂欄更講得通。
	#   ★ **每一顆儲槽自己身上還有一圈琥珀弧**，所以「哪一顆滿了」在地圖上讀得到，
	#     頂欄少的只是那個總和數字。
	_set_row("silo_store", "　　儲槽存量　%.0f/%.0f" % [r["silo_charge"], r["silo_capacity"]],
		float(r["silo_capacity"]) > 0.05, Palette.ENERGY_AMBER)
	_set_row("sep2", "─────────────────", false)

	# ★ 「誰餵不飽」（使用者要求）。淨值只說「差多少」，不說「誰在挨餓」——
	#   而玩家能採取的動作（拉優先權、加粗那條線、多蓋一台發電機）取決於後者。
	#   名單直接取三態徽章的 `STARVED`，與地圖上的橙色倒三角是同一份判定。
	var short_list: Array[String] = []
	var states: Dictionary = r["node_state"]
	for n: Dictionary in s.nodes:
		# ★ `is_starved()` 而不是 `== STARVED`（B2.4.8）：缺料分成礦／電兩態之後，
		#   寫死等號的地方會安靜地漏掉一半的節點——而「安靜地漏掉」正是這一整批
		#   在修的東西。
		if not SessionState.is_starved(int(states.get(int(n["id"]), 0))):
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
	_codex_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 不設寬度的話它會長到最長那一行那麼寬（熔爐那一行 850px），
	#   從 x=124 一路蓋掉 x=870 的能量面板——兩個浮層同時開就疊在一起。
	_codex_label.custom_minimum_size.x = 640.0
	_codex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_codex_label)
	add_child(box)
	_codex_panel = box


## ★ B3.7：面板底下多兩顆鈕（升級／加粗、拆除）。
##
## 動詞跟著**被選中的那個東西**走，不再跟著模式走。原本要動一座塔得先去底欄按
## 「升級」、點它、再按回來——三步裡有兩步不是決定。現在點它就看得到它，
## 而它能做的兩件事就寫在旁邊。
##
## ⚠ `UiKit.panel()` 是 `MOUSE_FILTER_IGNORE`（RG-39：浮層是資訊不是障礙物），
##   但那只管容器自己——Godot 的命中測試照樣會走進子節點，所以鈕收得到點擊，
##   而鈕以外的地方仍然穿透到底下的地圖。
## 檢視面板的固定寬高（B3.9.1）。**位置只能是離散狀態的函式**——見 `_place_inspect`。
## `INSPECT_MAX_H` 是它最高的樣子（導管面板量到 342），只拿來判避讓。
const INSPECT_W := 383.0

const INSPECT_MAX_H := 360.0


func _build_inspect_panel() -> void:
	# ★ B3.7 起用標準不透明度（0.96），不再是角色簡介那種半透明。
	# 半透明的理由是「讓玩家看見底下是什麼」，而這個面板底下不是它要講的東西
	# ——被選取的那一格與供電來源都在畫面另一邊。加了兩顆鈕之後代價更明顯：
	# 節點圖形從字和鈕後面透出來，而**可以按的東西要讀起來是實心的**。
	var box := UiKit.panel()
	box.visible = false
	var col := UiKit.vbox(8)
	# ⚠ **內層容器要一起穿透**。`UiKit.panel()` 自己是 `MOUSE_FILTER_IGNORE`
	#   （RG-39：浮層是資訊不是障礙物），但 `Container` 預設是 `STOP`——面板底下
	#   那一塊地圖於是點不到也拖不動。B3.9.1 把面板挪到畫面中段之後這件事才要緊。
	#   兩顆鈕仍是 `STOP`（它們就是要點的東西）。
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 356 ＝ 量到的最長一行。**不開 autowrap**：這些行是設計成單行的，折行會讓
	#   面板從 258 長到 552，一個蓋住半張地圖的浮層比它要修的位移更糟。
	_inspect_label.custom_minimum_size.x = 356.0
	col.add_child(_inspect_label)
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_up = Button.new()
	_inspect_up.pressed.connect(_on_inspect_upgrade)
	_inspect_del = Button.new()
	_inspect_del.pressed.connect(_on_inspect_demolish)
	for b: Button in [_inspect_up, _inspect_del]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UiKit.touchable(b))
	col.add_child(row)
	box.add_child(col)
	add_child(box)
	_inspect_panel = box


## 被選取那條導管在 `s.conduits` 裡的索引。找不到（被拆了、被敵人啃斷了）回 −1。
##
## 每次都重找而不是記索引——理由寫在 `_sel_wire` 的宣告上。線性掃：一局的導管
## 是幾十條，而這只在玩家選著一條線的那些幀跑。
func sel_wire_index() -> int:
	if _sel_wire < 0:
		return -1
	for i in s.conduits.size():
		if int((s.conduits[i])["id"]) == _sel_wire:
			return i
	return -1


## 選一條導管。再點同一條＝取消（和選節點同一個開關語意）。
func _select_wire(id: int) -> void:
	selected = Vector2i(-1, -1)
	_sel_wire = -1 if _sel_wire == id else id
	_message = ""
	_refresh_inspect()


func _on_inspect_upgrade() -> void:
	var wi := sel_wire_index()
	if wi >= 0:
		var code := BuildController.upgrade(s, wi)
		if code == Build.OK:
			AudioBus.play("build_wire")
		_message = _text_of(code)
	elif selected.x >= 0:
		var code := BuildController.upgrade_node(s, selected)
		if code == Build.OK:
			AudioBus.play("build_place")
		_message = _text_of(code)
	_refresh_inspect()
	_refresh_hint()
	redraw()


func _on_inspect_demolish() -> void:
	var wi := sel_wire_index()
	var code := ""
	if wi >= 0:
		code = BuildController.demolish_conduit(s, wi)
	elif selected.x >= 0:
		code = BuildController.demolish(s, selected)
	else:
		return
	if code == Build.OK:
		AudioBus.play("build_destroyed", -4.0)
		# 拆掉的東西不能繼續選著：面板下一幀就沒有東西可講了。
		selected = Vector2i(-1, -1)
		_sel_wire = -1
	_message = _text_of(code)
	_refresh_inspect()
	_refresh_hint()
	redraw()


## ★ 被選取那一座的**當下數據**（B3.6）。每幀重算——它講的是這個 tick。
##
## 三件事，照玩家問的順序：**這是什麼 → 它現在吃多少電 → 電從哪來。**
## 前兩件是它自己的欄位，第三件要逆著本 tick 的實際流向走（`FlowNetwork.upstream_power()`）。
func _refresh_inspect() -> void:
	if _inspect_panel == null:
		return
	if Hooks.naked:
		_inspect_panel.visible = false
		return
	# 選著的那條線可能已經不在了（自己拆的、或敵人啃斷的）。**在這裡收掉**，
	# 而不是等某個讀 `s.conduits[i]` 的地方越界——那個症狀是整支函式中止（RG-164）。
	var wi := sel_wire_index()
	if _sel_wire >= 0 and wi < 0:
		_sel_wire = -1
	if wi >= 0:
		_refresh_inspect_wire(wi)
		return
	var n: Dictionary = s.node_at(selected) if selected.x >= 0 else {}
	if n.is_empty():
		_inspect_panel.visible = false
		return
	var type := String(n["type"])
	var def := NodeDefs.of(type)
	var lvl := int(n.get("level", 0))
	var scale := Build.node_scale(lvl)
	var lines: Array[String] = []
	lines.append("%s%s" % [NodeDefs.label(type), "　%d 級" % lvl if lvl > 0 else ""])
	lines.append("生命　%d / %d" % [int(n["hp"]), int(NodeDefs.hp(type))])

	# ── 它自己的數據（升級之後要顯示**升過的值**，不是表上的原值）──
	# ★ B3.8：升的是哪一項各問各的（`10_GDD.md` §4.3）。這裡**不能用 `scale`**
	#   ——那是耗能倍率；一座第 2 級加射速的錨，傷害還停在 1 級的值。
	var eff := Build.effect_scale(type, lvl)
	var rng := Build.node_range(type, lvl)
	if rng > 0.0:
		lines.append("射程　%.0f 格" % rng)
	if float(def.get("dmg", 0.0)) > 0.0:
		lines.append("傷害　%.0f × %.1f 發/秒" % [
			float(def["dmg"]) * eff * float(s.mods["damage_mult"]),
			float(def.get("rof", 0.0)) * Build.rof_scale(type, lvl),
		])
	if float(def.get("slow", 0.0)) > 0.0:
		# 光環塔的**全部效果**都在這一行。B3.5 起它一直沒有被級數乘過，而面板
		# 也從來沒有印出來——使用者實玩才發現「潮鳴跟霜礁升級都沒用」（B3.8）。
		lines.append("減速　%d%%%s" % [
			int(round(minf(float(def["slow"]) * eff, Combat.SLOW_MAX) * 100.0)),
			"　破甲 %d%%" % int(round(float(def["armor_break"]) * eff * 100.0))
				if float(def.get("armor_break", 0.0)) > 0.0 else "",
		])
	if Build.splash_radius(type, lvl) > 0.0:
		lines.append("濺射　%.1f 格" % Build.splash_radius(type, lvl))
	if float(def.get("reclaim", 0.0)) > 0.0:
		lines.append("回收　射程內任何死亡的 %d%% 換能量" % int(round(
			float(def["reclaim"]) * eff * 100.0
		)))
	if float(def.get("ore_out", 0.0)) > 0.0:
		lines.append("產出　%.1f 礦砂/秒" % (float(def["ore_out"]) * eff
			* float(s.mods["produce_mult"])))
	if float(def.get("power_out", 0.0)) > 0.0:
		lines.append("發電　%.0f 能量/秒" % (float(def["power_out"]) * eff
			* float(s.mods["produce_mult"])))

	# ── 耗能：**帳面**與**當下**分開講 ──
	# 帳面是「它交戰時會吃多少」，當下是「這個 tick 它真的拿到多少」。
	# 只講一個的話，玩家看不出「它在挨餓」——而那正是他點開這座塔的原因。
	var engage := float(def.get("engage_power", 0.0)) * scale * float(s.mods["engage_mult"])
	var idle := float(def.get("power_in", 0.0)) * scale
	if engage > 0.0 or idle > 0.0:
		# ⚠ **預設值不能是 1.0**。沒接進電網的節點根本不在解算器的表上，
		#   `.get(id, 1.0)` 會把「查無此人」讀成「餵得飽飽的」——
		#   截圖當場抓到面板自相矛盾：上一行寫「餵得 100%」，下一行寫「供電 沒有」。
		#   用 −1 當哨兵，把「沒在表上」和「在表上而且滿足率是 1」分開。
		var sat_raw := float((s.rates["satisfaction"] as Dictionary).get(int(n["id"]), -1.0))
		var wired: bool = sat_raw >= 0.0
		var sat: float = sat_raw if wired else 0.0
		# `.get()` 不是 `.has()`：`_engaged` 是 {id: bool}，沒交戰的塔**鍵也在**，
		# 值才是 false（第 1008 行那條既有斷言用的就是 get）。
		var busy: bool = engage > 0.0 and bool(stage.engaged.get(int(n["id"]), false))
		var draw := (engage if busy else 0.0) + idle
		if engage > 0.0:
			lines.append("交戰耗能　%.1f 能量/秒%s" % [engage, "" if busy else "（待機 0）"])
		if idle > 0.0:
			lines.append("待機耗能　%.1f 能量/秒" % idle)
		if not wired:
			# 和提示列講同一句話——同一件事在兩個地方要有同一個說法。
			lines.append("此刻　沒接進電網，交戰時一發都打不出來")
		else:
			lines.append("此刻　%.1f 能量/秒　餵得 %d%%" % [draw * sat, int(round(sat * 100.0))])

	# ── ★ 電從哪來 ──
	var sources: Dictionary = power_sources()
	var chain := FlowNetwork.upstream_power(s.conduits, energy_net(), selected, sources)
	var feeders: Dictionary = chain["sources"]
	if engage > 0.0 or idle > 0.0:
		# ⚠ 「沒有外部來源」和「在挨餓」**不是同一件事**。回收者靠自己的回收緩衝、
		#   儲槽靠自己的存量，兩者都會出現「一條線都沒有在餵它，而它餵得飽飽的」。
		#   第一版一律寫「沒有——這一刻沒有任何電流進來」，於是面板上一行寫
		#   「餵得 100%」、下一行寫「沒有供電」，讀起來像壞掉了（截圖當場看到）。
		var self_fed: bool = String(n["type"]) in ["reclaimer", "silo"]
		var supply_text := "%d 座（已在地圖上標出）" % feeders.size()
		if feeders.is_empty():
			supply_text = "沒有外部來源，這一刻靠自己的存量" if self_fed 				else "這一刻沒有電流進來"
		lines.append("供電　%s" % supply_text)

	# ── ★ 兩顆動詞鈕（B3.7）──
	# **核心兩顆都關**：它升不得也拆不得（`upgrade_node()`／`demolish()` 都擋著）。
	# 鈕在那裡而按不動，等於邀請玩家去按一個保證失敗的東西。
	if type == "core":
		_show_verbs("", "")
	else:
		# ★ B3.8：鈕上寫**這一級買到的是什麼**。三級各不相同，而玩家在按下去
		#   之前必須知道自己買的是射程還是射速——否則「多元化」對他等於隨機。
		var up := "已滿級" if lvl >= Build.NODE_MAX_LEVEL else "升級　%s　%d 礦砂" % [
			_step_text(Build.next_step(type, lvl)),
			Build.node_upgrade_cost(NodeDefs.cost(type), lvl),
		]
		var refund := BuildController.node_refund(type)
		_show_verbs(up, "拆除　退 %d 礦砂" % refund.x, lvl < Build.NODE_MAX_LEVEL)
	_place_inspect(lines)


## ★ 被選取那條導管的當下數據（B3.7）。
##
## 玩家點一條線要問的是同一組問題，只是主詞換了：**它多粗 → 這一刻擠不擠 →
## 加粗要多少錢**。「擠不擠」是這一批真正要答的——導管滿載在圖上是變色與線寬，
## 那是給掃視用的；點下去要拿得到數字。
func _refresh_inspect_wire(wi: int) -> void:
	var c: Dictionary = s.conduits[wi]
	var lvl := int(c["level"])
	var cap := Build.conduit_cap(lvl, float(s.mods["cap_bonus"]))
	var flow := float((s.rates["conduit_flow"] as Dictionary).get(c["id"], 0.0))
	var lines: Array[String] = []
	lines.append("導管%s" % ("　%d 級" % lvl if lvl > 0 else ""))
	lines.append("生命　%d / 40" % int(c["hp"]))
	lines.append("長度　%d 格" % (Build.conduit_cost(c["a"], c["b"]) / Build.CONDUIT_COST_PER_CELL))
	# 「這一刻擠不擠」：滿載是這條線正在**卡住**它下游的每一個節點。
	lines.append("流量　%.1f / %.0f 每秒%s" % [
		flow, cap, "　已滿載" if flow >= cap - 0.05 else ""
	])
	if lvl < Build.CAP_MAX_LEVEL:
		lines.append("加粗後　%.0f 每秒" % Build.conduit_cap(lvl + 1, float(s.mods["cap_bonus"])))

	var up := "已滿級"
	if lvl < Build.CAP_MAX_LEVEL:
		var alloy := Build.upgrade_alloy(lvl)
		up = "加粗　%d 礦砂%s" % [
			Build.upgrade_cost(lvl), "" if alloy == 0 else " ＋ %d 合金" % alloy
		]
	var refund := BuildController.conduit_refund(c)
	_show_verbs(up, "拆除　退 %d 礦砂" % refund.x, lvl < Build.CAP_MAX_LEVEL)
	_place_inspect(lines)


## 兩顆鈕的文字與可按性。空字串＝那顆鈕整個收起來。
func _show_verbs(up: String, del: String, up_on: bool = true) -> void:
	_inspect_up.visible = up != ""
	_inspect_up.text = up
	_inspect_up.disabled = not up_on
	_inspect_del.visible = del != ""
	_inspect_del.text = del


## 面板的內容與座標。**兩種選取共用**——版面規則只有一份，不然加第三種選取時
## 會有一種悄悄跑到畫面外（RG-139／149／162／170 都是同一個錯法）。
func _place_inspect(lines: Array[String]) -> void:
	_inspect_label.text = "
".join(lines)
	_inspect_panel.visible = true
	# ── ★ 座標只能是**離散狀態**的函式（B3.9.1，使用者回報「點了升級之後，滑鼠會
	#      位移到一個很奇怪的位置」）───────────────────────────────────────
	#
	#   位移的不是游標，是面板。它的位置本來同時是**內容**的函式：靠右對齊用的是
	#   實際寬度（字一長就往左滑，量到 277 → 383），避讓鄰居判的是實際高度
	#   （多一行就從右緣彈到 x=477）。於是升一級＝兩顆鈕跑掉，而停在原地的游標
	#   落到地圖上，或落到「拆除」上。
	#
	#   兩條規矩：
	#   ① **寬高一律用常數**（`INSPECT_W`／`INSPECT_MAX_H`）算位置與避讓，實際尺寸
	#      只拿來對齊底邊。位置因此只由「鄰居開著沒」決定——那是玩家自己按的開關，
	#      不是每 tick 都在變的數字。
	#   ② **底邊釘住**。兩顆動詞鈕在面板底列，底邊不動＝鈕不動；內容變多時往上長。
	#      頂邊釘住的話，多一行字就把鈕往下推。
	#   ③ ★ B3.10：**尺寸每次自己算，不讀上一次留下的**。自由浮動的 `Control`
	#      只會長不會縮——先點一條導管（面板 258 高）再點一座塔（內容 120），
	#      `size.y` 停在 258，於是底邊釘住之下頂邊高出 140px，塔的資料浮在一塊
	#      空白底板的上緣。B3.9.1 把**寬**改成常數就是為了根治這件事，高度這一半
	#      當時沒改到（那一批的 clicktest 收尾自己寫了 `size = Vector2.ZERO`）。
	#      `get_combined_minimum_size()` 是這一份內容真正要多高，不必等下一幀。
	_inspect_panel.size = Vector2(INSPECT_W, _inspect_panel.get_combined_minimum_size().y)
	var bottom := stage.FRAME.end.y - 12.0
	var pos := Vector2(float(size.x) - INSPECT_W - 24.0, bottom - _inspect_panel.size.y)
	var probe := Rect2(Vector2(pos.x, bottom - INSPECT_MAX_H), Vector2(INSPECT_W, INSPECT_MAX_H))
	# ⚠ **右下角住著三個東西**：能量收支面板（右上）、小地圖（右下）、和它自己。
	#   讓位一律**往左挪，不能往上擠**：能量面板自己就有 358 高，右緣從 y 96 排到
	#   454，小地圖從 525 起——中間只剩 71px，塞不下一個 174px 高的面板。
	#   B3.7 把上限夾在小地圖上緣，結果是面板被推回去壓在能量面板身上
	#   （量到 392–650 對 96–454）——**那只是把一個重疊換成另一個重疊**
	#   （`版面=false` 從 B3.8 就紅著）。
	if _energy_panel != null and _energy_panel.visible:
		var energy := Rect2(_energy_panel.position, _energy_panel.size)
		if probe.intersects(energy):
			pos.x = maxf(stage.FRAME.position.x + 12.0, energy.position.x - INSPECT_W - 12.0)
			probe.position.x = pos.x
	var mini := overlay.minimap_rect()
	if probe.intersects(mini):
		pos.x = maxf(stage.FRAME.position.x + 12.0, mini.position.x - INSPECT_W - 12.0)
	_inspect_panel.position = pos


## 本 tick 每條導管的**能量**淨流（沿 a→b 為正）。
func energy_net() -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in s.conduits:
		var v: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		out[c["id"]] = v.y
	return out


## 會發電的那些格（發電機、放電中的儲槽、回收者的緩衝）。
func power_sources() -> Dictionary:
	var out: Dictionary = {}
	for n: Dictionary in s.nodes:
		var d := NodeDefs.of(String(n["type"]))
		if float(d.get("power_out", 0.0)) > 0.0 or String(n["type"]) in ["silo", "reclaimer"]:
			out[n["cell"]] = true
	return out


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
## 升級階梯的一個台階講成人話（B3.8）。**四個詞的唯一翻譯處**——
## 圖鑑與檢視面板讀同一支，兩邊各寫一份的話遲早有一邊沒跟上資料表。
func _step_text(step: String) -> String:
	return {
		Build.STEP_POWER: "出力 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_RANGE: "射程 +1 格",
		Build.STEP_ROF: "射速 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_SPLASH: "濺射 +1 格",
	}.get(step, step)


func _codex_lines(type: String) -> Array[String]:
	var def := NodeDefs.of(type)
	var out: Array[String] = [BuildController.price_text(type)]
	out.append({
		"extractor": "礦砂的源頭。只能蓋在礦點上，而且要接到核心才入帳。",
		"generator": "把礦砂燒成能量。全遊戲唯一的電力來源，每台吃 4 礦砂/秒。",
		"smelter": "合金的唯一來源。吃礦砂也吃電，而且待機也吃 10 能量/秒。合金要接到核心才入帳。",
		"breaker": "濺射：打中最前那一隻，順便打它周圍 2.5 格內的每一隻。單打的傷害比錨低。",
		"relay": "轉彎與分岔用。導管只能走直線與 45°，所有拐角都靠它。",
		"silo": "準備期存電、波次期放電。充放電速率受它自己那條導管的 cap 限制。",
		"anchor": "最便宜的塔，物理傷害。護甲是減法，而甲殼有護甲 8。",
		"prism": "最貴的塔，能量傷害穿透一直線。與路徑同一列時可一次貫穿整段。",
		"knell": "不開火。減速 40% ＋ 破甲 25%，多座不疊加，取最強的一座。",
		# `Label` 不解析 Markdown——`**任何**` 會原樣印出兩排星號（B0.7.1／B0.7.3
		# 各犯過一次，這裡是第三處，B1.1 一併掃掉）。強調一律用「」。
		"reclaimer": "射程內「任何」敵人死亡就回收能量，不限自己擊殺。",
		"longcall": "射程 12，一座蓋掉大圖的一個象限。每瓦傷害中等。",
		"frostreef": "不開火。減速 65%（潮鳴 40%），「沒有」破甲，射程 3，電費是潮鳴的 1.8 倍。減速與破甲各自取最大。",
		"ballast": "血量 90（其餘塔 60），每瓦傷害全場最高。造價 240 礦砂 ＋ 100 合金。",
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
	# ★ B3.8：把三級的階梯寫在**花錢之前**看得到的地方（§4.3）。
	#   「每一級加的不是同一樣東西」如果只有升級當下才看得到，玩家在擺位時
	#   就沒有辦法把它算進去——而擺位是本作的主要決策。
	var ladder := PackedStringArray()
	for lv in Build.NODE_MAX_LEVEL:
		ladder.append("%d 級 %s" % [lv + 1, _step_text(Build.next_step(type, lv))])
	out.append("升級　" + "　→　".join(ladder))
	return out


func _on_toggle_priority(open: bool) -> void:
	_prio_panel.visible = open


## 一條滑桿推的是**整列**（`NodeDefs.priority_members`，B2.4）。`FlowNetwork`
## 仍然逐 type 讀 `priorities[type]`——合併只發生在這裡，模擬層不知道有這回事。
func _on_priority(row: String, delta: int) -> void:
	for type: String in NodeDefs.priority_members(row):
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


## 建造欄的段標題（B2.4.2）。`text.xs` ＋ `text.secondary`——它是分界不是內容，
## 不該和鈕搶注意力。**不畫線**：兩段之間本來就有 2px 間距 ＋ 一個矮標題，
## 再加一條線就是同一個分界講兩次（§4.3b「同一個位置上的兩個訊息」的同一條）。
func _section_label(text: String) -> Control:
	var l := UiKit.label(text, 11, Palette.TEXT_SECONDARY, false)
	l.custom_minimum_size = Vector2(0, 16)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## ★ B3.7.1：建造鈕改成**開關**（使用者指定「按一下選擇，再按一下取消選擇」）。
##
## 手上什麼都沒拿的時候，左鍵就純粹是檢視——點節點看節點、點導管看導管、
## 點空地什麼都不做。那也是**在有導管經過的格子上蓋東西**之外，另一個
## 「我只是想看一下」的正常需求。
##
## ⚠ 放開那一支要**確認自己還是當前那一個才清空**。同一個 `ButtonGroup` 換鈕時
##   會先後送出「舊的 false」與「新的 true」兩個事件，而兩者的順序不是這裡能
##   假設的——沒有這個守衛，換鈕有一半的機率把剛選好的那一個清掉。
func _on_build_type(pressed: bool, type: String) -> void:
	if not pressed:
		if build_type == type:
			build_type = ""
			_message = ""
			_refresh_hint()
		return
	mode = Mode.BUILD
	build_type = type
	drag_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


# ── 藍圖庫（B2.3、`10_GDD.md` §3.7）───────────────────────────────────

## 這一份存檔有幾個槽。**吃的是玩家的科技，不是這一局的 `s.mods`**——
## 藍圖庫是跨局資產（§3.7），而每日挑戰的統一配置榜會把 `s.mods` 壓成中性值
## （憲法 B3）。用 `s.mods` 的話，打統一配置榜時玩家的槽會憑空少兩個。
func _bp_slots() -> int:
	var unlocked: Array = (GameState.data.get("tech", {}) as Dictionary).get("unlocked", [])
	return Blueprint.slots(Tech.mods(unlocked))


func blueprints() -> Array:
	return GameState.data.get("blueprints", [])


## 框選存檔。
func _save_blueprint(a: Vector2i, b: Vector2i) -> void:
	var bp := Blueprint.capture(s.nodes, s.conduits, a, b)
	var err := SaveService.add_blueprint(GameState.data, bp, _bp_slots())
	if err != "":
		_message = err
		return
	SaveService.save_from(GameState.data)
	var cost: Dictionary = Blueprint.cost(bp)
	_message = "✔ 已存為藍圖　%d 節點・%d 導管　展開要 %d 礦砂" % [
		(bp["nodes"] as Array).size(), (bp["conduits"] as Array).size(), int(cost["ore"])
	]
	_refresh_blueprints()


## 把手上那張藍圖放在 `cell`。**全有全無**（`BuildController.blueprint_place`）。
func _expand_blueprint(cell: Vector2i) -> void:
	var list := blueprints()
	if bp_index < 0 or bp_index >= list.size():
		bp_index = -1
		return
	var err := BuildController.blueprint_place(s, list[bp_index], cell)
	if err != "":
		_message = err
		return
	AudioBus.play("build_place")
	# 放完就放下它。**不留在手上**：藍圖是「一次把一整條產線種下去」，
	# 連放兩次的自然結果是兩份重疊在一起而第二份整份失敗。
	bp_index = -1
	_message = "✔ 藍圖已展開"
	_refresh_blueprints()
	redraw()


func _on_toggle_blueprint(open: bool) -> void:
	_bp_panel.visible = open
	if open:
		_refresh_blueprints()


## 重畫藍圖抽屜。列出每一張的名字、成本，以及兩顆鈕（展開／刪除）。
func _refresh_blueprints() -> void:
	if _bp_panel == null:
		return
	var col: VBoxContainer = _bp_panel.get_child(0)
	UiKit.clear(col)
	var list := blueprints()
	col.add_child(UiKit.label(
		"藍圖庫　%d／%d 槽" % [list.size(), _bp_slots()], 16, Palette.TEXT_PRIMARY, false
	))
	col.add_child(UiKit.label(
		"框選：切「藍圖」→ 在地圖上按住拖出一個框",
		13, Palette.TEXT_SECONDARY, false
	))
	if list.is_empty():
		col.add_child(UiKit.label("（尚無藍圖）", 13, Palette.TEXT_SECONDARY, false))
		return
	for i in list.size():
		var bp: Dictionary = list[i]
		var cost: Dictionary = Blueprint.cost(bp)
		var row := UiKit.hbox(6)
		col.add_child(row)
		# 成本寫在清單上，**不是等玩家點下去才知道**（§3.7「自動計算成本」）。
		var alloy_part := "" if int(cost["alloy"]) <= 0 else "・%d 合金" % int(cost["alloy"])
		row.add_child(UiKit.label("%s　%d 礦砂%s" % [
			String(bp.get("name", "")), int(cost["ore"]), alloy_part
		], 13, Palette.TEXT_PRIMARY, false))
		var take := Button.new()
		take.text = "放下" if bp_index == i else "展開"
		take.pressed.connect(_on_take_blueprint.bind(i))
		row.add_child(UiKit.touchable(take))
		var del := Button.new()
		del.text = "刪除"
		del.pressed.connect(_on_delete_blueprint.bind(i))
		row.add_child(UiKit.touchable(del))


func _on_take_blueprint(i: int) -> void:
	# 再按一次＝放下。拿著藍圖時左鍵會展開它，沒有取消的手勢就等於卡住。
	bp_index = -1 if bp_index == i else i
	if bp_index >= 0:
		mode = Mode.BUILD
		_message = "藍圖在手上：左鍵點地圖放下它（再按一次「放下」取消）"
	_refresh_blueprints()
	redraw()


func _on_delete_blueprint(i: int) -> void:
	var list := blueprints()
	if i < 0 or i >= list.size():
		return
	list.remove_at(i)
	GameState.data["blueprints"] = list
	SaveService.save_from(GameState.data)
	bp_index = -1
	_refresh_blueprints()


## 藍圖鈕。同建造鈕，`toggled` ＋ 再按一次回到建造（B3.7.1）。
func _on_mode(pressed: bool, new_mode: int) -> void:
	if not pressed:
		if mode == new_mode:
			mode = Mode.BUILD
			_message = ""
			_refresh_hint()
		return
	mode = new_mode
	# 換模式就放下手上的藍圖：拿著它的時候左鍵是「展開」，而玩家切走
	# 是為了做別的事——留著會讓下一次左鍵做出他沒想要的事。
	if bp_index >= 0:
		bp_index = -1
		_refresh_blueprints()
	drag_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


func _refresh_top() -> void:
	_refresh_summon()
	# ★ 快進鈕自己講自己開沒開（B2.4.4）。它不是 toggle（按下去只是切換 tick 倍率），
	#   所以在此之前**畫面上唯一的指示是頂欄那段「▶4×」**——因在底欄、果在頂欄。
	if _ff_button != null:
		_ff_button.text = "▶ 快進中 4×" if s.speed_mult > 1 else "快進 4×"
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
	# 一欄一列：[數值, 註腳, 顏色]。順序與 `TOP_CELLS` 一致。
	# 合金緊貼礦砂：**兩個都是造價貨幣**，玩家看的是同一個問題（我買得起嗎）。
	# 「能量需求為什麼突然翻倍」這個問題的答案永遠是交戰座數（§7.4 峰值約束），
	# 所以它掛在能量那一格旁邊當註腳，不是一個獨立的數字。
	var texts := [
		[UiKit.commas(int(s.ore)), "▲%.1f/秒" % r["ore_in"], Palette.ORDER_CYAN],
		[UiKit.commas(int(s.alloy)), "▲%.1f/秒" % r["alloy_in"], Palette.ALLOY_VIOLET],
		[
			"%.0f/%.0f" % [r["power_supply"], r["power_demand"]],
			"交戰 %d 座" % int(r["engaged"]),
			Palette.ENERGY_AMBER,
		],
		# ★ 擊殺數**不在頂欄**（B2.4.4）：它是計分不是決策輸入——沒有任何一個
		#   當下的操作取決於它，而頂欄的每一格都要為「我現在該做什麼」服務。
		#   它在局末結算裡；回收者換到的能量在能量面板有專屬一列。
		[
			_phase_parts()[0], _phase_parts()[1],
			Palette.TIDE_MAGENTA if s.phase == "wave" else Palette.TEXT_SECONDARY,
		],
		["%.0f/%.0f" % [maxf(0.0, s.core_hp()), core_full], "", core_col],
	]
	for i in texts.size():
		var col: Color = texts[i][2]
		_top_values[i].text = String(texts[i][0])
		_top_values[i].add_theme_color_override("font_color", col)
		_top_notes[i].text = String(texts[i][1])
		# 註腳走同一個色相但降一階字級：**顏色維持分群，層級交給字級**
		# （§7.2 B-2：顏色分群是這一批做對的事，要留著）。
		_top_notes[i].add_theme_color_override("font_color", Palette.alpha(col, 0.7))
	# ★ 倒數最後 10 秒脈動（`20_ART_DIRECTION.md` §4.3「一定要動」清單，B1.6）。
	#   **它動的是階段那一格**，不是整條頂欄——脈動要指向「時間快到了」這一件事。
	#   週期用 `dur.slow`：比環境呼吸急、又不到讓人分心的程度。
	var phase_label := _top_values[3]
	var urgent: bool = s.phase == "prep" and s.prep_time() - s.phase_time <= 10.0
	phase_label.modulate = Palette.MOD_FULL
	if urgent:
		phase_label.add_theme_color_override("font_color", Palette.WARN_ORANGE)
		phase_label.modulate = Palette.mod_alpha(Motion.pulse01(s.tick_count, Motion.SLOW, 0.45))


## 準備期顯示倒數（**計時器就在畫面上**——它是關卡參數不是隱藏係數，§7.7）。
##
## ★ 回傳 `[主, 附屬]` 兩段（B2.4.4）：主的是「我還有多少時間／現在第幾波」
## （`text.lg`），附屬的是波號、快進倍率、殘敵（`text.sm`）。
## **原本是一整串塞在同一個 22px 的標籤裡**，量到那一格 299px、把整條頂欄
## 撐出畫面 —— 而它裡面本來就有兩階資訊。
func _phase_parts() -> Array:
	# ★ 難度層掛在附屬那一段（B2.6）。**只在第 1 層以上出現**：第 0 層寫「標準」
	#   等於在每一局的頂欄佔一格去講「沒有任何額外規則」。
	var tier := "　%s" % Difficulty.of(s.difficulty)["name"] if s.difficulty > 0 else ""
	match s.phase:
		"prep":
			var left: float = maxf(0.0, s.prep_time() - s.phase_time)
			# ★ 快進倍率**不在這裡**（B2.4.4）：它原本同時出現在頂欄與底欄那顆
			#   「快進 4×」鈕上，而那顆鈕自己**看不出開沒開**（它不是 toggle）。
			#   指示搬到按鈕上——因與果放在同一個地方，頂欄也省下一段會變長的字。
			# 駐足在核心的敵人不會隨波次結束而消失（§3.5）。不講的話，
			# 玩家會看到核心在準備期掉血卻找不到原因。
			var left_over := "　殘敵 %d" % s.enemies.size() if not s.enemies.is_empty() else ""
			return ["準備期 %0.1fs" % left, "下一波 %d%s%s" % [s.wave_index + 1, left_over, tier]]
		"wave":
			return ["第 %d 波" % s.wave_index, "敵人 %d%s" % [s.enemies.size(), tier]]
		"won":
			return ["通關", ""]
		_:
			return ["核心已毀", ""]


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
		# ★ 每日挑戰記在自己那一格，不混進無盡的個人最佳（B2.2）：兩者的地圖
		#   來源一樣，但無盡是「隨便一張圖能撐多久」、每日是「今天這張圖」。
		#   混在一起會讓無盡的紀錄被一張特別好打的日圖洗掉。
		var daily: bool = daily_board != ""
		# ★ 無盡的紀錄逐難度層各一筆（sv3、`data/Difficulty.gd`）：拿第 0 層的
		#   紀錄去比第 3 層的成績，「破紀錄」那三個字就會變成一句謊。
		var slot: Dictionary = (
			((GameState.data.get("daily", {}) as Dictionary).get("today", {}) as Dictionary)
				.get(daily_board, {})
			if daily else Difficulty.best(GameState.data, difficulty)
		)
		var prev_wave := int(slot.get("wave", 0))
		var prev_output := float(slot.get("output", 0.0))
		var fresh := (
			SaveService.apply_daily(GameState.data, daily_date, daily_board, waves, score)
			if daily else SaveService.apply_endless(GameState.data, waves, score, difficulty)
		)
		SaveService.save_from(GameState.data)
		if daily:
			col.add_child(UiKit.label(
				"每日挑戰　%s　%s" % [
					daily_date, "統一配置" if daily_board == Daily.UNIFORM else "自由配置"
				], 13, Palette.ORDER_CYAN, false
			))
		elif difficulty > 0:
			# 紀錄記在哪一層要說出來，否則「最高波次 8 波」看起來像退步。
			col.add_child(UiKit.label(
				"無盡　%s" % Difficulty.name_of(difficulty), 13, Palette.WARN_ORANGE, false
			))
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
			"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars), 32, Palette.ENERGY_AMBER
		))
		for line: String in _star_lines(stars, score):
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
		if gain > 0.0:
			col.add_child(UiKit.label(
				"關卡獎勵　＋%.0f 研究數據" % gain, 13, Palette.OK_GREEN, false
			))
	# ★ 升級材料（B2.7、§7.15 的第一條路）。**只有戰役與無盡算**——
	#   測試圖與沙盤沒有進度可寫（星等與研究數據的同一條線）。
	#   只數波數：加星數加成的話，重刷第 1 關會比打完第 5 關划算。
	var comps := 0
	if not level.is_empty() or endless_seed != 0:
		comps = SaveService.apply_components(GameState.data, waves)
		if comps > 0:
			SaveService.save_from(GameState.data)
			col.add_child(UiKit.label(
				"升級材料　＋%d（撐過的波數）　現有 %d" % [
					comps, SaveService.components(GameState.data)
				], 13, Palette.OK_GREEN, false
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
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
	# ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」——
	#   上面那幾行是**成績**，這一行才是**原因**。放在按鈕正上方：
	#   玩家的視線在按「立刻重來」之前一定會經過這裡。
	var why := feedback.diag_line(won)
	if why != "":
		var lbl := UiKit.label(
			why, 13, Palette.WARN_ORANGE if not won else Palette.ORDER_CYAN, false
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
	col.add_child(UiKit.label("選單", 32, Palette.ORDER_BRIGHT))
	col.add_child(UiKit.label("時間仍在走。選單不暫停。", 13, Palette.WARN_ORANGE))
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
	_menu_layer = null
	_settings_layer = null
	_menu_button = null
	_menu_buttons.clear()
	_over_panel = null
	_top = null
	# 這兩個陣列裝的是已經 `queue_free()` 掉的 Label——不清就會拿到斷裂的參照。
	_top_values.clear()
	_top_notes.clear()
	_hint = null
	_ff_button = null
	_summon_button = null
	_prio_panel = null
	_bp_panel = null
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
	mode = Mode.BUILD
	build_type = "extractor"
	# 選取要跟著局一起歸零。**`_sel_wire` 存的是 id，而新的一局的 id 從頭發**——
	# 不清的話重開一關會看到面板指著一條玩家沒選過的線（B3.7）。
	selected = Vector2i(-1, -1)
	_sel_wire = -1
	s = SessionState.new()
	_bind_session()
	_setup_session()
	accum = 0.0
	_message = ""
	_build_ui()


func _refresh_hint() -> void:
	# ⚠ **UI 還沒建完就可能被呼叫**（B3.7.1）：`_build_ui()` 裡設建造鈕的
	#   `button_pressed = true` 會當場送出 `toggled`，而那時提示列還沒建出來。
	#   少了這道守衛的症狀不是報錯，是 `_build_ui()` **從那一行起整支中止**
	#   ——半個畫面沒建出來，而畫面自己不會抱怨（RG-164 的形狀）。
	if _hint == null:
		return
	if Hooks.naked:
		_hint.visible = false
		return
	# ★ 兩行：**上行永遠是「下一步」，下行才是當下這個動作的細節。**
	# B0.7 原本讓預覽「取代」下一步，於是玩家把滑鼠移到地圖上——正是最需要
	# 指引的那一刻——指引就消失了。使用者實玩後的第一句話是「你沒教我怎麼操作」。
	var parts: Array[String] = []
	# 拖曳中就只講這一條線連不連得成——這時玩家問的問題只有那一個。
	if drag_from.x >= 0:
		_hint.text = "▶ %s\n%s" % [
			"放開在另一個節點上就拉出一條導管；放開在空地／原地則取消。",
			_connect_hint() if stage.in_map(hover) else "",
		]
		return
	match mode:
		Mode.BUILD:
			# ★ 游標壓在導管上時，落點提示是**錯的**——點下去不會蓋東西（B3.7）。
			#   順便把逃生門講出來：想在這一格蓋，就避開線，往格子邊緣點。
			if bp_index < 0 and s.conduit_near(hover_p, WIRE_PICK) >= 0:
				parts.append("這條導管：左鍵點一下就檢視它，面板上可以加粗或拆除。想在這一格蓋東西，避開線往格子邊緣點。")
			elif build_type == "" and bp_index < 0:
				# ★ B3.7.1：手上什麼都沒拿。**要講得出「現在能做什麼」**，
				#   不然這個狀態讀起來會像「怎麼點都沒反應」。
				parts.append("目前沒有拿著任何節點。左鍵點一座建築或一條導管＝檢視它，面板上就能升級、加粗或拆除。要蓋東西就在左欄點一種。")
			elif stage.in_map(hover):
				parts.append_array(BuildController.preview_place(s, build_type, hover)["lines"])
			else:
				parts.append("建造 %s：左鍵點一格放下；從既有節點按住拖到另一個節點＝拉導管。" % NodeDefs.label(build_type))
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
		return "電有了。左欄點「錨」（最便宜的塔）蓋在「離紫色路徑 2 格以上」的地方。貼太近會被走過的敵人打壞。"
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
		return "都齊了。等倒數跑完自動開波，或按「提前召喚」提早開。倒數剩越多，這一波掉落倍率越高。"
	return "波次進行中：盯著頂端能量條，橙色那截就是餵不飽的部分；節點上的橙色倒三角＝這個缺料。"


## 連線預覽的逐格回報。**連不成的時候要說出差在哪**——「不是 45°」對玩家
## 沒有動作可做，「橫 4 直 3，要 4/4 或 3/3」才有。
func _connect_hint() -> String:
	if s.node_at(hover).is_empty():
		return "終點也要是一個節點（先在那裡蓋一個「中繼」）。"
	var cf := drag_from
	var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, hover, s.conduit_cells()
	)
	if code == Build.NOT_STRAIGHT:
		var d: Vector2i = hover - cf
		return "✕ 不是直線：橫 %d 直 %d。要走 45° 兩邊得一樣長；否則先放一個「中繼」轉彎。" % [
			absi(d.x), absi(d.y)
		]
	if code != Build.OK:
		return "✕ " + BuildController.reason_text(code)
	var cost := Build.conduit_cost(cf, hover)
	var afford := "" if s.ore >= float(cost) else "　（礦砂不夠）"
	return "✔ 可連：%s → %s，%d 礦砂%s" % [
		_label_at(cf), _label_at(hover), cost, afford
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
